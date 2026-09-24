@Tags(['benchmark'])
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/cut_piece.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/display_buffer_cache.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show buildAppTheme;
import 'package:anicel/src/ui/ui_scale_binding.dart';

import '../helpers/home_page_probes.dart';
import '../helpers/panel_finders.dart';
import 'brush_canvas_test_helpers.dart';

/// 🚨**F-130 — 「브러시 커서 프리뷰가 일반 OS 커서보다 느리다 — 일반 커서가
/// 60fps 면 프리뷰는 30fps 느낌」** (유저 2026-09-14/15).
///
/// ⛔**NOT a correctness test** — it prints numbers. Run it with
/// `--run-skipped --tags benchmark`, ALONE on the machine. What it DOES
/// assert is that every arm measured what it says it measured: the cursor
/// really moved, the paint counter really moved when it should, and a
/// quiet frame really was quiet.
///
/// ★**WHAT ONE POINTER MOVE COSTS, PER FRAME, PER ARM.** For every move it
/// records, on the frame the move asks for: whether a frame was scheduled
/// at all, what the frame built (dirty widgets by the key nearest above
/// them), what it painted (render objects by nearest key), how many layers
/// were re-added to the scene (an engine layer whose identity moved =
/// re-submitted, the rest retained), the transient/draw split and the wall
/// clock — plus the DISPATCH cost of the event itself, which is where
/// per-event work (a hit test of the whole tree, an eyedropper sampling the
/// composite) lives and which no frame timer can see. Relayout is read in
/// a SEPARATE untimed pass, because tracing `markNeedsLayout` takes a stack
/// per mark and would be the thing it measures.
///
/// The arms (`F130_ARMS`, default all): `idle` (the brush over a one-cel
/// canvas) · `tools` (eraser · fill · eyedropper · stamp with a held piece;
/// the stamp arm also counts the display buffer's full composes, which a
/// hover must not cause) · `settings` (the tool settings panel open) ·
/// `stroke` (the cursor WHILE the pen is down, and — under `runAsync` — how
/// many frames after the move the ink itself appears) · `after` (hovering in
/// the settle window right after a stroke lands) · `layers` (the same idle
/// hover after seven more drawn layers) · `stream` (a 60-event pointer
/// stream, one frame per event: does the cursor keep 60 — 유저's own
/// terms).
///
/// 🚨★★★**THE CONTROLS ARE THE POINT** ([[adversarial-verify-is-not-
/// optional]]): a quiet pair of pumps before each treatment must read zero
/// painted and no scheduled frame, the arming move must have put the cursor
/// somewhere, and the cursor must have travelled the distance the pointer
/// did — a cursor that stopped following cannot pass as cheap.
///
/// ⚠️ONE MOUSE for the whole run. `flutter_test` gives every mouse gesture
/// the same device, and `MouseTracker` asserts on a second `PointerAdded`
/// for a device it already tracks — so the mouse is added once and moved
/// from arm to arm, never re-created.
///
/// ⚠️Debug build IS the bar ([[debug-build-performance-bar]]); read ratios
/// and object counts, never a debug millisecond as a release one.
void main() {
  testWidgets('F-130: what a cursor move costs, per frame, per arm', (
    tester,
  ) async {
    AnicelBinding.applyFocusHighlightPolicy(FocusManager.instance);
    // 🚨THE HARNESS IS ANDROID unless told otherwise, and the ROUTE the app
    // sits under is chosen by platform: Flutter gives android the predictive
    // back / fade-forwards transition and windows the zoom one. Their
    // leftovers differ — a completed `FadeTransition` keeps a full-window
    // `OpacityLayer` for ever (`RenderAnimatedOpacityMixin` is a repaint
    // boundary at ANY alpha above 0, 255 included) — so a layer census taken
    // on the default harness is a census of Android's chrome, not of what
    // the user is running. `F130_PLATFORM=windows` reads the user's.
    final platform = Platform.environment['F130_PLATFORM'];
    if (platform != null && platform.isNotEmpty) {
      debugDefaultTargetPlatformOverride = TargetPlatform.values.firstWhere(
        (p) => p.name == platform,
      );
    }
    // 🚨THE APP'S OWN THEME, because the theme is what decides the route's
    // transition — and a completed transition's leftovers are half of what
    // this file counts. A bare `MaterialApp` here measured Flutter's
    // defaults and called them the app's.
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();

    // The default project has no cel at the playhead — author one.
    final addButton = find.byKey(const ValueKey<String>('new-frame-button'));
    await tester.ensureVisible(addButton);
    await tester.pumpAndSettle();
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    final canvas = mainCanvasView();
    expect(canvas, findsOneWidget, reason: 'authored cel must be drawable');
    final workspace = tester.widget<EditorWorkspace>(
      find.byType(EditorWorkspace),
    );
    final session = workspace.session;
    final brushTool = workspace.brushTool!;

    final arms = (Platform.environment['F130_ARMS'] ??
            'idle,tools,settings,stroke,after,layers,stream')
        .split(',')
        .map((s) => s.trim())
        .toSet();
    final moves = int.tryParse(Platform.environment['F130_MOVES'] ?? '') ?? 16;
    final probe = _Probe(tester, canvas);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    /// Where the app-drawn cursor under [key] shows, or null — the ALIVE
    /// oracle for a sprite arm. Scoped to the MAIN canvas: every panel with
    /// the tool armed mounts its sprite now (the timesheet's and the
    /// conte's show nothing, having no aim), so a bare key finds several.
    Offset? Function() shownUnder(String key) => () => toolCursorShownAt(
      tester,
      find.descendant(
        of: mainCanvasPanelShell(),
        matching: find.byKey(ValueKey<String>(key)),
      ),
    );

    Future<void> hoverArm(
      String label, {
      required CanvasTool tool,
      required String? cursorKey,
      Duration? realTimeBefore,
    }) async {
      await probe.armTool(brushTool, tool);
      await probe.measureHover(
        label,
        mouse,
        moves: moves,
        shownAt: cursorKey == null ? null : shownUnder(cursorKey),
        realTimeBefore: realTimeBefore,
      );
    }

    if (arms.contains('idle')) {
      await hoverArm(
        'idle-brush',
        tool: CanvasTool.brush,
        cursorKey: 'brush-cursor-overlay',
      );
    }

    if (arms.contains('tools')) {
      await hoverArm(
        'eraser',
        tool: CanvasTool.eraser,
        cursorKey: 'brush-cursor-overlay',
      );
      await hoverArm('fill', tool: CanvasTool.fill, cursorKey: 'fill-cursor-icon');
      await hoverArm(
        'eyedropper',
        tool: CanvasTool.eyedropper,
        cursorKey: 'eyedropper-cursor-icon',
      );
      // The stamp needs a piece in hand. A 64x64 opaque square, held on the
      // panel's own slot — the same object the cut tool would fill.
      final slot = tester
          .widget<BrushCanvasPanel>(mainCanvasPanelShell())
          .cutPieceSlot!;
      final rgba = Uint8List(64 * 64 * 4);
      for (var i = 0; i < rgba.length; i += 4) {
        rgba[i] = 0x20;
        rgba[i + 1] = 0x80;
        rgba[i + 2] = 0xC0;
        rgba[i + 3] = 0xFF;
      }
      slot.hold(
        CutPiece(
          image: BrushStampImage(
            id: 'f130-bench-piece',
            width: 64,
            height: 64,
            rgba: rgba,
          ),
          originLeft: 0,
          originTop: 0,
        ),
      );
      await tester.pumpAndSettle();
      final stackState =
          tester.state(find.byType(CanvasLayerStackView)) as dynamic;
      // The state class is private; its testing seam is reachable this way
      // only (the backdrop predicate test reads `debugBake` the same way).
      // ignore: avoid_dynamic_calls
      final buffers = stackState.debugBufferCacheInUse as DisplayBufferCache;
      final fullBefore = buffers.fullCount;
      final patchedBefore = buffers.patchedCount;
      // Real time between moves, so the buffer's snapshot promotion (a
      // `toImage`) lands the way it does in the app: without it every patch
      // draws FROM the deferred head and re-rasters its recipe — a cost the
      // harness makes, not the app.
      await hoverArm(
        'stamp',
        tool: CanvasTool.cutStamp,
        cursorKey: null,
        realTimeBefore: const Duration(milliseconds: 20),
      );
      // ignore: avoid_print
      print(
        '[F130] stamp: display buffer full composes '
        '${buffers.fullCount - fullBefore}, patches '
        '${buffers.patchedCount - patchedBefore} over the arm (arming + 4 '
        'warm-up + $moves measured + 4 relayout-probe moves = ${moves + 9}; '
        'a hover that recomposites the whole buffer per move reads as that '
        'many full composes — the cost this arm exists to show)',
      );
      await probe.armTool(brushTool, CanvasTool.brush);
    }

    if (arms.contains('settings')) {
      // The tool settings group ships CLOSED on the left rail (slot 2);
      // H30's `H30_OPEN_SETTINGS` opened it the same way.
      final group = EditorWorkspace.railGroupId(right: false, slot: 2);
      final groupButton = find.byKey(ValueKey<String>('rail-group-$group'));
      await tester.tap(groupButton);
      await tester.pumpAndSettle();
      await hoverArm(
        'settings-open',
        tool: CanvasTool.brush,
        cursorKey: 'brush-cursor-overlay',
      );
      await tester.tap(groupButton);
      await tester.pumpAndSettle();
    }

    if (arms.contains('stroke')) {
      await probe.armTool(brushTool, CanvasTool.brush);
      await probe.measureStroke('stroke-down', moves: moves);
      await probe.measureInkFrames('ink-latency', moves: 6);
    }

    if (arms.contains('after')) {
      await probe.armTool(brushTool, CanvasTool.brush);
      await probe.measureAfterStroke('after-pen-up', mouse, moves: moves);
    }

    if (arms.contains('layers')) {
      await probe.armTool(brushTool, CanvasTool.brush);
      // Seven more layers, each with its own cel and one stroke on it, so
      // the composite under the cursor holds eight drawn rows.
      for (var i = 0; i < 7; i += 1) {
        await addLayer(tester);
        await tester.ensureVisible(addButton);
        await tester.pumpAndSettle();
        await tester.tap(addButton);
        await tester.pumpAndSettle();
        await probe.drawOneStroke(session);
        // ignore: avoid_print
        print(
          '[F130] layers: added layer ${i + 2}, active layer now '
          '${session.activeLayer?.id.value}',
        );
      }
      final rows = timelineLayerRows().evaluate().length;
      // ignore: avoid_print
      print('[F130] layers: the timeline now shows $rows layer rows');
      await hoverArm(
        'eight-layers',
        tool: CanvasTool.brush,
        cursorKey: 'brush-cursor-overlay',
      );
    }

    if (arms.contains('stream')) {
      // 🗣️유저's own terms (2026-09-15): the OS cursor moves at 60, the
      // app's tool cursor at 30 — does the cursor KEEP 60? A pointer
      // stream at display rate: one move, one frame, sixty times. Every
      // frame must show the cursor where that frame's move put it (a
      // frame the cursor missed is the 30 the user sees), and the frame's
      // cost says how much of the 16.67ms budget a move takes.
      await probe.armTool(brushTool, CanvasTool.brush);
      await probe.measureStream(
        'stream-60hz',
        mouse,
        moves: 60,
        shownAt: shownUnder('brush-cursor-overlay'),
      );
    }

    if (arms.contains('solo')) {
      // 🗣️유저 2026-09-23, through the board/integration session's own
      // measurement (board `I-19`): 「솔로 버벅임」 — ONE FRAME of layer
      // select 260ms · solo on 132ms · solo off 331ms with 24 inked rows,
      // and their counts put the difference outside the widgets (solo on and
      // off rebuild the same 3,051 elements and paint the same 4,104 render
      // objects, yet off costs +200ms). This arm reads the CANVAS side of
      // those same three verbs, and every frame each one costs until the
      // app is quiet again. Run it with `--dart-define=BRUSH_LAB_PROFILE=true`
      // and the lab probes inside the frame print their share.
      //
      // 🔬CORRECTED ON THE DEVICE the same day (the real Windows app on its
      // GPU, debug, 24 inked rows, the engine's `FrameTiming`): the first
      // frame's UI thread is select 26ms · solo on 55ms · solo off 66ms,
      // its raster 5-9ms, and the canvas side of that UI work stays under
      // the probes' 4ms floor. The +200ms is the TEST VM's — flutter_tester
      // rasterises on the CPU and inflates exactly that composite tens of
      // times over. So the stutter's body is the WIDGET rebuild (board
      // `an-eye-rebuilds-its-whole-row`): this arm's counts stand, its
      // milliseconds are not the device's, and a device cost is read by an
      // integration test on the device (board `brush-render-roadmap`).
      final rows =
          int.tryParse(Platform.environment['F130_SOLO_ROWS'] ?? '') ?? 24;
      await probe.armTool(brushTool, CanvasTool.brush);
      await probe.drawOneStroke(session);
      for (var i = 1; i < rows; i += 1) {
        await addLayer(tester);
        await tester.ensureVisible(addButton);
        await tester.pumpAndSettle();
        await tester.tap(addButton);
        await tester.pumpAndSettle();
        await probe.drawOneStroke(session);
      }
      // Let the prerender warm what it warms at rest, as the user's app does
      // between clicks.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      final layers = session.layers;
      // ignore: avoid_print
      print('[F130] solo: ${layers.length} rows, active '
          '${session.activeLayer?.id.value}');
      final other = layers.firstWhere(
        (layer) => layer.id != session.activeLayer?.id,
      );
      await probe.measureVerb(
        'select-a-row',
        () => session.selectLayer(other.id),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await probe.measureVerb(
        'solo-on',
        session.visibilitySolo.toggleLayerVisibilitySolo,
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await probe.measureVerb(
        'solo-off',
        session.visibilitySolo.toggleLayerVisibilitySolo,
      );
    }

    // Drain the prerender scheduler's debounced warming (a pending timer at
    // teardown fails the harness's invariants).
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    // ⚠️IN THE BODY, not `addTearDown`: the harness checks the foundation
    // debug variables between the body and the tear-downs, so a platform
    // override released there fails the test it already measured.
    debugDefaultTargetPlatformOverride = null;
  }, timeout: const Timeout(Duration(minutes: 20)));
}

/// One frame's reading.
class _FrameReading {
  int dispatchMicros = 0;
  int pumpMicros = 0;
  int transientMicros = 0;
  int drawMicros = 0;
  bool frameScheduled = false;
  int painted = 0;
  final Map<String, int> paintedBy = <String, int>{};
  final Map<String, int> rebuiltBy = <String, int>{};
  final Map<String, int> relayoutBy = <String, int>{};

  /// Who dirtied a widget, in the traced pass: `widget ← app frame` — the
  /// first stack frame in this app's own code under `markNeedsBuild`.
  final Map<String, int> buildCausesBy = <String, int>{};
  int layersReadded = 0;

  /// WHICH layers were re-added, by layer type and the render object that
  /// created it. A count alone cannot be acted on: 「85 re-added」 is the
  /// same reading whether it is the cursor's own chain or every panel in
  /// the app, and those want opposite fixes.
  final Map<String, int> layersReaddedBy = <String, int>{};

  /// Layer OBJECTS that were not in the tree one frame ago — a subtree
  /// that was rebuilt rather than moved.
  int layersFresh = 0;
  final Map<String, int> layersFreshBy = <String, int>{};

  /// Picture layers whose `ui.Picture` is a new object after the frame: a
  /// re-record. Counts a repaint boundary repainting ITSELF, which the
  /// paint-profile hook (called only from a parent's `paintChild`) cannot
  /// see — a sprite that re-records its own picture shows up here.
  int picturesRerecorded = 0;
}

/// The instrument: drives pointers and reads every counter around one pump.
class _Probe {
  _Probe(this.tester, this.canvas);

  final WidgetTester tester;
  final Finder canvas;

  final Stopwatch clock = Stopwatch()..start();
  int _drawFrameDoneAt = 0;
  int _transientDoneAt = 0;
  bool _installed = false;
  Set<RenderObject>? _canvasRenderObjects;
  List<Offset>? _bareCanvas;
  int _strokeIndex = 0;

  /// How far one stroke's moves carry it.
  static const Offset strokeTravel = Offset(8 * 7.0, 8 * 4.0);

  void _install() {
    if (_installed) {
      return;
    }
    _installed = true;
    // A persistent callback registered after the renderer's own fires once
    // build → layout → paint is done (the H30 split, kept verbatim).
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      _drawFrameDoneAt = clock.elapsedMicroseconds;
    });
  }

  /// Whether a pointer at [point] would be delivered to the canvas view —
  /// membership of the hit-test PATH, not the deepest entry (H30).
  bool onCanvas(Offset point) {
    final mine = _canvasRenderObjects ??= () {
      final found = <RenderObject>{};
      void walk(Element element) {
        final renderObject = element.renderObject;
        if (renderObject != null) {
          found.add(renderObject);
        }
        element.visitChildElements(walk);
      }

      walk(canvas.evaluate().single);
      return found;
    }();
    return tester
        .hitTestOnBinding(point)
        .path
        .any((entry) => mine.contains(entry.target));
  }

  /// A bare-canvas start: hit-test chosen, like H30 (chrome lies ON this
  /// canvas, so coordinates alone put strokes on floating panels).
  Offset strokeStart(int index) {
    final points = _bareCanvas ??= () {
      final rect = tester.getRect(canvas);
      final found = <Offset>[];
      for (var row = 1; row < 20; row += 1) {
        for (var column = 1; column < 20; column += 1) {
          final point = Offset(
            rect.left + rect.width * column / 20,
            rect.top + rect.height * row / 20,
          );
          if (onCanvas(point) && onCanvas(point + strokeTravel)) {
            found.add(point);
          }
        }
      }
      return found;
    }();
    expect(
      points.length,
      greaterThanOrEqualTo(8),
      reason: 'the hit-test found too few bare-canvas starts',
    );
    return points[index % points.length];
  }

  static String regionOf(RenderObject renderObject) {
    final creator = renderObject.debugCreator;
    if (creator is! DebugCreator) {
      return '(no creator)';
    }
    return _regionOfElement(creator.element);
  }

  static String _regionOfElement(Element element) {
    final own = element.widget.key;
    if (own is ValueKey<String>) {
      return own.value;
    }
    var region = '(no key)';
    element.visitAncestorElements((ancestor) {
      final key = ancestor.widget.key;
      if (key is ValueKey<String>) {
        region = key.value;
        return false;
      }
      return true;
    });
    return region;
  }

  /// Every layer's engine layer, by identity — a layer whose engine layer
  /// changed between two frames was re-added to the scene; one that kept it
  /// was retained. And every picture layer's picture, the same way.
  ({Map<Layer, Object?> engine, Map<Layer, ui.Picture?> pictures})
  _engineLayers() {
    final out = <Layer, Object?>{};
    final pictures = <Layer, ui.Picture?>{};
    void walk(Layer layer) {
      // ignore: invalid_use_of_protected_member
      out[layer] = layer.engineLayer;
      if (layer is PictureLayer) {
        pictures[layer] = layer.picture;
      }
      if (layer is ContainerLayer) {
        var child = layer.firstChild;
        while (child != null) {
          walk(child);
          child = child.nextSibling;
        }
      }
    }

    for (final view in RendererBinding.instance.renderViews) {
      // ignore: invalid_use_of_protected_member
      final root = view.layer;
      if (root != null) {
        walk(root);
      }
    }
    return (engine: out, pictures: pictures);
  }

  /// Runs [act] (the pointer work) and then ONE pump, reading everything.
  /// [traceLayout] captures `markNeedsLayout` stacks — costly, so it is
  /// only on in the untimed relayout pass.
  Future<_FrameReading> measureOne(
    Future<void> Function() act, {
    bool traceLayout = false,
  }) async {
    _install();
    final reading = _FrameReading();
    final layersBefore = _engineLayers();
    final relayoutLines = <String>[];
    final previousPrint = debugPrint;
    // A `markNeedsBuild` stack: the label line names the widget, the frames
    // follow; the first frame inside this app is the cause.
    String? dirtiedWidget;
    var causeFound = false;
    if (traceLayout) {
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message == null) {
          return;
        }
        for (final line in message.split('\n')) {
          if (line.startsWith('markNeedsLayout() called')) {
            relayoutLines.add(line);
          } else if (line.startsWith('scheduleBuildFor() called for ')) {
            dirtiedWidget = line
                .substring('scheduleBuildFor() called for '.length)
                .split('(')
                .first;
            causeFound = false;
          } else if (dirtiedWidget != null &&
              !causeFound &&
              line.contains('package:anicel/')) {
            final at = line.indexOf('package:anicel/');
            final cause = line.substring(at + 'package:anicel/'.length).split(')').first;
            final key = '$dirtiedWidget ← $cause';
            reading.buildCausesBy[key] = (reading.buildCausesBy[key] ?? 0) + 1;
            causeFound = true;
          }
        }
      };
      debugPrintMarkNeedsLayoutStacks = true;
      debugPrintScheduleBuildForStacks = true;
    }
    debugOnRebuildDirtyWidget = (element, _) {
      final key =
          '${element.widget.runtimeType}@${_regionOfElement(element)}';
      reading.rebuiltBy[key] = (reading.rebuiltBy[key] ?? 0) + 1;
    };
    var painted = 0;
    debugOnProfilePaint = (renderObject) {
      painted += 1;
      final region = regionOf(renderObject);
      reading.paintedBy[region] = (reading.paintedBy[region] ?? 0) + 1;
    };
    debugProfilePaintsEnabled = true;
    try {
      final dispatch = clock.elapsedMicroseconds;
      await act();
      reading.dispatchMicros = clock.elapsedMicroseconds - dispatch;
      reading.frameScheduled = SchedulerBinding.instance.hasScheduledFrame;
      _transientDoneAt = 0;
      // `scheduleNewFrame: false`: the probe must not manufacture the frame
      // it is measuring — a quiet pump has to stay a non-frame.
      SchedulerBinding.instance.scheduleFrameCallback(
        (_) => _transientDoneAt = clock.elapsedMicroseconds,
        scheduleNewFrame: false,
      );
      final t0 = clock.elapsedMicroseconds;
      _drawFrameDoneAt = 0;
      await tester.pump();
      reading.pumpMicros = clock.elapsedMicroseconds - t0;
      if (_transientDoneAt > 0 && _drawFrameDoneAt > 0) {
        reading.transientMicros = _transientDoneAt - t0;
        reading.drawMicros = _drawFrameDoneAt - _transientDoneAt;
      }
    } finally {
      debugProfilePaintsEnabled = false;
      debugOnProfilePaint = null;
      debugOnRebuildDirtyWidget = null;
      debugPrintMarkNeedsLayoutStacks = false;
      debugPrintScheduleBuildForStacks = false;
      debugPrint = previousPrint;
    }
    reading.painted = painted;
    for (final line in relayoutLines) {
      // "markNeedsLayout() called for RenderStack#abc12 relayoutBoundary=…"
      final rest = line.substring('markNeedsLayout() called for '.length);
      final type = rest.split('#').first;
      reading.relayoutBy[type] = (reading.relayoutBy[type] ?? 0) + 1;
    }
    final layersAfter = _engineLayers();
    // 🚨★★★**A LAYER WITH NO ENGINE LAYER CANNOT ANSWER THIS QUESTION**
    // (2026-09-22). `PictureLayer.addToScene` calls `builder.addPicture`,
    // which returns nothing, so a picture layer's `engineLayer` is null for
    // ever. The first version of this counter read a null as "its engine
    // layer changed", so EVERY picture in the tree counted as re-added on
    // EVERY frame: 85/frame for an idle hover, of which 72 were pictures
    // that had not moved and whose `ui.Picture` objects were identical —
    // the re-record column right beside it read 0 and said so.
    //
    // ⛔That number went on the F-130 card as a cost to cut (「층 84~114개
    // 재추가」). It was the instrument. What is below is the question the
    // column was written to ask: a CONTAINER layer that came back with a
    // new engine layer was re-submitted to the scene instead of retained.
    var readded = 0;
    var fresh = 0;
    void name(Map<String, int> into, Layer layer) {
      final creator = layer.debugCreator;
      final owner = switch (creator) {
        null => '',
        final RenderObject object => ' <${object.runtimeType}>',
        _ => ' <${creator.toString().split('\n').first}>',
      };
      final key = '${layer.runtimeType}$owner';
      into[key] = (into[key] ?? 0) + 1;
    }

    for (final entry in layersAfter.engine.entries) {
      final layer = entry.key;
      final after = entry.value;
      if (!layersBefore.engine.containsKey(layer)) {
        // A Layer OBJECT that was not in the tree a frame ago. Also real
        // work, and a different defect from a re-submitted one.
        fresh += 1;
        name(reading.layersFreshBy, layer);
        continue;
      }
      final before = layersBefore.engine[layer];
      if (before == null && after == null) {
        continue;
      }
      if (!identical(before, after)) {
        readded += 1;
        name(reading.layersReaddedBy, layer);
      }
    }
    reading.layersReadded = readded;
    reading.layersFresh = fresh;
    var rerecorded = 0;
    for (final entry in layersAfter.pictures.entries) {
      final before = layersBefore.pictures[entry.key];
      if (before == null || !identical(before, entry.value)) {
        rerecorded += 1;
      }
    }
    reading.picturesRerecorded = rerecorded;
    return reading;
  }

  /// Two pumps with NO input. Prints what they cost; a treatment measured
  /// on a machine that is not quiet is noise, and this says so.
  Future<void> control(String label) async {
    final a = await measureOne(() async {});
    final b = await measureOne(() async {});
    // ignore: avoid_print
    print(
      '[F130] $label control: painted ${a.painted}/${b.painted} '
      'rebuilt ${_sum(a.rebuiltBy)}/${_sum(b.rebuiltBy)} '
      'scheduled ${a.frameScheduled}/${b.frameScheduled} '
      'pump ${_ms(a.pumpMicros)}/${_ms(b.pumpMicros)}ms'
      '${(a.painted == 0 && b.painted == 0) ? '' : '  ⚠️NOT QUIET'}',
    );
  }

  /// One VERB — not a pointer — and every frame it costs until the app is
  /// quiet again: the frame the verb asks for, then each frame the passes
  /// it started ask for. A composition that lands late is a frame of its
  /// own, and a stutter spread over three frames is still a stutter.
  Future<void> measureVerb(String label, void Function() verb) async {
    // ignore: avoid_print
    print('[F130] >>> $label');
    // ⚠️The counting hooks [measureOne] installs (build and paint profiling)
    // are part of what they time, and they bill per WIDGET — so a verb that
    // rebuilds a lot reads heavier than it is, next to one whose cost is a
    // raster. `F130_PLAIN` times the same frames with nothing installed.
    if (Platform.environment['F130_PLAIN'] != null) {
      final times = <int>[];
      final watch = Stopwatch()..start();
      verb();
      await tester.pump();
      times.add(watch.elapsedMicroseconds);
      for (var frame = 0;
          frame < 30 && tester.binding.hasScheduledFrame;
          frame += 1) {
        watch
          ..reset()
          ..start();
        await tester.pump(const Duration(milliseconds: 16));
        times.add(watch.elapsedMicroseconds);
      }
      // ignore: avoid_print
      print('[F130] $label (plain): frames ${times.map(_ms).join(' ')}');
      return;
    }
    final first = await measureOne(() async => verb());
    final later = <int>[];
    for (var frame = 0;
        frame < 30 && tester.binding.hasScheduledFrame;
        frame += 1) {
      final watch = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 16));
      watch.stop();
      later.add(watch.elapsedMicroseconds);
    }
    // Eight kinds of rebuild, not four: the stutter's body is the rebuild
    // (the correction on the `solo` arm), and the solo meter that was a
    // second copy of this arm read eight before it was folded in here.
    // ignore: avoid_print
    print(
      '[F130] $label: first frame ${_ms(first.pumpMicros)}ms (the verb '
      '${_ms(first.dispatchMicros)}ms) | rebuilt ${_sum(first.rebuiltBy)} '
      '{${_top(first.rebuiltBy, 8)}} | painted ${first.painted} '
      '{${_top(first.paintedBy, 4)}} | pictures re-recorded '
      '${first.picturesRerecorded} | later frames ${later.length}: '
      '${later.map(_ms).join(' ')}',
    );
  }

  Future<void> armTool(
    ValueNotifier<BrushToolState> brushTool,
    CanvasTool tool,
  ) async {
    brushTool.value = brushTool.value.copyWith(tool: tool);
    await tester.pumpAndSettle();
    expect(brushTool.value.tool, tool, reason: 'the tool switch was refused');
  }

  /// The hover arm: warm the cursor up, control, then [moves] measured
  /// moves 4px apart, each followed by one pump — then four untimed moves
  /// with layout tracing on, and the cost of one hit test.
  Future<void> measureHover(
    String label,
    TestGesture mouse, {
    required int moves,
    required Offset? Function()? shownAt,
    Duration? realTimeBefore,
  }) async {
    final start = strokeStart(0) + const Offset(2, 2);
    Future<void> realTime() async {
      if (realTimeBefore != null) {
        await tester.runAsync(() => Future<void>.delayed(realTimeBefore));
      }
    }

    // ARM — the cursor shows only once the census has seen the pointer.
    await realTime();
    final arming = await measureOne(() => mouse.moveTo(start));
    // ignore: avoid_print
    print(
      '[F130] $label arming: painted ${arming.painted} rebuilt '
      '${_sum(arming.rebuiltBy)} pictures re-recorded '
      '${arming.picturesRerecorded} scheduled ${arming.frameScheduled}',
    );
    if (shownAt != null) {
      expect(shownAt(), isNotNull, reason: '$label: the cursor must be up');
    }
    // Warm-up moves are not the measurement (JIT).
    for (var i = 1; i <= 4; i += 1) {
      await realTime();
      await mouse.moveTo(start + Offset(4.0 * i, 0));
      await tester.pump();
    }
    await control(label);
    final cursorBefore = shownAt?.call();
    final readings = <_FrameReading>[];
    for (var i = 1; i <= moves; i += 1) {
      final target = start + Offset(16 + 4.0 * i, 4.0 * (i % 3));
      await realTime();
      readings.add(await measureOne(() => mouse.moveTo(target)));
    }
    if (shownAt != null) {
      // ALIVE — the cursor followed; "it stopped moving" cannot pass.
      final cursorAfter = shownAt();
      expect(cursorAfter, isNotNull, reason: '$label: the cursor vanished');
      expect(
        cursorAfter!.dx - cursorBefore!.dx,
        closeTo(4.0 * moves, 0.5),
        reason: '$label: the cursor tracked every move',
      );
    }
    // The relayout pass — untimed, traced.
    final traced = <_FrameReading>[];
    for (var i = 1; i <= 4; i += 1) {
      final target = start + Offset(16 + 4.0 * moves + 4.0 * i, 0);
      await realTime();
      traced.add(
        await measureOne(() => mouse.moveTo(target), traceLayout: true),
      );
    }
    _report(label, readings, traced);
    // The event's own cost, apart from the frame: a hit test of the whole
    // tree per hover, per the framework — measured here so the number is
    // this app's tree and not a guess.
    final hitTest = Stopwatch()..start();
    for (var i = 0; i < 200; i += 1) {
      tester.hitTestOnBinding(start);
    }
    hitTest.stop();
    // ignore: avoid_print
    print(
      '[F130] $label: one hit test of the tree = '
      '${(hitTest.elapsedMicroseconds / 200).toStringAsFixed(0)}us',
    );
  }

  /// A pointer stream at display rate: [moves] moves, one frame each. For
  /// every frame, whether the cursor stands where that frame's move put it
  /// — the frames it did not are the 「30」 the user sees — and what the
  /// frame cost against the 16.67ms budget.
  Future<void> measureStream(
    String label,
    TestGesture mouse, {
    required int moves,
    required Offset? Function() shownAt,
  }) async {
    // A circle on bare canvas: [strokeStart] vouches for the point and for
    // the point one stroke's travel away, so a ring inside that box never
    // leaves the canvas — a straight run of 60 moves did, and read the
    // scrollbar's hover as a lost cursor.
    final start = strokeStart(1) + const Offset(2, 2);
    final centre = start + const Offset(28, 16);
    const radius = 14.0;
    Offset pointAt(int i) =>
        centre +
        Offset(
          radius * math.cos(i * 2 * math.pi / moves),
          radius * math.sin(i * 2 * math.pi / moves),
        );
    await mouse.moveTo(pointAt(0));
    await tester.pump();
    final origin = shownAt();
    expect(origin, isNotNull, reason: '$label: the cursor must be up');
    var kept = 0;
    final readings = <_FrameReading>[];
    for (var i = 1; i <= moves; i += 1) {
      final target = pointAt(i);
      final reading = await measureOne(() => mouse.moveTo(target));
      readings.add(reading);
      final at = shownAt();
      final expected = origin! + (target - pointAt(0));
      final onTarget = at != null &&
          (at.dx - expected.dx).abs() < 0.5 &&
          (at.dy - expected.dy).abs() < 0.5;
      if (onTarget) {
        kept += 1;
      }
      if (!onTarget || i <= 3) {
        // ignore: avoid_print
        print(
          '[F130] $label frame $i: ${onTarget ? 'on target' : 'MISSED'} '
          'expected $expected shown $at | scheduled ${reading.frameScheduled} '
          'pump ${_ms(reading.pumpMicros)}ms rebuilt ${_sum(reading.rebuiltBy)} '
          '{${_top(reading.rebuiltBy, 3)}} painted ${reading.painted} '
          '{${_top(reading.paintedBy, 3)}}',
        );
      }
    }
    final n = readings.length;
    final budget = const Duration(microseconds: 16667).inMicroseconds;
    final over = readings.where((r) => r.pumpMicros > budget).length;
    int maxOf(int Function(_FrameReading) f) =>
        readings.fold(0, (a, r) => f(r) > a ? f(r) : a);
    // ignore: avoid_print
    print(
      '[F130] $label: frames that showed the cursor where the move put it '
      '$kept/$n | frames over the 16.67ms budget $over/$n | pump mean '
      '${_ms(readings.fold(0, (a, r) => a + r.pumpMicros) ~/ n)}ms max '
      '${_ms(maxOf((r) => r.pumpMicros))}ms | rebuilt '
      '${readings.fold(0, (a, r) => a + _sum(r.rebuiltBy))} painted '
      '${readings.fold(0, (a, r) => a + r.painted)} pictures re-recorded '
      '${readings.fold(0, (a, r) => a + r.picturesRerecorded)} over the stream',
    );
    expect(kept, n, reason: '$label: every frame must carry the cursor');
  }

  /// The pen is DOWN: [moves] stylus moves, one pump each — the cursor
  /// frame while the stroke's dabs queue for their own flush.
  Future<void> measureStroke(String label, {required int moves}) async {
    final start = strokeStart(_strokeIndex);
    _strokeIndex += 1;
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    for (var i = 0; i < 4; i += 1) {
      await gesture.moveBy(const Offset(3, 2));
      await tester.pump();
    }
    final readings = <_FrameReading>[];
    for (var i = 0; i < moves; i += 1) {
      readings.add(await measureOne(() => gesture.moveBy(const Offset(4, 2))));
    }
    final traced = <_FrameReading>[];
    for (var i = 0; i < 4; i += 1) {
      traced.add(
        await measureOne(
          () => gesture.moveBy(const Offset(4, 2)),
          traceLayout: true,
        ),
      );
    }
    _report(label, readings, traced);
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// How many frames after a move the INK appears — with real time between
  /// pumps (`runAsync`) so the tile upload can land. Reads the overlay's tile
  /// image count: a move whose tiles decoded shows up as a growth.
  Future<void> measureInkFrames(String label, {required int moves}) async {
    final overlay = tester
        .widget<BrushCanvasPanel>(mainCanvasPanelShell())
        .activeStrokeOverlayModel;
    if (overlay == null) {
      // ignore: avoid_print
      print('[F130] $label: no host overlay model — merged mode is off');
      return;
    }
    final start = strokeStart(_strokeIndex);
    _strokeIndex += 1;
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
    final framesToInk = <int>[];
    for (var i = 0; i < moves; i += 1) {
      // Far enough to land on a fresh tile with each move.
      await gesture.moveBy(const Offset(96, 64));
      final imagesBefore = overlay.tileImages.length;
      var frames = 0;
      var landed = false;
      for (var frame = 1; frame <= 4 && !landed; frame += 1) {
        // Real time first, so an upload started in the EVENT would land
        // before the frame; today's flush starts inside the frame.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pump();
        frames = frame;
        landed = overlay.tileImages.length > imagesBefore;
      }
      framesToInk.add(landed ? frames : -1);
    }
    // ignore: avoid_print
    print(
      '[F130] $label: frames from move to a NEW overlay tile image, per '
      'move: $framesToInk (-1 = not within 4 frames; 40ms of real time '
      'before every frame)',
    );
    await gesture.up();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  /// One stylus stroke, asserted to have committed exactly one undo step
  /// (the H30 contamination guard, kept).
  Future<void> drawOneStroke(EditorSessionManager session) async {
    final countBefore = session.historyManager.undoCount;
    final start = strokeStart(_strokeIndex);
    _strokeIndex += 1;
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.stylus,
    );
    for (var move = 0; move < 8; move += 1) {
      await gesture.moveBy(const Offset(7, 4));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      session.historyManager.undoCount - countBefore,
      1,
      reason: 'the stroke must have committed one pixel step',
    );
  }

  /// Hover moves in the settle window right after a stroke lands — the
  /// clock advanced 16ms per pump so the 50ms settle recheck fires.
  Future<void> measureAfterStroke(
    String label,
    TestGesture mouse, {
    required int moves,
  }) async {
    final start = strokeStart(_strokeIndex);
    _strokeIndex += 1;
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.stylus,
    );
    for (var move = 0; move < 8; move += 1) {
      await gesture.moveBy(const Offset(7, 4));
      await tester.pump();
    }
    await gesture.up();
    // No settle: the very next frames ARE the measurement.
    final hoverStart = start + const Offset(-20, 30);
    await mouse.moveTo(hoverStart);
    await tester.pump();
    final readings = <_FrameReading>[];
    for (var i = 1; i <= moves; i += 1) {
      readings.add(
        await measureOne(() => mouse.moveTo(hoverStart + Offset(4.0 * i, 0))),
      );
      // Let the settle timers tick between moves.
      await tester.pump(const Duration(milliseconds: 16));
    }
    _report(label, readings, const []);
    await tester.pumpAndSettle();
  }

  static int _sum(Map<String, int> m) => m.values.fold(0, (a, b) => a + b);

  static String _ms(int micros) => (micros / 1000.0).toStringAsFixed(2);

  static String _top(Map<String, int> m, int n) {
    final entries = m.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(n).map((e) => '${e.key}:${e.value}').join(' ');
  }

  void _report(
    String label,
    List<_FrameReading> readings,
    List<_FrameReading> traced,
  ) {
    final n = readings.length;
    int meanOf(int Function(_FrameReading) f) =>
        readings.fold(0, (a, r) => a + f(r)) ~/ n;
    int maxOf(int Function(_FrameReading) f) =>
        readings.fold(0, (a, r) => f(r) > a ? f(r) : a);
    final painted = <String, int>{};
    final rebuilt = <String, int>{};
    final relayout = <String, int>{};
    final causes = <String, int>{};
    final readdedBy = <String, int>{};
    final freshBy = <String, int>{};
    for (final r in readings) {
      r.paintedBy.forEach((k, v) => painted[k] = (painted[k] ?? 0) + v);
      r.rebuiltBy.forEach((k, v) => rebuilt[k] = (rebuilt[k] ?? 0) + v);
      r.layersReaddedBy.forEach(
        (k, v) => readdedBy[k] = (readdedBy[k] ?? 0) + v,
      );
      r.layersFreshBy.forEach((k, v) => freshBy[k] = (freshBy[k] ?? 0) + v);
    }
    for (final r in traced) {
      r.relayoutBy.forEach((k, v) => relayout[k] = (relayout[k] ?? 0) + v);
      r.buildCausesBy.forEach((k, v) => causes[k] = (causes[k] ?? 0) + v);
    }
    if (causes.isNotEmpty) {
      // ignore: avoid_print
      print(
        '[F130] $label: who dirtied widgets over ${traced.length} traced '
        'moves {${_top(causes, 8)}}',
      );
    }
    final scheduled = readings.where((r) => r.frameScheduled).length;
    final relayoutPerFrame = traced.isEmpty
        ? '(not traced)'
        : '${(_sum(relayout) / traced.length).toStringAsFixed(1)}/frame '
            '{${_top(relayout, 4)}}';
    // A mean hides a one-off: name the heaviest frame and the median, so a
    // single decode landing mid-arm cannot pass as a per-move cost.
    final pumps = readings.map((r) => r.pumpMicros).toList()..sort();
    final median = pumps[pumps.length ~/ 2];
    var heaviest = readings.first;
    for (final r in readings) {
      if (_sum(r.rebuiltBy) + r.painted > _sum(heaviest.rebuiltBy) + heaviest.painted) {
        heaviest = r;
      }
    }
    // ignore: avoid_print
    print(
      '[F130] $label: median pump ${_ms(median)}ms | heaviest frame rebuilt '
      '${_sum(heaviest.rebuiltBy)} painted ${heaviest.painted} pump '
      '${_ms(heaviest.pumpMicros)}ms {${_top(heaviest.rebuiltBy, 3)}} | frames '
      'with any rebuild ${readings.where((r) => r.rebuiltBy.isNotEmpty).length}/$n',
    );
    // ignore: avoid_print
    print(
      '[F130] $label: moves $n | dispatch ${_ms(meanOf((r) => r.dispatchMicros))}ms/ev '
      '| pump ${_ms(meanOf((r) => r.pumpMicros))}ms '
      '(transient ${_ms(meanOf((r) => r.transientMicros))} + draw '
      '${_ms(meanOf((r) => r.drawMicros))}) max ${_ms(maxOf((r) => r.pumpMicros))} '
      '| frame scheduled $scheduled/$n '
      '| rebuilt ${(_sum(rebuilt) / n).toStringAsFixed(1)}/frame '
      '{${_top(rebuilt, 6)}} '
      '| painted ${meanOf((r) => r.painted)}/frame '
      '{${_top(painted, 6)}} '
      '| relayout $relayoutPerFrame '
      '| layers re-added ${meanOf((r) => r.layersReadded)}/frame '
      '{${_top(readdedBy, 8)}} '
      '| layers new ${meanOf((r) => r.layersFresh)}/frame '
      '{${_top(freshBy, 6)}} '
      '| pictures re-recorded ${meanOf((r) => r.picturesRerecorded)}/frame',
    );
  }
}

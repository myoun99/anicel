import 'dart:ui' show ImageByteFormat, PictureRecorder;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/canvas_selection_layer.dart';
import 'package:anicel/src/ui/canvas/selection_ants_painter.dart';

import '../helpers/brush_canvas_fixture.dart';

/// P9 widget routing on the R19 pixel model: the selection layer mounts
/// only for selection tools, regions select PIXELS, move sessions float
/// until ONE confirmed history entry, and all oracles are the raster
/// itself (commands retired — the picture is the record).
void main() {
  const layerKey = ValueKey<String>('canvas-selection-layer');

  BrushDab dab(double x, double y) => BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: 0xFFFF0000,
    size: 4,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: 0,
  );

  Future<
    ({
      BrushFrameEditingCoordinator coordinator,
      HistoryManager history,
      CanvasSelectionCommands commands,
      Future<void> Function(CanvasTool tool) setTool,
      Future<void> Function(CanvasViewport viewport) setViewport,
      ValueNotifier<TransformToolOptions> transformOptions,
    })
  >
  pumpSelectionPanel(
    WidgetTester tester, {
    CanvasTool tool = CanvasTool.select,
    CanvasShapeKind shapeKind = CanvasShapeKind.rect,
    BrushBlendMode blendMode = BrushBlendMode.color,
    TransformMode transformMode = TransformMode.normal,
    CanvasViewport? viewport,
    // Extra committed ink, mounted with the fixture. `null` replaces the
    // in-canvas stroke entirely (a cel whose only ink is off-canvas).
    List<BrushDab>? sourceDabs,
    // A canvas SMALLER than the 800×600 test viewport, so pasteboard
    // coordinates are reachable by a pointer at all.
    CanvasSize canvasSize = BrushCanvasFixture.canvasSize,
  }) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
      canvasSize: canvasSize,
    );
    final history = HistoryManager();
    final commands = CanvasSelectionCommands();
    final transformOptions = ValueNotifier(
      TransformToolOptions(mode: transformMode),
    );
    addTearDown(transformOptions.dispose);
    // One committed stroke around canvas (30..60, 30..60). An EMPTY list
    // means a blank cel — the coordinator refuses to commit nothing, and
    // "nothing was committed" is exactly the state under test.
    final dabs = sourceDabs ?? [dab(30, 30), dab(45, 45), dab(60, 60)];
    if (dabs.isNotEmpty) {
      coordinator.commitSourceStroke(sourceDabs: dabs);
    }

    var liveViewport = viewport;
    var liveTool = tool;
    Future<void> pumpWith(CanvasTool tool) async {
      liveTool = tool;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: const ValueKey<String>('panel-capture'),
              child: BrushCanvasPanel(
                coordinator: coordinator,
                // The panel carries its OWN canvas size, independent of the
                // coordinator's session store — passing only the fixture's
                // left the panel at the 2340×1654 default, which silently
                // put every reachable pointer position back on canvas.
                canvasSize: canvasSize,
                availableFrameKeys: frameKeys,
                cacheInvalidationSink: BrushEditCacheInvalidationSink(),
                historyManager: history,
                brushToolState: BrushToolState.defaults.copyWith(
                  tool: tool,
                  selectShape: shapeKind,
                  fillShape: shapeKind,
                  fillBlendMode: blendMode,
                ),
                selectionCommands: commands,
                viewport: liveViewport,
                shapeFillDabFor: (shape, color) => buildShapeFillDab(
                  shape: shape,
                  color: color,
                  options: const FloodFillOptions(
                    expandPx: 0,
                    antiAlias: false,
                  ),
                ),
                transformOptions: transformOptions,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpWith(tool);
    return (
      coordinator: coordinator,
      history: history,
      commands: commands,
      setTool: pumpWith,
      setViewport: (next) async {
        liveViewport = next;
        await pumpWith(liveTool);
      },
      transformOptions: transformOptions,
    );
  }

  /// A picture that covers more than the painter's four-tile per-pixel
  /// budget (tiles are 256 px), which is the threshold below which every
  /// float defect is invisible.
  ///
  /// ⚠️ A grid, not a diagonal. The first version of this ran from
  /// (30,30) to (710,506) and touched EXACTLY four tiles, so the budget
  /// covered all of it and the tests it was written for passed without
  /// their fixes. Nine tiles here, comfortably past it.
  final widePicture = <BrushDab>[
    for (var y = 30; y <= 550; y += 40)
      for (var x = 30; x <= 750; x += 40) dab(x.toDouble(), y.toDouble()),
  ];

  /// A picture whose pixels are SEMI-TRANSPARENT and soft-edged, so a
  /// landing dropped on top of it makes the stand-in composition actually
  /// blend.
  ///
  /// ⚠️ The hard opaque squares above cannot measure the composition at
  /// all: `srcOver` of an opaque source is exact by construction, so a
  /// landing made of them agrees with the commit whatever the rounding
  /// does. Every other fixture in this file lifts the WHOLE picture too,
  /// which leaves the pre-commit tiles EMPTY — and composing over nothing
  /// is exact for the same reason.
  BrushDab softDab(double x, double y) => BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: 0xFFFF2020,
    size: 26,
    opacity: 0.45,
    flow: 0.8,
    hardness: 0.25,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: 0,
  );
  final blendedPicture = <BrushDab>[
    for (var y = 40; y <= 520; y += 26)
      for (var x = 40; x <= 720; x += 26) softDab(x.toDouble(), y.toDouble()),
  ];

  /// The cel's CURRENT pixels — 0/null means transparent.
  int inkAt(BrushFrameEditingCoordinator coordinator, int x, int y) {
    return surfacePixelRgba(
          coordinator.currentSurfaceOf(coordinator.activeFrameKey),
          x,
          y,
        ) ??
        0;
  }

  BitmapSurface currentSurface(BrushFrameEditingCoordinator coordinator) =>
      coordinator.currentSurfaceOf(coordinator.activeFrameKey);

  /// How much of the RED fixture ink the COMPOSITED panel is showing —
  /// base, float, held preview and all, exactly what the user's eye gets.
  ///
  /// ⚠️ `toImageSync`, captured before any `runAsync`: the frame under
  /// test is one where nothing has decoded yet, and giving the pipeline an
  /// idle slice first would let the committed tiles land and report the
  /// defect as fixed. The snapshot is read afterwards, which is safe
  /// because it is a snapshot.
  /// WHERE the ink is, not how much of it there is.
  ///
  /// ⚠️ Counting is not enough, and believing a count cost this file a
  /// wrong conclusion once. The base painter's stale fallback draws the
  /// pre-lift picture at the PRE-lift place; on a move whose landing
  /// overlaps its origin those wrong pixels are ink too, so a count reads
  /// them as "covered" and removing the lie reads as a regression.
  Future<List<bool>> screenInkMask(WidgetTester tester) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey<String>('panel-capture')),
    );
    final image = boundary.toImageSync();
    late List<bool> mask;
    await tester.runAsync(() async {
      final data = await image.toByteData(format: ImageByteFormat.rawRgba);
      final bytes = data!.buffer.asUint8List();
      mask = List<bool>.generate(
        bytes.length ~/ 4,
        (i) =>
            bytes[i * 4] > 128 &&
            bytes[i * 4 + 1] < 100 &&
            bytes[i * 4 + 2] < 100,
        growable: false,
      );
    });
    image.dispose();
    return mask;
  }

  /// The panel's raw pixels, same capture as [screenInkMask] but without
  /// the red threshold — for questions about the VALUE of a pixel rather
  /// than whether it counts as ink.
  Future<Uint8List> screenBytes(WidgetTester tester) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey<String>('panel-capture')),
    );
    final image = boundary.toImageSync();
    late Uint8List bytes;
    await tester.runAsync(() async {
      final data = await image.toByteData(format: ImageByteFormat.rawRgba);
      bytes = Uint8List.fromList(data!.buffer.asUint8List());
    });
    image.dispose();
    return bytes;
  }

  /// What the frame gets WRONG against the settled result: ink where the
  /// result has none (`ghost` — a displaced or leftover copy) and none
  /// where the result has ink (`hole`).
  ///
  /// ⚠️ RUN THE FILE WHOLE. `ghost` is drawn by the tile cache's stale
  /// fallback, so its size is how much of the cel had already decoded —
  /// and the cache is a shared singleton that earlier tests in this file
  /// warm. Measured on the same code: 4020 with the file, 0 with
  /// `--plain-name`. A ghost assertion run in isolation is vacuous.
  ({int ghost, int hole}) inkDelta(List<bool> frame, List<bool> settled) {
    var ghost = 0;
    var hole = 0;
    for (var i = 0; i < settled.length; i += 1) {
      if (frame[i] && !settled[i]) ghost += 1;
      if (!frame[i] && settled[i]) hole += 1;
    }
    return (ghost: ghost, hole: hole);
  }

  /// Waits for a CONDITION, never for a clock.
  ///
  /// The float preview lands through a real `decodeImageFromPixels`
  /// callback, so a test has to let real async work run — and how long
  /// that takes depends on what else the machine is doing. A fixed delay
  /// passes when the file runs alone and fails in a full suite, which is
  /// the worst way for a test to be wrong: it comes back as a failure in
  /// whatever landed that day.
  ///
  /// Fails loudly on timeout rather than falling through to an assertion
  /// that would blame the code.
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() ready, {
    required String reason,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final watch = Stopwatch()..start();
    while (!ready()) {
      if (watch.elapsed > timeout) {
        fail(
          'timed out after ${timeout.inSeconds}s waiting for $reason — the '
          'pipeline never got there, which is a real failure and not a '
          'slow machine',
        );
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  /// True once the transform preview widget is mounted — the observable
  /// end of the resample + decode round trip.
  bool previewIsUp() => find
      .byKey(const ValueKey<String>('transform-resample-preview'))
      .evaluate()
      .isNotEmpty;

  /// Lets the real decode pipeline run to completion, so the committed
  /// surface can paint and any hold releases.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 16)),
      );
      await tester.pump();
    }
  }

  Future<void> dragOnLayer(WidgetTester tester, Offset from, Offset to) async {
    final origin = tester.getTopLeft(find.byKey(layerKey));
    final gesture = await tester.startGesture(origin + from);
    await tester.pump();
    await gesture.moveTo(origin + to);
    await tester.pump();
    await gesture.up();
    await tester.pump();
  }

  /// One polygon vertex tap: down where it aims, up to commit it.
  Future<void> tapOnLayer(WidgetTester tester, Offset at) async {
    final origin = tester.getTopLeft(find.byKey(layerKey));
    final gesture = await tester.startGesture(origin + at);
    await tester.pump();
    await gesture.up();
    await tester.pump();
  }

  /// The chrome the ants painter is ACTUALLY drawing — read off the
  /// mounted painter, so a fix that only reaches the model cannot pass.
  SelectionTransformChrome? chromeOnScreen(WidgetTester tester) {
    final paints = tester.widgetList<CustomPaint>(
      find.descendant(
        of: find.byKey(layerKey),
        matching: find.byType(CustomPaint),
      ),
    );
    for (final paint in paints) {
      final painter = paint.painter;
      if (painter is SelectionAntsPainter) {
        return painter.transformChrome;
      }
    }
    return null;
  }

  /// Horizontal extent in VIEWPORT space, so the assertions never have to
  /// know the zoom the panel settled on.
  ({double left, double right, double width}) extentOf(List<Offset> points) {
    var left = points.first.dx;
    var right = points.first.dx;
    for (final point in points) {
      if (point.dx < left) left = point.dx;
      if (point.dx > right) right = point.dx;
    }
    return (left: left, right: right, width: right - left);
  }

  testWidgets('㉝ 삭제 pulls the move box in with it — the chrome frames '
      'what is selected NOW, not what was selected first', (tester) async {
    final env = await pumpSelectionPanel(tester);
    await dragOnLayer(tester, const Offset(20, 20), const Offset(120, 120));

    await env.setTool(CanvasTool.move);
    final before = chromeOnScreen(tester);
    expect(before, isNotNull, reason: 'the move tool shows the box at once');
    final wide = extentOf(before!.box);
    expect(wide.width, greaterThan(0));

    // 삭제: a second drag cuts the right half back out.
    await env.setTool(CanvasTool.select);
    env.commands.combineMode = SelectionCombineMode.subtract;
    await tester.pump();
    await dragOnLayer(tester, const Offset(70, 10), const Offset(140, 140));

    final region = env.commands.region!;
    expect(
      region.selectedBounds.right,
      lessThan(region.coverageBounds.right),
      reason: 'precondition: the 삭제 really took an edge band off',
    );

    await env.setTool(CanvasTool.move);
    final after = chromeOnScreen(tester)!;
    final narrow = extentOf(after.box);

    expect(
      narrow.left,
      moreOrLessEquals(wide.left, epsilon: 1),
      reason: 'the untouched side stays put',
    );
    expect(
      narrow.right,
      lessThan(wide.right - wide.width / 4),
      reason: 'the box gave up the subtracted half',
    );
    // The handles are the same box, so they have to come along; reading
    // them separately is what catches a chrome built from two sources.
    expect(
      extentOf(after.handles).right,
      moreOrLessEquals(narrow.right, epsilon: 1),
    );
  });

  testWidgets('P3a: the bytes the PREVIEW showed are the bytes Enter '
      'writes — the contract, tested at last', (tester) async {
    // Before P3a this was untestable because it was false. The affine and
    // quad previews were a Skia widget Transform over tiles drawn at
    // FilterQuality.none, and the mesh preview was drawVertices through an
    // ImageShader at FilterQuality.medium — three screen approximations,
    // none of which agreed with the Catmull-Rom the commit ran. The whole
    // point of a mode that preserves colours exactly is to SEE the result
    // before committing to it, so the preview and the commit now share one
    // buffer rather than two computations that ought to match.
    final env = await pumpSelectionPanel(tester);
    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    await env.setTool(CanvasTool.move);

    debugLastResampledFloat = null;
    env.commands.beginTransform();
    await tester.pump();
    // A rotation, so the resampler actually runs (a pure translation
    // short-circuits and never reaches it).
    env.commands.setTransformValues(
      tx: 0,
      ty: 0,
      rotationDegrees: 24,
      scale: 1,
    );
    await tester.pump();

    final previewed = debugLastResampledFloat;
    expect(
      previewed,
      isNotNull,
      reason: 'an open rotation must have produced a resampled float',
    );
    final stamp = previewed!.stamp!;
    final previewBytes = Uint8List.fromList(stamp.rgba);
    final left = (previewed.center.x - stamp.width / 2).round();
    final top = (previewed.center.y - stamp.height / 2).round();

    env.commands.commitTransform();
    await tester.pump();
    expect(env.commands.movePending, isFalse);

    // Every fully opaque pixel of the preview must be exactly that colour
    // in the landed picture. Opaque only: a partial-alpha pixel composites
    // against whatever was underneath, which is a different question.
    var checked = 0;
    for (var y = 0; y < stamp.height; y += 1) {
      for (var x = 0; x < stamp.width; x += 1) {
        final offset = (y * stamp.width + x) * 4;
        if (previewBytes[offset + 3] != 255) {
          continue;
        }
        final landed = surfacePixelRgba(
          currentSurface(env.coordinator),
          left + x,
          top + y,
        );
        expect(
          landed,
          isNotNull,
          reason: 'the preview showed a pixel at ($x,$y) and nothing landed',
        );
        expect(
          [
            landed! & 0xff,
            (landed >> 8) & 0xff,
            (landed >> 16) & 0xff,
            (landed >> 24) & 0xff,
          ],
          [
            previewBytes[offset],
            previewBytes[offset + 1],
            previewBytes[offset + 2],
            previewBytes[offset + 3],
          ],
          reason: 'preview and commit disagree at ($x,$y)',
        );
        checked += 1;
      }
    }
    expect(
      checked,
      greaterThan(0),
      reason: 'a preview with no opaque pixel proves nothing',
    );
  });

  testWidgets('P3a: an arrow-key nudge with the box open moves the '
      'PICTURE, not just the outline', (tester) async {
    // Caught by adversarial review, not by the suite. Once the preview is
    // a resampled bitmap rather than a matrix evaluated in build, any
    // mutation of the open warp that forgets to schedule a resample moves
    // the ants and the box chrome while the artwork stays put — and Enter
    // then lands the ink where the outline is, not where the picture was.
    // Master could not have this bug: it recomputed the screen matrix on
    // every build.
    final env = await pumpSelectionPanel(tester);
    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    await env.setTool(CanvasTool.move);

    env.commands.beginTransform();
    await tester.pump();
    env.commands.setTransformValues(
      tx: 0,
      ty: 0,
      rotationDegrees: 24,
      scale: 1,
    );
    await tester.pump();
    final before = debugLastResampledFloat!.center;

    await tester.runAsync(() async {
      for (var i = 0; i < 10; i += 1) {
        env.commands.nudge(1, 0);
      }
      // The decode from the rotation above is still in flight, so the
      // nudges only mark the preview dirty; the callback runs the last
      // state. Letting that settle is the realistic path, and asserting
      // after it is what makes this test about the SCHEDULING rather than
      // about how many resamples one drag happens to trigger.
      //
      // Waits for the EVENT, not for the clock. A fixed delay here failed
      // in the full suite and passed on its own, which is the signature of
      // a test that measures the machine: under load the resample had not
      // landed in 100 ms. Polling for "the float moved at all" keeps the
      // assertion honest — it can still be the wrong value, and a
      // resample that never happens still times out and fails.
      for (var waited = 0; waited < 60; waited += 1) {
        if (debugLastResampledFloat!.center != before) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();

    expect(
      debugLastResampledFloat!.center.x,
      before.x + 10,
      reason: 'the resampled float must follow the nudge',
    );
    expect(debugLastResampledFloat!.center.y, before.y);
  });

  testWidgets('the DEFAULT mode smooths — the guard that keeps the '
      'colour-preservation assertions from being vacuous', (tester) async {
    // Named for what it actually does. It does NOT drive the AA-off
    // switch: this harness builds BrushCanvasPanel without
    // transformResampleMode, so the layer reads the blend default and no
    // test here can change it.
    //
    // What it is for: the colour-preservation tests elsewhere assert that
    // Pick invents no new colours. That assertion is worth nothing unless
    // the default DOES invent them on the same transform — otherwise a
    // resampler that had quietly stopped interpolating would satisfy both.
    // This is the control.
    final env = await pumpSelectionPanel(tester);
    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    await env.setTool(CanvasTool.move);

    final before = currentSurface(env.coordinator);
    final sourceColours = <int>{};
    for (var y = 0; y < 90; y += 1) {
      for (var x = 0; x < 90; x += 1) {
        final pixel = surfacePixelRgba(before, x, y);
        if (pixel != null && (pixel >> 24) != 0) sourceColours.add(pixel);
      }
    }
    expect(sourceColours, isNotEmpty);

    env.commands.beginTransform();
    await tester.pump();
    env.commands.setTransformValues(
      tx: 0,
      ty: 0,
      rotationDegrees: 24,
      scale: 1,
    );
    await tester.pump();
    env.commands.commitTransform();
    await tester.pump();

    // Blend is the default, and a rotation through it MUST invent
    // in-between colours — otherwise the assertion below proves nothing.
    final landed = currentSurface(env.coordinator);
    var invented = 0;
    for (var y = 0; y < 90; y += 1) {
      for (var x = 0; x < 90; x += 1) {
        final pixel = surfacePixelRgba(landed, x, y);
        if (pixel != null &&
            (pixel >> 24) != 0 &&
            !sourceColours.contains(pixel)) {
          invented += 1;
        }
      }
    }
    expect(
      invented,
      greaterThan(0),
      reason:
          'AA on must smooth; if it does not, the AA-off assertion in '
          'the sibling test is vacuous',
    );
  });

  testWidgets('the layer mounts for selection tools only', (tester) async {
    await pumpSelectionPanel(tester, tool: CanvasTool.brush);
    expect(find.byKey(layerKey), findsNothing);

    await pumpSelectionPanel(tester);
    expect(find.byKey(layerKey), findsOneWidget);
    expect(find.byType(CanvasSelectionLayer), findsOneWidget);
  });

  testWidgets('marquee selects; the MOVE tool floats a session and the '
      'confirm lands ONE undoable pixel move (R11-⑧/R16-①)', (tester) async {
    final env = await pumpSelectionPanel(tester);

    // Marquee around the whole stroke (viewport is identity: local ==
    // canvas coordinates).
    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    expect(env.commands.hasSelection, isTrue);

    // A MARQUEE-tool drag inside the region draws a NEW region — content
    // never moves on the selection tools.
    await dragOnLayer(tester, const Offset(25, 25), const Offset(68, 68));
    expect(inkAt(env.coordinator, 30, 30), isNonZero);
    expect(env.commands.hasSelection, isTrue);

    // The MOVE tool opens a TVP-style SESSION: the lift's erase lands raw
    // (origin vanishes), drags move only the floating stamp — nothing is
    // undoable until the CONFIRM.
    await env.setTool(CanvasTool.move);
    final entriesBeforeMove = env.history.undoCount;
    await dragOnLayer(tester, const Offset(45, 45), const Offset(55, 50));

    expect(
      inkAt(env.coordinator, 30, 30),
      0,
      reason: 'pending: the base holds only the erase — origin is blank',
    );
    expect(env.commands.movePending, isTrue);
    expect(
      env.history.undoCount,
      entriesBeforeMove,
      reason: 'nothing is undoable before the confirm',
    );

    // CONFIRM: one history entry; the pixels land moved by (+10,+5).
    env.commands.confirmPendingMove();
    await tester.pump();
    expect(env.commands.movePending, isFalse);
    expect(env.history.undoCount, entriesBeforeMove + 1);
    expect(inkAt(env.coordinator, 40, 35), isNonZero);
    expect(inkAt(env.coordinator, 28, 28), 0);

    env.history.undo(); // the WHOLE session (lift + move) as one step
    await tester.pump();
    expect(
      inkAt(env.coordinator, 30, 30),
      isNonZero,
      reason: 'one undo restores the pre-lift picture',
    );

    env.history.redo();
    await tester.pump();
    expect(inkAt(env.coordinator, 40, 35), isNonZero);

    // Outside the region the move tool does nothing.
    await dragOnLayer(tester, const Offset(150, 150), const Offset(170, 170));
    expect(inkAt(env.coordinator, 40, 35), isNonZero);
  });

  testWidgets('R26 #13: the MOVE tool with NO selection drags the WHOLE '
      'picture — implicit whole-canvas session, ONE confirmed entry, and '
      'the end returns to no selection', (tester) async {
    final env = await pumpSelectionPanel(tester, tool: CanvasTool.move);
    expect(env.commands.hasSelection, isFalse);

    final entriesBefore = env.history.undoCount;
    await dragOnLayer(tester, const Offset(45, 45), const Offset(55, 50));
    expect(env.commands.movePending, isTrue);
    expect(
      inkAt(env.coordinator, 30, 30),
      0,
      reason: 'the whole picture lifted — the origin is blank while pending',
    );

    env.commands.confirmPendingMove();
    await tester.pump();
    expect(env.history.undoCount, entriesBefore + 1);
    expect(inkAt(env.coordinator, 40, 35), isNonZero, reason: '+10,+5 landed');
    expect(
      env.commands.hasSelection,
      isFalse,
      reason: 'the implicit shape ends with the session — no stray ants',
    );

    env.history.undo();
    await tester.pump();
    expect(
      inkAt(env.coordinator, 30, 30),
      isNonZero,
      reason: 'one undo restores the pre-lift picture',
    );
  });

  testWidgets('the whole picture means the PASTEBOARD too — no-selection '
      'move carries off-canvas ink with the rest', (tester) async {
    // User report (08-04): "when the drawing runs out into the pasteboard
    // and I transform with nothing selected, only the part inside the
    // canvas becomes the target". The implicit whole-picture shape was
    // reading the cel's true ink bounds and then clamping them to the
    // canvas rect, so off-canvas ink stood still while the picture moved
    // out from under it.
    //
    // The oracle is the RASTER at the off-canvas coordinate, not the
    // region bounds: a fix that lifts the right rect and then clips at
    // the commit would pass a bounds assertion and still be the bug.
    final env = await pumpSelectionPanel(
      tester,
      tool: CanvasTool.move,
      sourceDabs: [dab(-20, -20), dab(30, 30), dab(45, 45), dab(60, 60)],
    );
    expect(
      inkAt(env.coordinator, -20, -20),
      isNonZero,
      reason: 'the fixture really does hold pasteboard ink',
    );

    await dragOnLayer(tester, const Offset(45, 45), const Offset(55, 50));
    env.commands.confirmPendingMove();
    await tester.pump();

    expect(inkAt(env.coordinator, 40, 35), isNonZero, reason: '+10,+5 landed');
    expect(
      inkAt(env.coordinator, -10, -15),
      isNonZero,
      reason: 'the pasteboard dab moved by the same +10,+5',
    );
    expect(
      inkAt(env.coordinator, -20, -20),
      0,
      reason: 'and it LEFT its old place — not copied, moved',
    );
  });

  testWidgets('a cel whose only ink is on the pasteboard still has a whole '
      'picture to move', (tester) async {
    // The degenerate branch: with the canvas clamp, pasteboard-only ink
    // collapsed to an empty rect and fell back to the whole canvas —
    // which holds nothing — so the drag lifted emptiness and the drawing
    // could not be moved at all.
    final env = await pumpSelectionPanel(
      tester,
      tool: CanvasTool.move,
      sourceDabs: [dab(-200, -200), dab(-180, -180)],
    );
    expect(inkAt(env.coordinator, -200, -200), isNonZero);

    await dragOnLayer(tester, const Offset(45, 45), const Offset(55, 50));
    env.commands.confirmPendingMove();
    await tester.pump();

    expect(
      inkAt(env.coordinator, -190, -195),
      isNonZero,
      reason: 'pasteboard-only ink moves like any other picture',
    );
    expect(inkAt(env.coordinator, -200, -200), 0);
  });

  testWidgets('a press on the PASTEBOARD grabs the whole picture too — the '
      'box frames ink you can also take hold of', (tester) async {
    // The handles were already grabbable off-canvas (_hitTestTransformHandle
    // has no stage gate), so once the box frames pasteboard ink, a
    // canvas-only press gate leaves exactly one thing you can see framed
    // and cannot grab by pressing on it.
    const small = CanvasSize(width: 200, height: 150);
    final env = await pumpSelectionPanel(
      tester,
      tool: CanvasTool.move,
      canvasSize: small,
      sourceDabs: [dab(30, 30), dab(300, 100)],
    );
    // The viewport is identity here, so widget offsets ARE canvas
    // coordinates. (250,60) is past the 200-wide canvas — pasteboard —
    // and well clear of the implicit box's handles, which sit on the
    // corners and edge midpoints of the ink bounds and are grabbable
    // off-canvas already: pressing the corner at (300,100) scales
    // instead of moving, which is how this test first read as a failure.
    expect(inkAt(env.coordinator, 300, 100), isNonZero);
    expect(
      small.containsPasteboardPoint(x: 250, y: 60),
      isTrue,
      reason: '(250,60) is past the 200×150 canvas but inside its pasteboard',
    );

    await dragOnLayer(tester, const Offset(250, 60), const Offset(260, 65));
    expect(
      env.commands.movePending,
      isTrue,
      reason: 'the press on the pasteboard opened the implicit session',
    );
    env.commands.confirmPendingMove();
    await tester.pump();
    // TRANSLATION, asserted at both ends: a handle grab would scale about
    // the opposite corner and leave the anchor ink standing, so "the old
    // place is empty" is the assertion that tells a move from a scale.
    expect(
      inkAt(env.coordinator, 310, 105),
      isNonZero,
      reason: 'the pasteboard dab moved +10,+5',
    );
    expect(inkAt(env.coordinator, 298, 98), 0, reason: 'and left its old one');
    expect(
      inkAt(env.coordinator, 40, 35),
      isNonZero,
      reason: 'and so did the in-canvas one — one picture, one move',
    );
    expect(inkAt(env.coordinator, 28, 28), 0, reason: 'nothing stayed behind');
  });

  testWidgets('R28 #10: a SECOND transform on the same tool works — the '
      'first one\'s confirm must not leave the layer unable to lift', (
    tester,
  ) async {
    // The user\'s report is about transforming twice in a row WITHOUT
    // switching tools ("변형 한번하고 다시 변형하면"), which is the one path
    // the R27 #18 fix did not cover — it hung the cleanup on a tool
    // change. Both rounds here run on the Move tool.
    final env = await pumpSelectionPanel(tester, tool: CanvasTool.move);

    // Round 1: implicit whole-picture transform, confirmed.
    env.commands.beginTransform();
    await tester.pump();
    expect(env.commands.transformActive, isTrue);
    await dragOnLayer(tester, const Offset(45, 45), const Offset(55, 45));
    env.commands.commitTransform();
    await tester.pump();
    expect(env.commands.transformActive, isFalse);
    expect(inkAt(env.coordinator, 40, 30), isNonZero, reason: '+10 landed');
    expect(
      inkAt(env.coordinator, 30, 30),
      0,
      reason: 'the origin is empty — the lift erased it',
    );

    // Round 2: the SAME thing again.
    env.commands.beginTransform();
    await tester.pump();
    expect(
      env.commands.transformActive,
      isTrue,
      reason: 'R28 #10: the second transform must actually OPEN',
    );
    expect(
      inkAt(env.coordinator, 40, 30),
      0,
      reason:
          'R28 #10: the second lift has to ERASE its origin too — '
          'leaving it is how the user saw "원본그림 존재하고 변형된 그림도 존재"',
    );

    // The picture moved +10, so the box did too — grab it where it now is.
    await dragOnLayer(tester, const Offset(55, 45), const Offset(65, 45));
    env.commands.commitTransform();
    await tester.pump();
    expect(
      inkAt(env.coordinator, 50, 30),
      isNonZero,
      reason: 'the second +10 landed',
    );
    expect(inkAt(env.coordinator, 40, 30), 0);
  });

  testWidgets('R26 #13: REVERTING the implicit whole-picture session '
      'restores the picture, leaves NO selection and records NOTHING', (
    tester,
  ) async {
    final env = await pumpSelectionPanel(tester, tool: CanvasTool.move);
    final entriesBefore = env.history.undoCount;

    await dragOnLayer(tester, const Offset(45, 45), const Offset(55, 50));
    expect(env.commands.movePending, isTrue);

    env.commands.revertPendingMove();
    await tester.pump();
    expect(inkAt(env.coordinator, 30, 30), isNonZero);
    expect(env.commands.hasSelection, isFalse);
    expect(env.history.undoCount, entriesBefore);
  });

  testWidgets('퍼스 mode: a corner drag warps the quad with NO modifier, '
      'and Enter commits ONE resampled entry', (tester) async {
    final env = await pumpSelectionPanel(
      tester,
      transformMode: TransformMode.perspective,
    );
    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    await env.setTool(CanvasTool.move);
    final entriesBefore = env.history.undoCount;

    // Straight onto the top-left corner and inward. No Ctrl: the MODE is
    // the door, which is what makes the gesture reachable on a tablet.
    await dragOnLayer(tester, const Offset(20, 20), const Offset(34, 24));

    expect(env.commands.transformActive, isTrue, reason: 'quad session open');
    expect(
      env.commands.transformValues,
      isNotNull,
      reason:
          'the affine lives UNDER the warp now, so the numeric channels '
          'keep their meaning in every mode',
    );

    // Enter: resample through the homography + confirm as ONE entry.
    env.commands.commitTransform();
    await tester.pump();
    expect(env.commands.movePending, isFalse);
    expect(env.history.undoCount, entriesBefore + 1);

    // One undo restores the pre-lift picture whole.
    env.history.undo();
    await tester.pump();
    expect(inkAt(env.coordinator, 30, 30), isNonZero);
  });

  testWidgets('퍼스 mode with every offset still zero resamples through the '
      'AFFINE path — an untouched quad is not a warp', (tester) async {
    final env = await pumpSelectionPanel(
      tester,
      transformMode: TransformMode.perspective,
    );
    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    await env.setTool(CanvasTool.move);

    // Scale by an EDGE handle: in 퍼스 that is an affine drag, and with no
    // corner touched the commit must take the affine path rather than a
    // homography that only happens to agree with it.
    await dragOnLayer(tester, const Offset(45, 20), const Offset(45, 12));
    expect(env.commands.transformActive, isTrue);
    final values = env.commands.transformValues;
    expect(values, isNotNull);
    expect(
      values!.rotationDegrees,
      0,
      reason: 'an edge drag scales, it does not rotate',
    );

    env.commands.commitTransform();
    await tester.pump();
    expect(env.commands.movePending, isFalse);
  });

  testWidgets('mode switches carry the box: a 퍼스 warp survives a trip '
      'through 일반 and back', (tester) async {
    final env = await pumpSelectionPanel(
      tester,
      transformMode: TransformMode.perspective,
    );
    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    await env.setTool(CanvasTool.move);
    await dragOnLayer(tester, const Offset(20, 20), const Offset(34, 24));
    expect(env.commands.transformActive, isTrue);

    // Narrowing drops the warp on screen...
    env.transformOptions.value = env.transformOptions.value.copyWith(
      mode: TransformMode.normal,
    );
    await tester.pump();
    expect(
      env.commands.transformActive,
      isTrue,
      reason: 'a mode switch must not confirm or close the open box',
    );

    // ...and widening brings it back, because narrowing stashed it. The
    // alternative — losing the warp on a mis-click — is the reason the
    // offsets are held rather than baked.
    env.transformOptions.value = env.transformOptions.value.copyWith(
      mode: TransformMode.perspective,
    );
    await tester.pump();
    env.commands.commitTransform();
    await tester.pump();
    expect(env.commands.movePending, isFalse);
  });

  testWidgets('메쉬 mode: the control grid comes up WITH the box, a dragged '
      'point + Enter commits ONE warped entry', (tester) async {
    final env = await pumpSelectionPanel(
      tester,
      transformMode: TransformMode.mesh,
    );
    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    await env.setTool(CanvasTool.move);
    final entriesBefore = env.history.undoCount;

    // The mesh has no button any more — the mode is the door, and any
    // ordinary open brings the grid with it.
    env.commands.beginTransform();
    await tester.pump();
    expect(env.commands.transformActive, isTrue);
    expect(
      env.commands.transformValues,
      isNotNull,
      reason:
          'the grid rides ON an affine, so X/Y/angle/scale still describe '
          'something even here',
    );
    // Drag an interior control point (stamp rect (20,20)-(71,71), 3×3
    // cells → pitch 17: the (1,1) point sits at (37,37)).
    await dragOnLayer(tester, const Offset(37, 37), const Offset(31, 42));
    await pumpUntil(
      tester,
      previewIsUp,
      reason:
          'the live warp preview to mount — it appears once there is a warp '
          'to show, an all-zero grid resampling nothing by design',
    );
    expect(
      find.byKey(const ValueKey<String>('transform-resample-preview')),
      findsOneWidget,
    );

    env.commands.commitTransform();
    await tester.pump();
    expect(env.commands.movePending, isFalse);
    expect(env.history.undoCount, entriesBefore + 1);

    env.history.undo();
    await tester.pump();
    expect(
      inkAt(env.coordinator, 30, 30),
      isNonZero,
      reason: 'one undo restores the pre-lift picture',
    );
  });

  testWidgets('an EMPTY cel takes the transform tool and refuses the EDIT: '
      'quietly, and it says so through the channel', (tester) async {
    // A cel whose only ink is off-canvas is still ink; `sourceDabs: []`
    // is the empty one this needs.
    final env = await pumpSelectionPanel(
      tester,
      tool: CanvasTool.move,
      sourceDabs: const [],
    );

    expect(
      env.commands.canEditTransform,
      isFalse,
      reason: 'nothing to transform — but the TOOL is armed regardless',
    );

    // Every edit entrance is inert, and none of them says anything: the
    // refusal is the flat control, not a notice per tap.
    env.commands.beginTransform();
    await tester.pump();
    expect(env.commands.transformActive, isFalse);

    env.commands.setTransformValues(
      tx: 10,
      ty: 10,
      rotationDegrees: 0,
      scale: 1,
    );
    await tester.pump();
    expect(env.commands.transformActive, isFalse);
    expect(env.commands.hasSelection, isFalse);
    expect(env.history.undoCount, 0);
  });

  testWidgets('the gate follows the CEL, not the tool switch: ink makes the '
      'same tool editable', (tester) async {
    final env = await pumpSelectionPanel(tester, tool: CanvasTool.move);
    expect(
      env.commands.canEditTransform,
      isTrue,
      reason: 'the fixture cel has a stroke in it',
    );

    // The old gate asked `celHasRenderableContent` — three map lookups
    // that answer "does a cel exist", so a blank one passed and the lift
    // then came back empty. The live predicate reads the INK bounds.
    env.commands.beginTransform();
    await tester.pump();
    expect(env.commands.transformActive, isTrue);
  });

  testWidgets('flip mirrors the box, and 리셋 clears the numbers AND the '
      'warp', (tester) async {
    final env = await pumpSelectionPanel(tester, tool: CanvasTool.move);

    env.commands.flipTransform(horizontal: true);
    await tester.pump();
    expect(
      env.commands.transformActive,
      isTrue,
      reason: 'with no box open, a flip opens one — like the numeric fields',
    );
    expect(env.commands.transformValues?.scale, -1);

    env.commands.setTransformValues(
      tx: 12,
      ty: 0,
      rotationDegrees: 30,
      scale: 2,
    );
    await tester.pump();
    env.commands.resetTransform();
    await tester.pump();
    final values = env.commands.transformValues;
    expect(values?.tx, 0);
    expect(values?.rotationDegrees, 0);
    expect(values?.scale, 1);
  });

  testWidgets('적용 with nothing transformed REPLAYS the last committed '
      'values, and does not commit them until pressed again', (tester) async {
    final env = await pumpSelectionPanel(tester, tool: CanvasTool.move);

    // Commit something worth remembering.
    env.commands.setTransformValues(
      tx: 10,
      ty: 4,
      rotationDegrees: 0,
      scale: 1,
    );
    await tester.pump();
    env.commands.commitTransform();
    await tester.pump();
    final entriesAfterFirst = env.history.undoCount;

    // Now an untouched box. 적용 recalls rather than committing — the
    // values land where they can be seen, and history does not move.
    env.commands.beginTransform();
    await tester.pump();
    env.commands.applyTransform();
    await tester.pump();
    expect(env.commands.transformValues?.tx, 10);
    expect(env.commands.transformValues?.ty, 4);
    expect(
      env.history.undoCount,
      entriesAfterFirst,
      reason: '재현만 — the recall is not a commit',
    );

    // The second press is the one that applies.
    env.commands.applyTransform();
    await tester.pump();
    expect(env.history.undoCount, entriesAfterFirst + 1);
  });

  testWidgets('the preview clips ONLY while a handle is being dragged, and '
      'goes back to the whole rect the moment it is released', (tester) async {
    // A canvas larger than the 800×600 test viewport, so a whole-picture
    // box really is bigger than the screen and clipping has something to
    // clip.
    const big = CanvasSize(width: 1800, height: 1400);
    await pumpSelectionPanel(
      tester,
      tool: CanvasTool.move,
      canvasSize: big,
      sourceDabs: [dab(100, 100), dab(700, 600), dab(1500, 1200)],
      viewport: CanvasViewport(),
    );

    final origin = tester.getTopLeft(find.byKey(layerKey));
    // The box frames the ink, which runs to (1500,1200) — far past the
    // 800×600 test viewport, so a window really is smaller. Its TOP-LEFT
    // handle is the one that is on screen to grab.
    final gesture = await tester.startGesture(origin + const Offset(100, 100));
    await tester.pump();
    await gesture.moveTo(origin + const Offset(60, 55));
    await tester.pump();
    // Wait for the resample to have HAPPENED, not for a stopwatch — the
    // same lesson the mesh test above learned the hard way.
    await pumpUntil(
      tester,
      () => debugLastResampledFloat?.stamp != null,
      reason: 'the drag-time resample',
    );
    final duringDrag = debugLastResampledFloat!.stamp!.width;

    await gesture.up();
    // Releasing widens it back out to the whole rect.
    await pumpUntil(
      tester,
      () => (debugLastResampledFloat?.stamp?.width ?? duringDrag) > duringDrag,
      reason: 'the at-rest resample to widen past the drag-time window',
    );
    final atRest = debugLastResampledFloat!.stamp!.width;

    expect(
      duringDrag,
      lessThan(atRest),
      reason:
          'mid-drag the preview covers the viewport; at rest it covers the '
          'whole rect, because the viewport can MOVE at rest and a window '
          'computed for where the user was is a window with a hole in it',
    );
  });

  testWidgets('a transform dragged with most of the picture OFF SCREEN '
      'still lands all of it', (tester) async {
    // The failure this exists for: the preview resamples only the visible
    // window, and if that window ever reached the commit the user would
    // keep the rectangle they could see and lose the rest of the drawing.
    // Three things are supposed to prevent it — the commit asks for no
    // window, the window is part of the cache key so it cannot be handed
    // one, and clipping only happens mid-drag while the commit happens at
    // rest. This checks the OUTCOME rather than any of the three.
    const big = CanvasSize(width: 1800, height: 1400);
    final env = await pumpSelectionPanel(
      tester,
      tool: CanvasTool.move,
      canvasSize: big,
      // The far dab sits at (1500,1200) — far outside the 800×600 test
      // viewport, and therefore outside every window the preview ever
      // computed during the drag below.
      sourceDabs: [dab(100, 100), dab(700, 600), dab(1500, 1200)],
      viewport: CanvasViewport(),
    );
    expect(
      inkAt(env.coordinator, 1500, 1200),
      isNonZero,
      reason: 'the far ink is there to begin with',
    );
    final entriesBefore = env.history.undoCount;

    // Scale by the top-left handle, which is the one on screen. The drag
    // is what turns clipping on.
    await dragOnLayer(tester, const Offset(100, 100), const Offset(40, 30));
    expect(env.commands.transformActive, isTrue);
    env.commands.commitTransform();
    await tester.pump();

    expect(
      env.history.undoCount,
      entriesBefore + 1,
      reason: 'the transform really committed',
    );
    expect(
      inkAt(env.coordinator, 1500, 1200),
      isNonZero,
      reason:
          'the far corner is the anchor, so it lands where it started — and '
          'it is still THERE, which is what says the commit landed the '
          'whole picture and not the window the preview was drawing',
    );
  });

  testWidgets('the ANCHOR is a setting, and Alt inverts it for one drag', (
    tester,
  ) async {
    // Centre-anchored: the box grows both ways, so the corner OPPOSITE the
    // grabbed one moves too. With the default anchor it would stay put.
    final env = await pumpSelectionPanel(tester);
    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    await env.setTool(CanvasTool.move);
    env.transformOptions.value = env.transformOptions.value.copyWith(
      anchor: TransformAnchor.center,
    );
    await tester.pump();

    // BR (70,70) out to (95,95) is 2× about the centre (45,45), so the
    // stroke's ends map 30→15 and 60→75. Anchored at the opposite corner
    // the same drag would be 1.5× about (20,20), putting them at 35 and 80.
    await dragOnLayer(tester, const Offset(70, 70), const Offset(95, 95));
    env.commands.commitTransform();
    await tester.pump();
    expect(
      inkAt(env.coordinator, 75, 75),
      isNonZero,
      reason:
          'the grabbed end went out to 75, not the 80 a corner anchor '
          'would have given',
    );
    expect(
      inkAt(env.coordinator, 15, 15),
      isNonZero,
      reason:
          'and the far end came out to meet it — that is what "anchor at '
          'the centre" means, and it used to need Alt held down',
    );
  });

  testWidgets('a finger landing mid-transform is IGNORED: the drag survives '
      'and the canvas does not pan', (tester) async {
    final env = await pumpSelectionPanel(tester);
    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    await env.setTool(CanvasTool.move);

    final origin = tester.getTopLeft(find.byKey(layerKey));
    // Grab the BR corner with the pen and start scaling...
    final pen = await tester.startGesture(
      origin + const Offset(70, 70),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await pen.moveTo(origin + const Offset(85, 85));
    await tester.pump();
    expect(env.commands.transformActive, isTrue);

    // ...then rest a palm on the glass. This used to cancel the drag and
    // hand the gesture to the viewport (유저: "변형 도중 터치 들어오면
    // 변형 멈춰버리는데").
    final palm = await tester.startGesture(
      origin + const Offset(20, 200),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    await pen.moveTo(origin + const Offset(95, 95));
    await tester.pump();
    await palm.up();
    await pen.up();
    await tester.pump();

    expect(
      env.commands.transformActive,
      isTrue,
      reason: 'the transform is still open — the finger changed nothing',
    );
    env.commands.commitTransform();
    await tester.pump();
    expect(
      inkAt(env.coordinator, 80, 80),
      isNonZero,
      reason: 'the scale the pen was drawing landed in full',
    );
  });

  testWidgets('메쉬 mode keeps the affine: a scaled box that switches to '
      '메쉬 stays scaled', (tester) async {
    final env = await pumpSelectionPanel(tester);
    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    await env.setTool(CanvasTool.move);

    // Scale by a corner in 일반, then switch to 메쉬. The grid used to be
    // seeded from the UNtransformed stamp rect, which threw the scale
    // away; holding the warp as offsets on top of the affine cannot.
    await dragOnLayer(tester, const Offset(20, 20), const Offset(10, 10));
    final scaled = env.commands.transformValues;
    expect(scaled, isNotNull);
    expect(scaled!.scale, isNot(1.0));

    env.transformOptions.value = env.transformOptions.value.copyWith(
      mode: TransformMode.mesh,
    );
    await tester.pump();
    expect(
      env.commands.transformValues?.scale,
      scaled.scale,
      reason: 'switching modes must not silently undo the scale',
    );
  });

  testWidgets('the session floats through the WHOLE interaction: the base '
      'holds only the erase until the confirm; a zero-move confirm is a '
      'byte-identical landing (R16-①)', (tester) async {
    final env = await pumpSelectionPanel(tester);
    final beforeLift = currentSurface(env.coordinator);
    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    await env.setTool(CanvasTool.move);

    final origin = tester.getTopLeft(find.byKey(layerKey));
    final gesture = await tester.startGesture(origin + const Offset(45, 45));
    await tester.pump();
    // Mid-drag: the base carries the erase but NOT the stamp — the base
    // never shows the moving pixels (no double image).
    expect(inkAt(env.coordinator, 30, 30), 0);
    expect(inkAt(env.coordinator, 45, 45), 0);

    // Zero-move release: the session STAYS pending (the float keeps
    // showing the pixels); the base still holds only the erase.
    await gesture.up();
    await tester.pump();
    expect(env.commands.movePending, isTrue);
    expect(inkAt(env.coordinator, 45, 45), 0);

    // Confirm: the stamp lands at its origin — byte-identical picture
    // (the R14-④ zero-move lift-and-drop pin, now at the widget level).
    env.commands.confirmPendingMove();
    await tester.pump();
    expect(env.commands.movePending, isFalse);
    expect(currentSurface(env.coordinator), equals(beforeLift));
  });

  testWidgets('REVERT puts the pixels back exactly and records nothing '
      '(R17-①: the prompt\'s 되돌리기)', (tester) async {
    final env = await pumpSelectionPanel(tester);
    final beforeLift = currentSurface(env.coordinator);
    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    await env.setTool(CanvasTool.move);
    final entriesBefore = env.history.undoCount;

    await dragOnLayer(tester, const Offset(45, 45), const Offset(60, 60));
    expect(env.commands.movePending, isTrue);

    env.commands.revertPendingMove();
    await tester.pump();

    expect(env.commands.movePending, isFalse);
    expect(
      identical(currentSurface(env.coordinator), beforeLift),
      isTrue,
      reason: 'the pre-lift surface snapshot restores BY REFERENCE',
    );
    expect(env.history.undoCount, entriesBefore, reason: 'nothing recorded');
  });

  testWidgets('selecting and deselecting are undoable steps (R11-⑧)', (
    tester,
  ) async {
    final env = await pumpSelectionPanel(tester);

    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    expect(env.commands.hasSelection, isTrue);
    expect(env.history.canUndo, isTrue);

    env.history.undo();
    await tester.pump();
    expect(env.commands.hasSelection, isFalse);

    env.history.redo();
    await tester.pump();
    expect(env.commands.hasSelection, isTrue);

    // Ctrl+D is undoable too.
    env.commands.deselect();
    await tester.pump();
    expect(env.commands.hasSelection, isFalse);
    env.history.undo();
    await tester.pump();
    expect(env.commands.hasSelection, isTrue);
  });

  testWidgets('a marquee missing the stroke selects nothing movable', (
    tester,
  ) async {
    final env = await pumpSelectionPanel(tester);

    await dragOnLayer(tester, const Offset(100, 100), const Offset(140, 140));
    expect(env.commands.hasSelection, isTrue);

    // The move tool grabs nothing there (the region covers no pixels).
    await env.setTool(CanvasTool.move);
    await dragOnLayer(tester, const Offset(110, 110), const Offset(120, 120));
    expect(inkAt(env.coordinator, 30, 30), isNonZero);
  });

  testWidgets('click-away and Ctrl+D deselect; nudges move by one pixel', (
    tester,
  ) async {
    final env = await pumpSelectionPanel(tester);

    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    expect(env.commands.hasSelection, isTrue);

    // Arrow nudges move the SESSION's float only (R16-①); the confirm
    // lands the accumulated result as one entry.
    env.commands.nudge(1, 0);
    env.commands.nudge(0, -1);
    await tester.pump();
    expect(env.commands.movePending, isTrue);
    expect(inkAt(env.coordinator, 30, 30), 0, reason: 'origin erased');
    env.commands.confirmPendingMove();
    await tester.pump();
    expect(
      inkAt(env.coordinator, 31, 29),
      isNonZero,
      reason: 'pixels landed at the nudged position (+1,−1)',
    );

    // Ctrl+D (through the channel) deselects.
    env.commands.deselect();
    await tester.pump();
    expect(env.commands.hasSelection, isFalse);

    // Re-select. R26 #16: in the DEFAULT 추가 mode a click is inert —
    // clicking away must not throw a composite selection away.
    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    expect(env.commands.hasSelection, isTrue);
    await tester.tapAt(
      tester.getTopLeft(find.byKey(layerKey)) + const Offset(150, 150),
    );
    await tester.pump();
    expect(env.commands.hasSelection, isTrue);

    // In 갱신 (replace) mode the click-away deselect is back — Photoshop's.
    env.commands.combineMode = SelectionCombineMode.replace;
    await tester.pump();
    await tester.tapAt(
      tester.getTopLeft(find.byKey(layerKey)) + const Offset(150, 150),
    );
    await tester.pump();
    expect(env.commands.hasSelection, isFalse);
  });

  group('Ctrl+T free transform (R19 pixel model: lift + stamp resample)', () {
    testWidgets('inside-drag translates; Enter confirms the session as one '
        'undo entry — pure translation lands byte-preserved pixels', (
      tester,
    ) async {
      final env = await pumpSelectionPanel(tester);
      await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));

      env.commands.beginTransform();
      await tester.pump();
      expect(env.commands.transformActive, isTrue);
      expect(
        inkAt(env.coordinator, 30, 30),
        0,
        reason: 'Ctrl+T opened a lift session — the base holds the erase',
      );

      // Drag inside the box: rides the session (nothing committed yet —
      // the history holds only the marquee's Select entry).
      final undoDepthBefore = env.history.undoCount;
      await dragOnLayer(tester, const Offset(45, 45), const Offset(55, 48));
      expect(env.history.undoCount, undoDepthBefore);

      env.commands.commitTransform();
      await tester.pump();
      expect(env.commands.transformActive, isFalse);
      // The (+10,+3) translation landed: (30,30) → (40,33).
      expect(inkAt(env.coordinator, 40, 33), isNonZero);
      expect(inkAt(env.coordinator, 30, 30), 0);
      expect(env.history.canUndo, isTrue);
      env.history.undo();
      expect(
        inkAt(env.coordinator, 30, 30),
        isNonZero,
        reason: 'one Ctrl+Z retires the whole lift session',
      );
    });

    testWidgets('a freshly lifted float never paints pixels its own surface '
        'does not have', (tester) async {
      // The user-visible bug: opening a transform made the artwork
      // "teleport somewhere else, apparently enlarged" for a frame and
      // come back.
      //
      // The float surface is materialised fresh from the lift, so every
      // tile object is new and the identity-keyed image cache misses on
      // all of them. The painter's answer to a missing image is to borrow
      // whatever decoded last at that COORDINATE within its stale scope —
      // and the float was the one painter in lib/ built without a scope,
      // which put it in a bucket shared by every float ever lifted. The
      // second Ctrl+T of a session therefore drew the FIRST one's artwork,
      // at the first one's place and size, into this float's tile grid.
      //
      // Stated as the invariant rather than the symptom: a painter may not
      // put ink where its own surface is empty. That holds whatever the
      // borrowing policy is, and it is what fails if the opt-out is
      // removed.
      final env = await pumpSelectionPanel(tester, tool: CanvasTool.move);
      await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));

      Future<void> settle() async {
        for (var i = 0; i < 8; i += 1) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 16)),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      BitmapSurfacePainter floatPainter() {
        final committed = env.coordinator.currentSurfaceOf(
          env.coordinator.activeFrameKey,
        );
        final floats = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((paint) => paint.painter)
            .whereType<BitmapSurfacePainter>()
            .where((painter) => !identical(painter.surface, committed))
            .toList();
        expect(
          floats,
          hasLength(1),
          reason: 'expected exactly one float painter over the committed one',
        );
        return floats.single;
      }

      // Generation one, decoded, so the shared bucket is populated with a
      // float's tiles at these coordinates.
      env.commands.beginTransform();
      await tester.pump();
      final generationOne = floatPainter().surface;
      await settle();
      env.commands.setTransformValues(
        tx: 0,
        ty: 0,
        rotationDegrees: 0,
        scale: 0.4,
      );
      await tester.pump();
      await settle();
      env.commands.commitTransform();
      await tester.pump();
      await settle();

      // Generation two — the reported gesture. Its tiles are new and
      // undecoded, and the bucket from generation one is waiting.
      env.commands.beginTransform();
      await tester.pump();
      final painter = floatPainter();
      expect(
        identical(painter.surface, generationOne),
        isFalse,
        reason:
            'the second lift reused the first float — no borrowing '
            'could happen and this test would prove nothing',
      );
      await tester.runAsync(() async {
        final recorder = PictureRecorder();
        const size = Size(256, 256);
        painter.paint(Canvas(recorder, Offset.zero & size), size);
        final image = await recorder.endRecording().toImage(256, 256);
        final data = await image.toByteData(format: ImageByteFormat.rawRgba);
        final painted = data!.buffer.asUint8List();
        var ghost = 0;
        var missing = 0;
        for (var y = 0; y < 256; y += 1) {
          for (var x = 0; x < 256; x += 1) {
            final alpha = painted[(y * 256 + x) * 4 + 3];
            final own = surfacePixelRgba(painter.surface, x, y) ?? 0;
            if (alpha > 0 && ((own >> 24) & 0xff) == 0) {
              ghost += 1;
            } else if (alpha == 0 && ((own >> 24) & 0xff) > 0) {
              missing += 1;
            }
          }
        }
        expect(
          ghost,
          0,
          reason:
              'the float painted $ghost pixels of artwork its own '
              'surface does not contain',
        );
        // The other half of the same frame, and the half a first attempt
        // at this fix got wrong. Not borrowing trades a wrong picture for
        // an ABSENT one, and absent is only acceptable while it does not
        // happen: an undecoded tile falls to the painter's per-pixel path,
        // whose budget is FOUR TILES a frame.
        expect(
          missing,
          0,
          reason:
              'the float left $missing pixels of its own artwork '
              'unpainted — the per-pixel budget no longer covers it',
        );
      });

      // Secondary, and deliberately AFTER the render: the scope is how the
      // invariant is currently kept, but the invariant is the contract. A
      // test that asserted only the scope would pass a painter that had one
      // and borrowed across a lift anyway.
      expect(
        painter.staleScope,
        isNotNull,
        reason: 'a scopeless painter shares the bucket every float writes to',
      );
    });

    testWidgets('a float that only MOVED keeps borrowing its own previous '
        'generation', (tester) async {
      // The regression the first version of this fix shipped, and the test
      // that would have caught it.
      //
      // `_floatSurface` is rebuilt from an empty surface at five sites, and
      // three of them regenerate a float that ALREADY EXISTS: a drag
      // release, every arrow-key nudge, and Ctrl+T over a pending move.
      // There the previous generation is a legitimate predecessor. Refusing
      // to borrow across it left a float wider than the painter's four-tile
      // per-pixel budget three-quarters blank for a frame — and under a
      // held arrow key, which regenerates about thirty times a second, it
      // strobed.
      //
      // So the scope is emptied when the float's CONTENT changes and not
      // when it merely moves. This is the "merely moves" half, and the
      // fixture must be WIDER than four tiles or the per-pixel path covers
      // the mistake and the test proves nothing.
      final env = await pumpSelectionPanel(tester);
      // The float only holds tiles where the lift found pixels, so the
      // fixture's small stroke yields two however wide the marquee is. A
      // diagonal across the cel is what puts more than four tiles in it —
      // and more than four is the whole point, because at four or fewer
      // the painter's per-pixel path hides the defect.
      env.coordinator.commitSourceStroke(
        sourceDabs: <BrushDab>[
          for (var step = 0; step <= 24; step += 1)
            dab(80 + step * 36.0, 80 + step * 26.0),
        ],
      );
      await tester.pump();
      await dragOnLayer(tester, const Offset(6, 6), const Offset(720, 540));
      await env.setTool(CanvasTool.move);

      BitmapSurfacePainter floatPainter() {
        final committed = env.coordinator.currentSurfaceOf(
          env.coordinator.activeFrameKey,
        );
        return tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((paint) => paint.painter)
            .whereType<BitmapSurfacePainter>()
            .firstWhere((painter) => !identical(painter.surface, committed));
      }

      // A move drag: the lift happens on the way, and the release runs
      // `_commitMove`, which is the first of the three rebuilds that have
      // a legitimate predecessor.
      await dragOnLayer(tester, const Offset(300, 250), const Offset(310, 258));
      for (var i = 0; i < 10; i += 1) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 16)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }

      final lifted = floatPainter().surface;
      expect(
        lifted.tiles.length,
        greaterThan(4),
        reason:
            'a float inside the four-tile per-pixel budget cannot show '
            'this defect — widen the marquee',
      );

      // A NUDGE: the same picture, one pixel over.
      //
      // ⚠️ This test used to end differently, and the difference is the
      // point. It asserted that the nudge REBUILDS the float and that the
      // rebuilt tiles can borrow their own previous generation — because
      // borrowing was the only thing standing between a rebuilt float and
      // a blank frame. That borrow was always a half-truth: it is the
      // right pixels at the PREVIOUS PLACE, so a nudged float painted the
      // picture one step behind, and a released drag painted it a whole
      // drag behind. It is why the confirm frame of a wide move was 44%
      // absent, and why the user saw tiles jump.
      //
      // A move does not rebuild anything now. The surface stays where it
      // was materialized, its tiles keep the images they already decoded,
      // and the offset is carried at draw time. So the invariant is no
      // longer "the rebuild can borrow" but "there is no rebuild", and
      // the defect the old assertion guarded cannot be expressed.
      env.commands.nudge(1, 0);
      await tester.pump();
      final nudged = floatPainter();
      expect(
        identical(nudged.surface, lifted),
        isTrue,
        reason:
            'a nudge rebuilt the float — it is a translation, not new '
            'pixels, and a rebuilt surface has no decoded tiles to paint',
      );
      var undecoded = 0;
      for (final tile in nudged.surface.tiles.values) {
        if (BitmapTileImageCache.instance.imageFor(tile) == null) {
          undecoded += 1;
        }
      }
      expect(
        undecoded,
        0,
        reason:
            '$undecoded of the float\'s tiles cannot paint after a nudge; '
            'the whole point of not rebuilding is that they already did',
      );
    });

    testWidgets('the green confirm button commits the WARPED stamp, the '
        'same as Enter', (tester) async {
      // The button's visibility test is `_movePending`, which says nothing
      // about whether a transform box is open — so it IS offered mid-Ctrl+T.
      // Wired straight to `_confirmMoveSession` it landed the UNWARPED
      // lift: the artwork committed at its pre-transform position and size,
      // the warped preview kept painting on top of the wrong landing until
      // something closed the box, and the wrong landing went into history.
      // Enter has branched on `_transform != null` since R16-①; the button
      // never did, and a user reaching for the check mark instead of the
      // key silently lost their transform.
      final env = await pumpSelectionPanel(tester);
      await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
      env.commands.beginTransform();
      await tester.pump();
      // BR (70,70) → (95,95): 1.5× about the anchored TL (20,20).
      await dragOnLayer(tester, const Offset(70, 70), const Offset(95, 95));
      await tester.pump();

      final button = find.byKey(
        const ValueKey<String>('selection-move-confirm'),
      );
      expect(
        button,
        findsOneWidget,
        reason:
            'the button is offered with the box open — that is the '
            'premise of this test, not an accident of it',
      );
      await tester.tap(button, warnIfMissed: false);
      await tester.pump();

      // The same landing the corner-scale test asserts for Enter.
      expect(inkAt(env.coordinator, 35, 35), isNonZero);
      expect(inkAt(env.coordinator, 80, 80), isNonZero);
      expect(
        inkAt(env.coordinator, 30, 30),
        0,
        reason: 'the unwarped lift landed at its pre-transform position',
      );
      expect(
        env.commands.transformActive,
        isFalse,
        reason: 'confirm left the box open over an already-committed stamp',
      );
    });

    testWidgets('the confirm button still confirms an untouched box in one '
        'tap', (tester) async {
      // The guard on the fix. `_commitTransform` on an identity affine only
      // closes the box and leaves the session pending, so branching the way
      // Enter does would turn one tap of a button labelled "confirm" into
      // two.
      final env = await pumpSelectionPanel(tester);
      await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
      env.commands.beginTransform();
      await tester.pump();
      final undoBefore = env.history.undoCount;

      await tester.tap(
        find.byKey(const ValueKey<String>('selection-move-confirm')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(env.commands.transformActive, isFalse);
      expect(env.commands.movePending, isFalse);
      // Two cleared booleans say the session ENDED, not that it was
      // confirmed — a revert clears them too, and on an IDENTITY box the
      // pixels cannot tell them apart either, because both leave the
      // artwork where it started. What distinguishes them is that a
      // confirm lands an entry and a revert does not.
      expect(
        env.history.undoCount,
        greaterThan(undoBefore),
        reason: 'the button reverted the session instead of confirming it',
      );
    });

    testWidgets('the frame a move CONFIRMS on still has the artwork on it', (
      tester,
    ) async {
      // The user's third symptom: "확정짓는 버튼 누르면 100%로 그림이
      // 아예 사라졌다가 다시생겨."
      //
      // `_confirmMoveSession` used to null the float in the same setState
      // that landed the stamp. The stamp's destination tiles are brand-new
      // objects with no decoded image, so the base painter's stale
      // fallback answered for them with the tiles the LIFT ERASED —
      // emptiness — and the float that had been covering them was already
      // gone. Measured, the selection vanished for two frames.
      //
      // The float is what should cover that, because it is not a stand-in:
      // by P3a's preview/commit byte-identity contract it holds exactly
      // these bytes at exactly this place.
      final env = await pumpSelectionPanel(tester, sourceDabs: widePicture);
      await dragOnLayer(tester, const Offset(20, 20), const Offset(700, 500));
      await env.setTool(CanvasTool.move);
      await dragOnLayer(tester, const Offset(300, 200), const Offset(340, 225));
      await tester.pump();

      // Something on screen must be able to paint the moved artwork: the
      // float, or the committed surface itself. Stated as the OR because
      // which one it is depends on decode timing, and the defect is that
      // on the confirm frame it was NEITHER.
      // ⚠️ "The float is UP" is NOT "the float PAINTS", and an earlier
      // version of this oracle only asked the first. Its tiles are new
      // objects, so they miss the identity-keyed image cache, and the
      // painter's per-pixel fallback covers four tiles a frame — so a
      // mutant that pinned an EMPTY surface, which is the user's symptom
      // verbatim, passed all 29 tests in this file. It asks the raster now.
      //
      // ⚠️ EVERY surface painter, the committed one included. This used to
      // exclude it and ask a separate question of the cache — "has every
      // committed tile decoded" — which stopped being the right question
      // once a committed tile could also answer with a picture composed
      // from the float. Two ways of asking meant a mechanism that made the
      // frame CORRECT could still read as a failure. The raster does not
      // care which mechanism drew.
      //
      // 🚨 THIS ORACLE COULD NOT FAIL, FOR TWO SEPARATE REASONS, AND BOTH
      // ARE FIXED HERE. Measured against a painter rebuilt with a
      // brand-new EMPTY cache — no decode, no stand-in, no borrow, no
      // upload, i.e. every mechanism the assertion names removed:
      //
      //  1. THE WINDOW. Sampled at 128×128 it sits inside a SINGLE 256px
      //     tile whatever the artwork is, so the four-tile per-pixel
      //     budget covers it alone: own=48 missing=0, pass. `widePicture`
      //     over the full 800×600 viewport puts twelve tiles in range,
      //     eight past the budget. Same reason `widePicture` exists at
      //     all — four tiles is the threshold below which every defect in
      //     this family is invisible.
      //  2. THE PAPER, which is the worse one and survived fix 1:
      //     `missing` asked whether the painted pixel had any ALPHA, and
      //     the base painter fills the canvas with opaque paper before it
      //     draws a single tile. So alpha is 255 everywhere in-canvas and
      //     `missing` was structurally 0 — own=1064 missing=0 on an empty
      //     cache. It has to ask for the INK, and it now uses the same
      //     red predicate `screenInkMask` does. With both fixed, the
      //     empty-cache painter reports missing=800 of 1064 and fails.
      bool isInk(Uint8List px, int offset) =>
          px[offset] > 128 && px[offset + 1] < 100 && px[offset + 2] < 100;
      Future<bool> somethingCanPaintIt() async {
        final painters = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((paint) => paint.painter)
            .whereType<BitmapSurfacePainter>()
            .toList();
        for (final painter in painters) {
          var own = 0;
          var missing = 0;
          await tester.runAsync(() async {
            final recorder = PictureRecorder();
            const size = Size(800, 600);
            painter.paint(Canvas(recorder, Offset.zero & size), size);
            final image = await recorder.endRecording().toImage(800, 600);
            final data = await image.toByteData(
              format: ImageByteFormat.rawRgba,
            );
            final painted = data!.buffer.asUint8List();
            // Stepped, like its neighbour: an exhaustive walk of 480k
            // pixels through a per-pixel tile lookup takes minutes and
            // finds nothing extra.
            for (var y = 0; y < 600; y += 2) {
              for (var x = 0; x < 800; x += 2) {
                final own32 = surfacePixelRgba(painter.surface, x, y) ?? 0;
                if (((own32 >> 24) & 0xff) == 0) continue;
                own += 1;
                if (!isInk(painted, (y * 800 + x) * 4)) missing += 1;
              }
            }
          });
          // `own > 0` rejects an empty pinned surface; `missing == 0`
          // rejects a painter the four-tile budget cannot cover.
          if (own > 0 && missing == 0) return true;
        }
        return false;
      }

      expect(
        await somethingCanPaintIt(),
        isTrue,
        reason: 'the float is not up during the session — bad premise',
      );

      env.commands.confirmPendingMove();
      await tester.pump();

      // THE frame the symptom is about.
      expect(
        await somethingCanPaintIt(),
        isTrue,
        reason:
            'the confirm frame has nothing that can paint the artwork — '
            'the float went before the committed tiles could take over',
      );
    });

    testWidgets('a freshly lifted float paints on its FIRST frame, not '
        'four tiles of it', (tester) async {
      // User report (08-04): "from the second transform on, when the
      // transform STARTS, the target intermittently disappears for about
      // a frame."
      //
      // What kept it on screen was never the float: it was the BASE
      // painter's stale borrow, still holding the pre-erase tiles. That
      // borrow dies the moment the erased tiles decode, and the float's
      // own tiles decode on their own schedule — so whether anything is
      // on screen in between is a race nothing in the code orders. The
      // float now borrows the tiles the lift took WHOLE, which are its
      // own pixels by construction, and paints immediately.
      final env = await pumpSelectionPanel(
        tester,
        tool: CanvasTool.move,
        sourceDabs: widePicture,
      );
      // The cel has to be ON SCREEN before it is lifted — that is the
      // premise of the whole mechanism, and it is not free in a widget
      // test: `decodeImageFromPixels` never completes inside `pump`'s
      // fake-async zone, so without this the base has no decoded tiles to
      // hand over and the seeding has nothing to seed.
      await settle(tester);

      env.commands.beginTransform();
      await tester.pump();

      final committed = env.coordinator.currentSurfaceOf(
        env.coordinator.activeFrameKey,
      );
      final floats = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<BitmapSurfacePainter>()
          .where((painter) => !identical(painter.surface, committed))
          .toList();
      expect(floats, isNotEmpty, reason: 'no float is up — bad premise');

      var own = 0;
      var missing = 0;
      await tester.runAsync(() async {
        final recorder = PictureRecorder();
        const size = Size(800, 600);
        floats.first.paint(Canvas(recorder, Offset.zero & size), size);
        final image = await recorder.endRecording().toImage(800, 600);
        final data = await image.toByteData(format: ImageByteFormat.rawRgba);
        final painted = data!.buffer.asUint8List();
        // Every second pixel on each axis: a tile the float cannot draw is
        // a 256 px square, and `surfacePixelRgba` is a tile lookup per
        // call — the exhaustive walk took minutes for no more evidence.
        for (var y = 0; y < 600; y += 2) {
          for (var x = 0; x < 800; x += 2) {
            final own32 = surfacePixelRgba(floats.first.surface, x, y) ?? 0;
            if (((own32 >> 24) & 0xff) == 0) continue;
            own += 1;
            if (painted[(y * 800 + x) * 4 + 3] == 0) missing += 1;
          }
        }
        image.dispose();
      });

      expect(own, greaterThan(0), reason: 'the float has no pixels at all');
      expect(
        missing,
        0,
        reason:
            'the float cannot draw $missing of its own $own pixels on the '
            'frame the lift opened',
      );
    });

    testWidgets('the frame a WARPED transform confirms on still has the '
        'artwork on it', (tester) async {
      // User report (08-04): "on confirming the transform the target
      // disappears for about a frame, almost 100% of the time."
      //
      // The move path above was covered; this one was not, and this is the
      // one the user hits. `_clearTransform` discarded the decoded
      // resample — the single image of exactly the bytes about to land —
      // and rebuilt the float from the warped stamp instead, which is
      // all-new tiles with no cache entries, so what replaced it could not
      // paint. Measured on the real panel: 0 of 107 sampled ink pixels on
      // the confirm frame.
      //
      // The oracle is the COMPOSITED panel, because the question is what
      // the user sees, not which object is mounted.
      //
      // ⚠️ The picture has to be BIGGER THAN FOUR TILES or the defect
      // cannot show: the painter's per-pixel fallback covers four tiles a
      // frame, so a landing that fits inside them is painted whatever
      // else is broken. Written first with the file's 30..60 fixture,
      // this test passed without the fix — that is the whole reason the
      // user sees this on big transforms and not on small ones.
      final env = await pumpSelectionPanel(
        tester,
        tool: CanvasTool.move,
        sourceDabs: widePicture,
      );

      env.commands.beginTransform();
      await tester.pump();
      env.commands.setTransformValues(
        tx: 20,
        ty: 12,
        rotationDegrees: 0,
        scale: 1.5,
      );
      // The resample decodes asynchronously; the preview being up is what
      // says the image the confirm will keep actually exists yet.
      await settle(tester);
      expect(
        find.byKey(const ValueKey<String>('transform-resample-preview')),
        findsOneWidget,
        reason: 'the warped preview never came up — bad premise',
      );

      env.commands.commitTransform();
      await tester.pump();
      final atConfirm = await screenInkMask(tester);

      await settle(tester);
      final settled = await screenInkMask(tester);
      final settledInk = settled.where((on) => on).length;
      final delta = inkDelta(atConfirm, settled);

      expect(settledInk, greaterThan(0), reason: 'the landing has ink at all');
      expect(
        delta.hole,
        lessThan((settledInk * 0.1).round()),
        reason:
            'the confirm frame is missing the artwork: ${delta.hole} of '
            '$settledInk absent (ghost ${delta.ghost})',
      );
      // And it must not be shown in the WRONG place: the base's stale
      // fallback paints the pre-lift picture at the pre-lift position, and
      // those pixels are ink too.
      expect(
        delta.ghost,
        lessThan((settledInk * 0.1).round()),
        reason:
            '${delta.ghost} pixels of artwork where the settled picture has '
            'none — a displaced copy',
      );
    });

    testWidgets('nothing of the confirm outlives it — the held picture is '
        'let go, and the frame it covered is covered', (tester) async {
      // Keeping a decoded image alive past the session is only safe if it
      // is also let go. A hold that outlived its release would paint one
      // transform state over every later edit for the rest of the session.
      //
      // ⚠️ The premise used to be "the preview IS mounted on the confirm
      // frame", and it stopped being true for a good reason: the landing's
      // tiles now get that same picture composed onto them, so the base
      // paints the landing itself and there is nothing left to hold. A
      // mount assertion cannot tell that apart from the hold failing, so
      // the frame is asked about instead — released early is only correct
      // if the artwork is still there, and that is the question.
      final env = await pumpSelectionPanel(
        tester,
        tool: CanvasTool.move,
        sourceDabs: widePicture,
      );
      env.commands.beginTransform();
      await tester.pump();
      env.commands.setTransformValues(
        tx: 20,
        ty: 12,
        rotationDegrees: 0,
        scale: 1.5,
      );
      await settle(tester);
      env.commands.commitTransform();
      await tester.pump();
      final atConfirm = await screenInkMask(tester);

      await settle(tester);
      final settled = await screenInkMask(tester);
      final settledInk = settled.where((on) => on).length;
      final delta = inkDelta(atConfirm, settled);
      expect(settledInk, greaterThan(0), reason: 'the landing has ink at all');
      expect(
        delta.hole,
        lessThan((settledInk * 0.1).round()),
        reason:
            'the confirm frame lost the artwork: ${delta.hole} of '
            '$settledInk absent',
      );
      expect(
        find.byKey(const ValueKey<String>('transform-resample-preview')),
        findsNothing,
        reason: 'the hold released but the preview is still mounted',
      );
    });

    testWidgets('a WIDE move confirms with the picture on screen too — the '
        'other branch of the hold', (tester) async {
      // The move path holds a float SURFACE rather than a resample image,
      // and it is the path the 208,234-pixel double-composite was measured
      // on. Both branches are clipped to the tiles the base cannot paint
      // yet, so both need a landing wider than one decode round.
      //
      // This one is GREEN without the fix, deliberately: the move path
      // already worked, and what it guards is that clipping the hold to
      // the pending tiles does not take away pixels the base still cannot
      // paint. A clip that is too eager fails here and nowhere else.
      final env = await pumpSelectionPanel(
        tester,
        tool: CanvasTool.move,
        sourceDabs: widePicture,
      );
      await dragOnLayer(tester, const Offset(300, 200), const Offset(340, 225));
      expect(env.commands.movePending, isTrue);
      // ⚠️ THE FLOAT HAS TO HAVE DECODED, and only `runAsync` gets it
      // there: `decodeImageFromPixels` never completes inside `pump`'s
      // fake async, so without this the float's tiles have no pictures at
      // the confirm — a state production cannot be in, because the user
      // has been looking at that float for the whole drag. Written
      // without it, this measured a confirm whose float had nothing to
      // give and reported no change from a fix that gives the base the
      // float's picture.
      await settle(tester);
      // ⚠️ THE FLOAT'S tiles, not just the cel's. The comment above names
      // the float as the premise, and the float is by this file's own
      // definition the surface that is NOT `currentSurface` — a separate
      // 9-tile object with its own tiles. Asserting only the cel read as
      // a guard and guarded the wrong thing: after a whole-picture lift
      // those cel tiles are fully TRANSPARENT, so their decodes put no
      // pixels in the frame the bound below measures, while the float's
      // are the operand `inkFromSurface` refuses to compose without.
      // (Both matter — the cel is the pre-image half of the composition —
      // so both are asserted.)
      final committedBefore = currentSurface(env.coordinator);
      final floatSurfaces = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<BitmapSurfacePainter>()
          .map((painter) => painter.surface)
          .where((surface) => !identical(surface, committedBefore))
          .toList();
      expect(
        floatSurfaces,
        isNotEmpty,
        reason: 'no float is mounted during the session — bad premise',
      );
      for (final surface in [committedBefore, ...floatSurfaces]) {
        expect(
          surface.tiles.values.every(
            (tile) =>
                BitmapTileImageCache.instance.displayImageFor(tile) != null,
          ),
          isTrue,
          reason:
              'decodes did not land in the settle window — the bound below '
              'is measuring the fixture, not the confirm',
        );
      }

      env.commands.confirmPendingMove();
      await tester.pump();
      final atConfirm = await screenInkMask(tester);
      await settle(tester);
      final settled = await screenInkMask(tester);
      final settledInk = settled.where((on) => on).length;
      final delta = inkDelta(atConfirm, settled);

      expect(settledInk, greaterThan(0));
      // 🚨 THIS BOUND USED TO READ 45%, AND THE 45 WAS THE FIXTURE.
      //
      // The comment here recorded a confirm frame "still missing about
      // 42% of the landing", tracked down from 55% and 44% across two
      // earlier fixes, and attributed the rest to the hold's own
      // coverage. It was none of that: the fixture never let the float
      // DECODE. `decodeImageFromPixels` does not complete inside `pump`'s
      // fake async, so the hold was covering with a surface that had no
      // pictures, and the four-tile per-pixel budget was all the coverage
      // there was. Production cannot be in that state — the user has been
      // looking at that float for the whole drag.
      //
      // With the `settle` above, the number is 0. Not "small": the hold
      // covers the landing exactly. So the bound is 0, and the premise
      // that makes it reachable is asserted rather than assumed.
      expect(
        delta.hole,
        0,
        reason:
            '${delta.hole} of $settledInk absent on the confirm frame '
            '(ghost ${delta.ghost})',
      );
      // The picture must not be shown in the WRONG place. This is the
      // real assertion, and it is what the count-based oracle could not
      // make: a displaced copy is ink, so counting called it coverage.
      expect(
        delta.ghost,
        lessThan((settledInk * 0.1).round()),
        reason: '${delta.ghost} pixels of artwork where the result has none',
      );
    });

    testWidgets('the canvas paints its OWN landing: nothing is left covering '
        'for it, and the frame is the settled frame', (tester) async {
      // N4. Everything before this closed the confirm frame by COVERING
      // it — the float, or the held resample, clipped over the tiles the
      // base could not paint yet. The measurements say that cover works:
      // with a float whose tiles have decoded, the confirm frame is
      // already pixel-identical to the settled one, hole 0 and ghost 0.
      //
      // So this test is not about a missing pixel. It is about WHICH
      // object is drawing: composing the float's picture onto the base's
      // new tiles means the canvas answers for itself and the cover can
      // go, and a cover that is never mounted cannot mis-clip, cannot
      // composite a partial-alpha edge twice, and cannot outlive its
      // release.
      //
      // ⚠️ The float must have DECODED before the confirm — `runAsync`,
      // because `decodeImageFromPixels` never completes under `pump`.
      // Without it the float has no picture to give and this measures a
      // state production is never in (the user has been looking at that
      // float for the whole drag).
      final env = await pumpSelectionPanel(
        tester,
        tool: CanvasTool.move,
        sourceDabs: widePicture,
      );
      await dragOnLayer(tester, const Offset(300, 200), const Offset(340, 225));
      await settle(tester);
      final committedBefore = currentSurface(env.coordinator);
      expect(
        tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((paint) => paint.painter)
            .whereType<BitmapSurfacePainter>()
            .any((painter) => !identical(painter.surface, committedBefore)),
        isTrue,
        reason: 'no float during the session — bad premise',
      );

      env.commands.confirmPendingMove();
      await tester.pump();
      final atConfirm = await screenBytes(tester);
      final committed = currentSurface(env.coordinator);
      final covers = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<BitmapSurfacePainter>()
          .where((painter) => !identical(painter.surface, committed))
          .length;

      await settle(tester);
      final settled = await screenBytes(tester);
      var differing = 0;
      var worst = 0;
      for (var i = 0; i < settled.length; i += 4) {
        var pixelWorst = 0;
        for (var c = 0; c < 4; c += 1) {
          final delta = (atConfirm[i + c] - settled[i + c]).abs();
          if (delta > pixelWorst) pixelWorst = delta;
        }
        if (pixelWorst > 0) differing += 1;
        if (pixelWorst > worst) worst = pixelWorst;
      }

      expect(
        covers,
        0,
        reason:
            'the landing is still being covered for by $covers surface(s) '
            '— the base did not take its own picture',
      );
      // And taking the cover away cost nothing: composing is only allowed
      // to move fidelity by the rounding step the parity sweep measured,
      // and here the landing sits on erased tiles, so there is not even
      // that.
      expect(
        differing,
        0,
        reason:
            'the confirm frame differs from the settled frame in '
            '$differing pixels (worst channel $worst)',
      );
    });

    testWidgets('what the composition costs the EYE: at most one channel '
        'step, against the screen and against the truth', (tester) async {
      // N4 ②, and it is the judgement that closes the Skia side.
      //
      // The parity suite measures composed-vs-COMMIT and answers "may we
      // adopt this?" (no — up to two channel steps, so it stays
      // provisional). That is not the question a USER has. Theirs is: on
      // the frame my edit lands, does the picture change under me? So
      // this measures the composed stand-in against BOTH neighbours — the
      // frame before it and the settled truth after — through the panel's
      // own capture, which is what the eye gets.
      //
      // ⚠️ THE FIXTURE IS THE WHOLE TEST. Every other confirm test here
      // lifts the WHOLE picture with hard opaque dabs, and both halves of
      // that are exact by construction: composing over an emptied tile is
      // exact, and srcOver of an opaque source is exact. So none of them
      // has ever exercised a blend. This one lifts a SUB-REGION of a
      // soft, semi-transparent picture and drops it back on top of the
      // rest, which is the only shape where the two rounding orders can
      // disagree at all — and the anti-vacuity assertion below fails if a
      // future change makes it stop blending.
      final env = await pumpSelectionPanel(tester, sourceDabs: blendedPicture);
      await dragOnLayer(tester, const Offset(120, 120), const Offset(430, 380));
      await env.setTool(CanvasTool.move);
      await dragOnLayer(tester, const Offset(250, 220), const Offset(286, 249));
      await settle(tester);

      final live = await screenBytes(tester);
      env.commands.confirmPendingMove();
      await tester.pump();
      final atConfirm = await screenBytes(tester);
      await settle(tester);
      final settled = await screenBytes(tester);

      // ⚠️ The ants and the confirm button vanish AT the confirm, so a
      // whole-panel diff of live-vs-confirm is dominated by chrome —
      // measured 2105 pixels at a full 255. A pixel counts as chrome when
      // live disagrees with SETTLED by more than a rounding step, since
      // the settled frame has neither chrome nor stand-ins.
      var chrome = 0;
      var vsScreen = 0;
      var vsScreenWorst = 0;
      var vsTruth = 0;
      var vsTruthWorst = 0;
      for (var i = 0; i < settled.length; i += 4) {
        var liveVsSettled = 0;
        var liveVsConfirm = 0;
        var confirmVsSettled = 0;
        for (var c = 0; c < 4; c += 1) {
          final a = (live[i + c] - settled[i + c]).abs();
          final b = (live[i + c] - atConfirm[i + c]).abs();
          final d = (atConfirm[i + c] - settled[i + c]).abs();
          if (a > liveVsSettled) liveVsSettled = a;
          if (b > liveVsConfirm) liveVsConfirm = b;
          if (d > confirmVsSettled) confirmVsSettled = d;
        }
        if (confirmVsSettled > 0) {
          vsTruth += 1;
          if (confirmVsSettled > vsTruthWorst) {
            vsTruthWorst = confirmVsSettled;
          }
        }
        if (liveVsSettled > 1) {
          chrome += 1;
          continue;
        }
        if (liveVsConfirm > 0) {
          vsScreen += 1;
          if (liveVsConfirm > vsScreenWorst) vsScreenWorst = liveVsConfirm;
        }
      }

      // ANTI-VACUITY. Zero differing pixels would mean the landing never
      // blended and the bounds below are statements about nothing.
      expect(
        vsTruth,
        greaterThan(500),
        reason:
            'only $vsTruth pixels differ from the settled frame — the '
            'landing is not blending, so this measures nothing',
      );
      expect(
        chrome,
        greaterThan(0),
        reason: 'no chrome was masked — the session was not pending',
      );

      // THE JUDGEMENT. One step is invisible and it is on the FIDELITY
      // axis, which this program's invariant permits trading; coverage is
      // the axis it never trades, and the coverage assertions live in the
      // neighbouring tests. Measured: 2674 pixels against the screen,
      // 3509 against the truth, worst channel 1 on both.
      expect(
        vsScreenWorst,
        lessThanOrEqualTo(1),
        reason:
            'the confirm frame moved the picture under the user by '
            '$vsScreenWorst channel steps on $vsScreen pixels',
      );
      expect(
        vsTruthWorst,
        lessThanOrEqualTo(1),
        reason:
            'the stand-in is $vsTruthWorst channel steps from the truth on '
            '$vsTruth pixels — the sweep allows two, but the screen has '
            'never shown more than one and a regression should say so',
      );
    });

    testWidgets('a resample the confirm overtook is NOT held — an absent '
        'picture beats a wrong one', (tester) async {
      // `_resampledFloatImage` is deliberately the last COMPLETED
      // resample, while the confirm recomputes synchronously when the warp
      // changed since. Holding it unconditionally would paint the earlier
      // transform state over the landing for the whole hold. The keep is
      // gated on the image being `identical`ly the dab that landed.
      final env = await pumpSelectionPanel(tester);
      await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
      await env.setTool(CanvasTool.move);
      env.commands.beginTransform();
      await tester.pump();

      env.commands.setTransformValues(
        tx: 0,
        ty: 0,
        rotationDegrees: 0,
        scale: 1.4,
      );
      await settle(tester);
      expect(
        find.byKey(const ValueKey<String>('transform-resample-preview')),
        findsOneWidget,
        reason: 'the 1.4 preview decoded — bad premise otherwise',
      );

      // Change the warp and confirm WITHOUT letting the new decode land:
      // the image on hand is now the 1.4 picture, the landing is 2.4.
      env.commands.setTransformValues(
        tx: 0,
        ty: 0,
        rotationDegrees: 0,
        scale: 2.4,
      );
      await tester.pump();
      env.commands.commitTransform();
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('transform-resample-preview')),
        findsNothing,
        reason: 'a stale resample was held over the landing',
      );
      // And nothing is built to stand in its place. `_floatContentReplaced`
      // has just emptied the float's stale scope, so a surface built here
      // would have no image and nothing to borrow for any of its tiles —
      // measured 20 tiles, 0 decoded, 0 borrowable, contributing zero
      // pixels — after re-materialising the whole warped stamp to make it.
      final committed = env.coordinator.currentSurfaceOf(
        env.coordinator.activeFrameKey,
      );
      final floats = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<BitmapSurfacePainter>()
          .where((painter) => !identical(painter.surface, committed));
      expect(
        floats,
        isEmpty,
        reason:
            'a float was built into an emptied scope: it cannot paint, and '
            'making it costs a full re-materialisation of the stamp',
      );
    });

    testWidgets('Ctrl+Z over an open transform box folds it in rather than '
        'wedging the box', (tester) async {
      // The third caller with the button's old wiring, and the one that
      // hurt most: `home_page.dart` binds `confirmPendingMove` to
      // `HistoryManager.onBeforeUndoRedo`, which every undo runs
      // unconditionally. Bare, it landed the UNWARPED lift as a fresh
      // entry that the same Ctrl+Z then popped — the keypress consumed
      // itself — and left the box open with `_transform` still set and no
      // float, which wedges the next Ctrl+T against its own guard. Escape
      // was the only way out.
      final env = await pumpSelectionPanel(tester);
      env.history.onBeforeUndoRedo = env.commands.confirmPendingMove;
      await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
      env.commands.beginTransform();
      await tester.pump();
      await dragOnLayer(tester, const Offset(70, 70), const Offset(95, 95));
      await tester.pump();

      env.history.undo();
      await tester.pump();

      expect(
        env.commands.transformActive,
        isFalse,
        reason: 'the box was left open with no float — Ctrl+T is now wedged',
      );
      // And the session can be reopened, which is what "wedged" cost.
      env.commands.beginTransform();
      await tester.pump();
      expect(env.commands.transformActive, isTrue);
    });

    testWidgets('a corner drag scales anchored on the opposite corner: the '
        'pixels RESAMPLE into the scaled footprint', (tester) async {
      final env = await pumpSelectionPanel(tester);
      // Selection box (20,20)..(70,70): pivot (45,45), BR handle at (70,70).
      await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
      env.commands.beginTransform();
      await tester.pump();

      // Drag BR to (95,95): 1.5× about the anchored TL corner (20,20).
      await dragOnLayer(tester, const Offset(70, 70), const Offset(95, 95));
      env.commands.commitTransform();
      await tester.pump();

      // Dab centers map through q = 20 + 1.5·(p − 20):
      // (30,30)→(35,35), (45,45)→(57.5,57.5), (60,60)→(80,80).
      expect(inkAt(env.coordinator, 35, 35), isNonZero);
      expect(inkAt(env.coordinator, 57, 57), isNonZero);
      expect(inkAt(env.coordinator, 80, 80), isNonZero);
    });

    testWidgets('Alt scales about the center; Escape reverts a fresh '
        'Ctrl+T lift byte-exactly', (tester) async {
      final env = await pumpSelectionPanel(tester);
      await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
      env.commands.beginTransform();
      await tester.pump();

      // Alt+drag BR (70,70)→(95,95): 2× about the center (45,45).
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await dragOnLayer(tester, const Offset(70, 70), const Offset(95, 95));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      env.commands.commitTransform();
      await tester.pump();

      // q = 45 + 2·(p − 45): (30,30)→(15,15), (45,45) fixed, (60,60)→(75,75).
      expect(inkAt(env.coordinator, 15, 15), isNonZero);
      expect(inkAt(env.coordinator, 45, 45), isNonZero);
      expect(inkAt(env.coordinator, 75, 75), isNonZero);
      final afterFirst = currentSurface(env.coordinator);

      // A second session cancelled with Escape leaves no trace: the
      // fresh lift it opened reverts whole.
      env.commands.beginTransform();
      await tester.pump();
      await dragOnLayer(tester, const Offset(46, 46), const Offset(60, 60));
      env.commands.cancelTransform();
      await tester.pump();
      expect(env.commands.transformActive, isFalse);
      expect(
        identical(currentSurface(env.coordinator), afterFirst),
        isTrue,
        reason: 'Escape restores the pre-Ctrl+T surface by reference',
      );
    });

    testWidgets('R17-U 핸들 상시: with the MOVE tool a corner drag scales '
        'WITHOUT Ctrl+T — the grab itself opens the session', (tester) async {
      final env = await pumpSelectionPanel(tester);
      await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
      await env.setTool(CanvasTool.move);
      expect(env.commands.transformActive, isFalse);

      // Grab the BR corner handle of the ALWAYS-ON box and drag to
      // (95,95): 1.5× about the anchored TL corner.
      await dragOnLayer(tester, const Offset(70, 70), const Offset(95, 95));
      expect(
        env.commands.transformActive,
        isTrue,
        reason: 'the handle grab promoted the implicit box into a session',
      );

      env.commands.commitTransform();
      await tester.pump();
      expect(inkAt(env.coordinator, 35, 35), isNonZero);
      expect(inkAt(env.coordinator, 80, 80), isNonZero);
    });

    testWidgets('일반변형 follows the hand off the diagonal: the uniform '
        'scale is the PROJECTION, not the larger axis', (tester) async {
      // The test above drags exactly along the diagonal, where every rule
      // for picking one scale from two agrees. This one does not, which is
      // the only way to see which rule is running.
      //
      // Box (20,20)-(70,70), anchored at TL. Grabbing BR and pulling it
      // sideways to (95,70) asks for 1.5× on x and 1.0× on y:
      //
      //   max(|sx|,|sy|)  → 1.5×, so the stroke's far end (60,60) lands
      //                     at 20 + 40·1.5 = 80 — past the pointer on the
      //                     axis the hand never moved along.
      //   projection      → (75·50 + 50·50)/(50²+50²) = 1.25×, so it
      //                     lands at 20 + 40·1.25 = 70.
      //
      // Following the hand is also 1.44× fewer pixels to resample here,
      // which is the whole reason the rule changed.
      final env = await pumpSelectionPanel(tester);
      await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
      await env.setTool(CanvasTool.move);

      await dragOnLayer(tester, const Offset(70, 70), const Offset(95, 70));
      env.commands.commitTransform();
      await tester.pump();

      expect(
        inkAt(env.coordinator, 70, 70),
        isNonZero,
        reason: 'the far end landed at the projected 1.25×',
      );
      expect(
        inkAt(env.coordinator, 80, 80),
        0,
        reason:
            'and NOT at the 1.5× the larger-axis rule would have given — '
            'that is the box outrunning the hand',
      );
    });

    testWidgets('numeric transform input (tool settings) applies through '
        'the selection channel', (tester) async {
      final env = await pumpSelectionPanel(tester);
      await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
      await env.setTool(CanvasTool.move);

      env.commands.setTransformValues(
        tx: 10,
        ty: 5,
        rotationDegrees: 0,
        scale: 1,
      );
      await tester.pump();
      expect(env.commands.transformActive, isTrue);
      expect(env.commands.transformValues?.tx, 10);

      env.commands.commitTransform();
      await tester.pump();
      expect(inkAt(env.coordinator, 40, 35), isNonZero);
      expect(inkAt(env.coordinator, 28, 28), 0);
    });

    testWidgets('the rotate knob turns the selection about its center: '
        'only the shape\'s PIXELS rotate, unlifted content stays', (
      tester,
    ) async {
      final env = await pumpSelectionPanel(tester);
      // Lower box (20,40)..(70,90): dabs (45,45) and (60,60) lift; the
      // (30,30) dab's pixels sit above the region and stay in the base.
      await dragOnLayer(tester, const Offset(20, 40), const Offset(70, 90));
      expect(env.commands.hasSelection, isTrue);
      env.commands.beginTransform();
      await tester.pump();

      // Knob sits 28px above the top edge midpoint (45,40) → (45,12).
      // Sweep to angle 0° about the center (45,65): +90° rotation.
      await dragOnLayer(tester, const Offset(45, 12), const Offset(90, 65));
      env.commands.commitTransform();
      await tester.pump();

      // R90 about (45,65): (45,45)→(65,65), (60,60)→(50,80).
      expect(inkAt(env.coordinator, 65, 65), isNonZero);
      expect(inkAt(env.coordinator, 50, 80), isNonZero);
      expect(
        inkAt(env.coordinator, 30, 30),
        isNonZero,
        reason: 'the unlifted pixels never move',
      );
      expect(inkAt(env.coordinator, 45, 45), 0, reason: 'origin rotated away');
    });
  });

  testWidgets('the lasso tool selects with a freehand region', (tester) async {
    final env = await pumpSelectionPanel(
      tester,
      shapeKind: CanvasShapeKind.lasso,
    );

    // A rough triangle around the stroke.
    final origin = tester.getTopLeft(find.byKey(layerKey));
    final gesture = await tester.startGesture(origin + const Offset(10, 10));
    await tester.pump();
    for (final point in const [
      Offset(90, 10),
      Offset(90, 90),
      Offset(10, 90),
    ]) {
      await gesture.moveTo(origin + point);
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    expect(env.commands.hasSelection, isTrue);
    // The nudge lifts the lasso region's pixels into a pending session;
    // the confirm lands them moved (+2,0) — the raster is the record.
    env.commands.nudge(2, 0);
    await tester.pump();
    env.commands.confirmPendingMove();
    await tester.pump();
    expect(inkAt(env.coordinator, 32, 30), isNonZero);
    expect(inkAt(env.coordinator, 28, 30), 0);
  });

  testWidgets('the ellipse shape drags out a round region, not a box', (
    tester,
  ) async {
    // The wiring, not the geometry: the shape kind has to reach the drag
    // surface and pick the other factory. A box drag that came back square
    // would pass every pure-function test next door.
    final env = await pumpSelectionPanel(
      tester,
      shapeKind: CanvasShapeKind.ellipse,
    );
    await dragOnLayer(tester, const Offset(10, 10), const Offset(90, 90));

    final region = env.commands.region!;
    expect(
      region.containsPoint(CanvasPoint(x: 50, y: 50)),
      isTrue,
      reason: 'the middle is inside',
    );
    expect(
      region.containsPoint(CanvasPoint(x: 13, y: 13)),
      isFalse,
      reason: 'the box corner is not — that is what makes it an ellipse',
    );
  });

  testWidgets('the shape fill paints the outline and leaves the selection '
      'alone', (tester) async {
    // The verb, end to end. 유저 확정: 잘라내기와 같은 법 — filling a shape
    // you drew is not choosing it, so no region is created and Ctrl+Z
    // undoes the FILL rather than a marquee nobody asked for.
    final env = await pumpSelectionPanel(tester, tool: CanvasTool.fillShape);
    expect(inkAt(env.coordinator, 70, 70), 0, reason: 'blank to begin with');

    await dragOnLayer(tester, const Offset(60, 60), const Offset(90, 90));
    await tester.pump();

    expect(inkAt(env.coordinator, 70, 70), isNonZero, reason: 'it painted');
    expect(
      env.commands.region,
      isNull,
      reason: 'and made no selection doing it',
    );
  });

  testWidgets('a shape fill on the erase blend REMOVES ink', (tester) async {
    // 유저 확정 ③: erase is in the blend list, which makes the shapes into
    // an eraser. Asserted on the raster, not on a flag: erase is carried
    // per DAB and not by the blend mode at commit, so a fill handed only
    // `blendMode: erase` takes the plain path and paints the region. That
    // is exactly what this file caught.
    final env = await pumpSelectionPanel(
      tester,
      tool: CanvasTool.fillShape,
      blendMode: BrushBlendMode.erase,
    );
    expect(inkAt(env.coordinator, 45, 45), isNonZero, reason: 'ink to erase');

    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    await tester.pump();

    expect(inkAt(env.coordinator, 45, 45), 0, reason: 'the ink is gone');
  });

  group('polygon', () {
    testWidgets('taps place vertices and the first one closes the outline', (
      tester,
    ) async {
      final env = await pumpSelectionPanel(
        tester,
        shapeKind: CanvasShapeKind.polygon,
      );
      // Nothing is selected while the outline is still open — an unclosed
      // shape has not chosen anything yet.
      await tapOnLayer(tester, const Offset(20, 20));
      await tapOnLayer(tester, const Offset(80, 20));
      await tapOnLayer(tester, const Offset(80, 80));
      expect(env.commands.polygonPoints, hasLength(3));
      expect(env.commands.region, isNull);

      // Tapping the first vertex again closes it.
      await tapOnLayer(tester, const Offset(20, 20));
      expect(env.commands.hasOpenPolygon, isFalse);
      final region = env.commands.region;
      expect(region, isNotNull);
      expect(region!.containsPoint(CanvasPoint(x: 60, y: 40)), isTrue);
      expect(region.containsPoint(CanvasPoint(x: 30, y: 70)), isFalse);
    });

    testWidgets('the confirm closes it too — a tablet has no Enter key', (
      tester,
    ) async {
      final env = await pumpSelectionPanel(
        tester,
        shapeKind: CanvasShapeKind.polygon,
      );
      await tapOnLayer(tester, const Offset(20, 20));
      await tapOnLayer(tester, const Offset(80, 20));
      await tapOnLayer(tester, const Offset(80, 80));

      expect(env.commands.closePolygon(), isTrue);
      await tester.pump();
      expect(env.commands.hasOpenPolygon, isFalse);
      expect(env.commands.region, isNotNull);
    });

    testWidgets('an undone vertex leaves the rest of the outline standing', (
      tester,
    ) async {
      final env = await pumpSelectionPanel(
        tester,
        shapeKind: CanvasShapeKind.polygon,
      );
      await tapOnLayer(tester, const Offset(20, 20));
      await tapOnLayer(tester, const Offset(80, 20));
      await tapOnLayer(tester, const Offset(80, 80));

      expect(env.commands.undoPolygonPoint(), isTrue);
      await tester.pump();
      expect(env.commands.polygonPoints, hasLength(2));
      expect(
        env.commands.region,
        isNull,
        reason: 'taking a vertex back is not a selection change',
      );
    });

    testWidgets('changing tool drops the trace; the region it never made '
        'is not affected', (tester) async {
      final env = await pumpSelectionPanel(
        tester,
        shapeKind: CanvasShapeKind.polygon,
      );
      await tapOnLayer(tester, const Offset(20, 20));
      await tapOnLayer(tester, const Offset(80, 20));
      expect(env.commands.hasOpenPolygon, isTrue);

      await env.setTool(CanvasTool.brush);
      expect(env.commands.hasOpenPolygon, isFalse);
      expect(env.commands.region, isNull);
    });

    testWidgets('the close ring appears only once closing is on offer', (
      tester,
    ) async {
      // The ring is a promise about what a tap there would do, so it must
      // not be up while such a tap would do nothing.
      final env = await pumpSelectionPanel(
        tester,
        shapeKind: CanvasShapeKind.polygon,
      );
      CanvasPoint? ringAt() {
        for (final paint in tester.widgetList<CustomPaint>(
          find.descendant(
            of: find.byKey(layerKey),
            matching: find.byType(CustomPaint),
          ),
        )) {
          final painter = paint.painter;
          if (painter is SelectionAntsPainter) {
            return painter.closeTarget;
          }
        }
        return null;
      }

      await tapOnLayer(tester, const Offset(20, 20));
      await tapOnLayer(tester, const Offset(80, 20));
      expect(ringAt(), isNull, reason: 'two vertices enclose nothing');

      await tapOnLayer(tester, const Offset(80, 80));
      expect(ringAt(), CanvasPoint(x: 20, y: 20));
      expect(env.commands.canClosePolygon, isTrue);
    });
  });

  testWidgets('R26 #15: NO frame under the playhead still selects — the '
      'region is view state; only pixel ops need a cel', (tester) async {
    final commands = CanvasSelectionCommands();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: null,
            availableFrameKeys: const [],
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            historyManager: HistoryManager(),
            brushToolState: BrushToolState.defaults.copyWith(
              tool: CanvasTool.select,
            ),
            selectionCommands: commands,
            // The production no-frame configuration: the blank-canvas
            // placeholder carries the viewport.
            contentOverride: (context, viewport) => const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(layerKey),
      findsOneWidget,
      reason: 'the layer used to refuse to mount without a coordinator',
    );

    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    expect(
      commands.hasSelection,
      isTrue,
      reason: '"어느 상황에서든 무조건" — the marquee works on empty ground',
    );
  });
}

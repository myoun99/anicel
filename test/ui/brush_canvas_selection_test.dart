import 'dart:ui' show ImageByteFormat, PictureRecorder;
import 'dart:ui' as ui show Image;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/device_viewport.dart';
import 'package:anicel/src/services/straight_rgba_image.dart'
    show debugRawRgbaUploader;
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
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
import 'package:anicel/src/services/canvas_selection_shape.dart';
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
import 'package:anicel/src/ui/canvas/selection_float_overlay.dart';
import 'package:anicel/src/models/app_input_settings.dart';

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
      BrushEditCacheInvalidationSink cacheSink,
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
    // F-116: the production wiring hands these edges to the session's
    // counting EDIT HOLD. A case that watches the hold passes a recorder.
    ValueChanged<bool>? onSelectionInteractionChanged,
    // F-116-b: the cel ladder a confirm lands on. Null = the standing cel,
    // which is what the session answers with no range live.
    List<BrushFrameKey> Function()? transformTargetKeys,
  }) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
      canvasSize: canvasSize,
    );
    final history = HistoryManager();
    final commands = CanvasSelectionCommands();
    // 🚨★★★**ONE SINK, HELD.** It was built inline in `pumpWith`, so every
    // pump handed the panel a NEW one and nothing outside could tell the
    // panel a cel had changed.
    //
    // 🧪That is not a tidiness point — it made a whole class of case
    // unmeasurable, and cost F-164 a wrong conclusion: committing a stroke
    // through the coordinator moved the panel's drawn pixels by exactly
    // zero, which reads as 「the picture is gone」 and is actually 「this
    // fixture never repaints a commit」. A control caught it; the sink is
    // what fixes it.
    final cacheSink = BrushEditCacheInvalidationSink();
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

    // ⚠️Default to an EXPLICIT render 1.0. These cases map screen pixels
    // to canvas pixels one-for-one, and an uncontrolled panel opens at the
    // identity (one artwork px per DEVICE px), which on the 3x test view is
    // a render zoom of 1/3. Saying it here keeps the geometry the
    // assertions were written against, and states the assumption.
    //
    // ⛔Through `seedFromRender`, because the panel's viewport channels are
    // in DEVICE pixels — a bare `CanvasViewport()` here means 100%, and
    // every one-screen-pixel-is-one-canvas-pixel claim below would be off
    // by the harness ratio.
    var liveViewport = viewport ?? seedFromRender(tester, CanvasViewport());
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
                cacheInvalidationSink: cacheSink,
                transformTargetKeys: transformTargetKeys,
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
                onSelectionInteractionChanged:
                    onSelectionInteractionChanged,
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
      cacheSink: cacheSink,
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

  /// The FLOAT's surface painters — every one whose surface is not the
  /// committed cel.
  ///
  /// TS1 moved the float out of the widget tree's own painters: it is a
  /// canvas-space DESCRIPTION now, published so the composite can draw it at
  /// the active layer's depth (that is what makes the rows above occlude it).
  /// Hosts with no composite — this test's panel among them — draw the same
  /// description through [SelectionFloatPainter], so the way to the float is
  /// through that painter's `float`.
  List<BitmapSurfacePainter> floatPainters(
    WidgetTester tester,
    BitmapSurface committed,
  ) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((paint) => paint.painter)
      .whereType<SelectionFloatPainter>()
      .map((painter) => painter.float.surface)
      .whereType<BitmapSurfacePainter>()
      .where((painter) => !identical(painter.surface, committed))
      .toList();

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

  /// The ants painter as MOUNTED — so a fix that only reaches the model
  /// cannot pass.
  SelectionAntsPainter? antsOnScreen(WidgetTester tester) {
    final paints = tester.widgetList<CustomPaint>(
      find.descendant(
        of: find.byKey(layerKey),
        matching: find.byType(CustomPaint),
      ),
    );
    for (final paint in paints) {
      final painter = paint.painter;
      if (painter is SelectionAntsPainter) {
        return painter;
      }
    }
    return null;
  }

  SelectionTransformChrome? chromeOnScreen(WidgetTester tester) =>
      antsOnScreen(tester)?.transformChrome;

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

  testWidgets('🚨a REFUSED resample still opens the gate, so the next '
      'transform previews', (tester) async {
    // 🚨★★★`_resampleInFlight` is the throughput gate — one resample at a
    // time, so a drag cannot queue one full-canvas transform per pointer
    // event. It was set before `ui.decodeImageFromPixels` and cleared only
    // inside its callback, and that callback is never invoked on a refusal
    // (read in the SDK source). One refused upload therefore left the gate
    // closed for the life of the widget: the handles and the marching ants
    // kept running at 60 fps while the transformed pixels stopped, for good.
    //
    // ⛔The fix is NOT to fold the gate into `_resampleImageRequest`. Those
    // answer two different questions — which ask is current, versus whether
    // an upload is outstanding — and `_discardFloatResample` invalidates the
    // ask while deliberately leaving the gate CLOSED, because a discarded
    // upload is still holding a whole-picture scratch and still occupying
    // the engine. One field for both would start a second full-canvas upload
    // every time a drag crossed back through identity.
    //
    // 🚨The refusal comes through the seam because the engine under
    // `flutter test` never refuses on its own — the harness is
    // `flutter_tester`, Skia, which
    // `the_door_makes_the_same_picture_on_every_engine_test` pins by
    // asserting `pictureOfUploads` is false there. (This used to say
    // "because Windows runs Skia in every build"; that stopped being true
    // when 3.47 made Impeller the desktop default, 2026-09-16, and the
    // harness — not the platform — was always what this seam is for.)
    // See [debugRawRgbaUploader].
    // ⚠️THE SEAM IS GLOBAL, so the refusal is aimed: only the float's own
    // stamp, identified by not being a square power-of-two upload. (Until
    // 2026-09-17 this widget's canvas TILES went through the seam too, and
    // refusing everything wedged the fixture itself — measured: the test
    // ran to its ten-minute timeout. Tiles picture themselves through the
    // door now; the aim stays, because anything else square that comes
    // through here is still not the float.)
    final resampleSizes = <String>[];
    var resamples = 0;
    var refuseResample = false;
    ui.Image aSmallImage() {
      final recorder = PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 4, 4),
        Paint()..color = const Color(0xFF00FF00),
      );
      return recorder.endRecording().toImageSync(4, 4);
    }

    debugRawRgbaUploader =
        (
          rgba, {
          required int width,
          required int height,
          int? targetWidth,
          int? targetHeight,
        }) {
          final isTile = width == height && (width & (width - 1)) == 0;
          if (isTile) {
            return Future<ui.Image>.value(aSmallImage());
          }
          resamples += 1;
          resampleSizes.add('${width}x$height');
          if (refuseResample) {
            return Future<ui.Image>.error(StateError('the engine refused this'));
          }
          return Future<ui.Image>.value(aSmallImage());
        };
    addTearDown(() => debugRawRgbaUploader = null);

    // ⛔AND THE REFUSAL IS DELIBERATELY SILENT HERE, unlike the tile cache
    // and the stroke overlay. This runs once per pointer move of a drag, so
    // a report per refused resample would be a flood rather than a signal —
    // and the ask retires itself: the next move is a different transform,
    // which is why this site needs no refusal ledger either.
    final env = await pumpSelectionPanel(tester);
    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    await env.setTool(CanvasTool.move);
    env.commands.beginTransform();
    await tester.pump();

    // A ROTATION: a pure translation short-circuits and never reaches the
    // resampler at all, which is what the preview-parity test above says.
    refuseResample = true;
    env.commands.setTransformValues(tx: 0, ty: 0, rotationDegrees: 24, scale: 1);
    await tester.pump();
    await tester.pump();
    final afterRefusal = resamples;

    // A second, DIFFERENT transform. With the gate stuck closed this asks
    // for nothing at all — the bug, seen from outside the widget.
    refuseResample = false;
    env.commands.setTransformValues(tx: 0, ty: 0, rotationDegrees: 31, scale: 1);
    await tester.pump();
    await tester.pump();


    expect(
      afterRefusal,
      greaterThan(0),
      reason: 'instrument: the rotation reached the resampler — at 0 the '
          'assertion below would be measuring a transform that never ran '
          '(sizes seen: $resampleSizes)',
    );
    expect(
      resamples,
      greaterThan(afterRefusal),
      reason: 'the gate reopened on the refused road, so the preview keeps '
          'following the drag (sizes seen: $resampleSizes)',
    );
  });

  // ↩️「P3a: an arrow-key nudge with the box open moves the PICTURE, not just
  // the outline」 stood here. It pinned the nudge's own `_preview.schedule()`
  // — a mutation of the open warp that forgot to resample moved the ants
  // while the artwork stayed put. The nudge is gone with its schedule call
  // (F-86, 유저 2026-09-12: 「기능부터 잔존코드 싹 삭제」); the numbers and the
  // handles that still move an open box are pinned by the resample tests
  // above.

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

    // 🚨★★★**THE CEL KEEPS ITS INK WHILE THE BOX IS OPEN** (2026-09-17).
    // This read the opposite until then — 「pending: the base holds only the
    // erase — origin is blank」 — because the lift committed its erase at
    // once. A move session writes nothing until it lands now, so the
    // document still holds the original and the hole lives only in what the
    // panel DRAWS. The screen half is pinned by 「전/중/후 같은 그림」 below.
    expect(
      inkAt(env.coordinator, 30, 30),
      isNonZero,
      reason: 'pending: nothing is written yet, so the cel is untouched',
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

  /// 🚨★★★**F-164 — 유저 2026-09-18 실기**: 「변형중에 다른프레임가면 변형
  /// 실루엣 초록색되고 **돌아가면 그림사라져있는데**」.
  ///
  /// A move session lives in TWO places: the layer holds the float, the
  /// panel holds the HOLE it draws in that cel's place
  /// (`CanvasPanelLift`). Walking the sheet drops the float (유저 확정
  /// 2026-09-17: 「프레임이동 … 착지안하고」) — and the host has to be told,
  /// or its session stays open for the rest of the run: its derived view
  /// stays held under the store's discipline, and the cel it was cut from
  /// keeps drawing a hole nothing can close.
  ///
  /// ⛔`inkAt` cannot see it — the cel is untouched until the confirm
  /// (`314aa6e8`). The release is the thing to measure.
  testWidgets('F-164: an OPEN transform box that walks to another frame and '
      'back still shows the picture, and still reads as changed',
      (tester) async {
    /// The panel's DARK pixels — the fixture's committed stroke paints
    /// near-black. ⛔Not [screenInkMask], whose threshold is red: that
    /// counts the marching ANTS, and measured 16 px of an 800×600 panel
    /// while saying nothing at all about the picture.
    Future<int> drawnInk() async {
      final bytes = await screenBytes(tester);
      var dark = 0;
      for (var i = 0; i + 3 < bytes.length; i += 4) {
        if (bytes[i] < 80 && bytes[i + 1] < 80 && bytes[i + 2] < 80) {
          dark += 1;
        }
      }
      return dark;
    }

    final keys = BrushCanvasFixture.createFrameKeys();
    final env = await pumpSelectionPanel(tester, tool: CanvasTool.move);
    final settled = await drawnInk();
    expect(
      settled,
      greaterThan(100),
      reason: '⛔fixture premise: the panel DRAWS the committed stroke',
    );

    // The user's state: a box OPEN and already dragged — 변형중, and red.
    env.commands.beginTransform();
    await tester.pump();
    await dragOnLayer(tester, const Offset(45, 45), const Offset(55, 45));
    expect(env.commands.transformActive, isTrue);
    expect(
      antsOnScreen(tester)?.sessionHasChanges,
      isTrue,
      reason: '⛔fixture premise: a dragged box is red (H28)',
    );

    env.coordinator.selectFrame(keys[1]);
    await env.setTool(CanvasTool.move);
    env.coordinator.selectFrame(keys.first);
    await env.setTool(CanvasTool.move);

    expect(
      await drawnInk(),
      greaterThan(settled ~/ 2),
      reason:
          '🚨유저 2026-09-18: 「돌아가면 그림사라져있는데」 — the cel this box '
          'was cut from must not still be drawn with its hole',
    );
    expect(
      antsOnScreen(tester)?.sessionHasChanges,
      isTrue,
      reason:
          '🚨유저: 「변형중이면 빨간색 유지여야하고」 — the box is still open '
          'and still holds an unconfirmed change, so it still reads red',
    );
    expect(
      env.history.undoCount,
      0,
      reason: '⛔and nothing landed on the way — 「착지안하고」',
    );
  });

  /// 🚨★★★**F-164 — 유저 2026-09-18, the whole procedure they gave**:
  ///
  /// > 「프레임1,2에 그림을 그려두고, 프레임1에서 변형으로 확대한 다음
  /// > **확정하지 않고**, 프레임2가면 **프레임1의 그림이 그대로 남아있는**
  /// > 문제. 그리고 **확정버튼도 사라지는** 문제. 그리고 **프레임2의 변형이
  /// > 시작되야하는데 시작되지도 않는** 문제. 그 상태에서 엔터버튼으로
  /// > 확정시키고 프레임1가면 **프레임1의 그림이 사라짐**. **새로 선을 그어도
  /// > 긋고나서 커밋하면 사라짐**」
  ///
  /// ⚠️**BOTH FRAMES HAVE INK, and that is the condition the first attempt at
  /// this pin was missing.** With ink on only one cel the holed surface
  /// shares every tile it did not hole, so nothing on screen changes and the
  /// leak is invisible. 🧪Measured: that version passed while the shipped app
  /// lost pictures.
  ///
  /// The last symptom is the one that matters most — it is not about the
  /// transform at all any more. A session the layer let go of without telling
  /// the HOST leaves `CanvasPanelLift`'s session open for that cel, so
  /// `holedSurfaceFor` keeps drawing it with its hole, and anything drawn
  /// there afterwards is masked away on commit.
  testWidgets('F-164: a box left open on one frame lets that cel go, and the '
      'cel it came from keeps its picture', (tester) async {
    Future<int> drawnInk() async {
      final bytes = await screenBytes(tester);
      var dark = 0;
      for (var i = 0; i + 3 < bytes.length; i += 4) {
        if (bytes[i] < 80 && bytes[i + 1] < 80 && bytes[i + 2] < 80) {
          dark += 1;
        }
      }
      return dark;
    }

    final keys = BrushCanvasFixture.createFrameKeys();
    final env = await pumpSelectionPanel(tester, tool: CanvasTool.move);

    // Frame TWO gets ink of its own, somewhere else on the canvas.
    env.coordinator.selectFrame(keys[1]);
    env.coordinator.commitSourceStroke(
      sourceDabs: [dab(120, 120), dab(140, 140)],
    );
    await env.setTool(CanvasTool.move);
    // ⚠️**BASELINE UNDER THE SAME CHROME.** This counts dark pixels over
    // the whole panel, and the box's own buttons are dark chrome — the
    // cancel button 유저 asked for on 2026-09-22 added ~950 of them, which
    // a bare baseline read as a picture arriving. So the baseline is taken
    // with a box open too, and what is left in the comparison is the
    // PICTURE, which is what the pin is about.
    env.commands.beginTransform();
    await tester.pump();
    final frameTwoSettled = await drawnInk();
    env.commands.cancelTransform();
    await tester.pump();
    env.coordinator.selectFrame(keys.first);
    await env.setTool(CanvasTool.move);
    final frameOneSettled = await drawnInk();
    expect(
      frameOneSettled,
      greaterThan(100),
      reason: '⛔fixture premise: frame one draws its own stroke',
    );
    expect(
      frameTwoSettled,
      greaterThan(100),
      reason: '⛔fixture premise: frame two draws a stroke of ITS own',
    );

    // Scale the box on frame one and DO NOT confirm.
    env.commands.beginTransform();
    await tester.pump();
    await dragOnLayer(tester, const Offset(45, 45), const Offset(60, 60));
    expect(env.commands.transformActive, isTrue, reason: 'the box is open');

    env.coordinator.selectFrame(keys[1]);
    await env.setTool(CanvasTool.move);

    expect(
      await drawnInk(),
      closeTo(frameTwoSettled, frameTwoSettled * 0.2),
      reason:
          '①유저: 「프레임2가면 프레임1의 그림이 그대로 남아있는 문제」 — the '
          'float belongs to the cel it was cut from and may not follow',
    );
    expect(
      env.commands.transformActive,
      isTrue,
      reason:
          '③유저: 「프레임2의 변형이 시작되야하는데 시작되지도 않는 문제」. '
          'The box and its numbers survive a frame walk on purpose (유저 확정 '
          '2026-09-17) and apply to whatever cel they then stand on',
    );
    // 🚨★★★**THE HOST LET GO TOO** — the half that costs a picture. A
    // session the layer drops without telling the host stays open there,
    // and the cel it was cut from goes on being drawn through its hole
    // (유저: 「돌아가면 그림사라져있는데 … 새로 선을 그어도 긋고나서 커밋하면
    // 사라짐」).
    //
    // ⛔It counts VIEWS, not bytes. An open session is worth 0 bytes — its
    // holed surface shares every tile it did not hole — which is how an
    // earlier attempt at this pin measured nothing and passed.
    //
    // 🚨★★★**EXACTLY ONE, AND THE TWO WRONG ANSWERS ARE DIFFERENT BUGS.**
    // ↩️This asked for ZERO until 2026-09-19, when the box still arrived
    // EMPTY and the count was of nothing at all. Now the arrival starts
    // the transform here, so:
    // · 2 = the session the layer let go of is still open on the cel we
    //   left, which is the leak this pin was built for;
    // · 0 = the box arrived and lifted nothing, which is 유저's ③
    //   「프레임2의 변형이 시작되야하는데 시작되지도 않는 문제」.
    expect(
      env.coordinator.frameStore.reclaimableViewCount,
      1,
      reason:
          'the cel we LEFT was let go of, and the cel we arrived at opened '
          'one of its own — two would be the leak, zero would be the box '
          'arriving empty',
    );
    expect(
      find.byKey(const ValueKey<String>('selection-move-confirm')),
      findsOneWidget,
      reason: '②유저: 「확정버튼도 사라지는 문제」',
    );

    // Enter, then back to frame one.
    env.commands.commitTransform();
    await tester.pump();
    env.coordinator.selectFrame(keys.first);
    await env.setTool(CanvasTool.move);

    expect(
      await drawnInk(),
      greaterThan(frameOneSettled ~/ 2),
      reason: '④유저: 「프레임1가면 프레임1의 그림이 사라짐」',
    );

    // ⛔**⑤ IS PINNED BY ITS CAUSE, NOT BY ITS PICTURE — and that is a
    // measurement, not a shrug.** 유저's last symptom is 「새로 선을 그어도
    // 긋고나서 커밋하면 사라짐」: a cel still drawn through a stale hole
    // swallows whatever is drawn on it next. The hole exists only while the
    // HOST's session is open, and the assertion above says it is not — which
    // is the same fact one step earlier, and the step a mutant can reach.
    //
    // 🧪Why not the picture too, with a CONTROL rather than a guess: commit
    // a stroke through the coordinator on a cel this panel has ALREADY
    // drawn, and its pixels do not move — with the cache sink wired, which
    // this fixture could not even reach until this round built ONE instead
    // of a fresh one per pump. (A cel it has NOT drawn yet does show, which
    // is how the two-frame setup above works at all.) Nothing pokes the
    // panel the way the brush host does, so the picture half needs a rig
    // that DRAWS — and that rig must open with this same control, because
    // an instrument that cannot move satisfies 「the ink went up」 by
    // failing, and satisfies nothing at all by passing.
  });

  /// 🚨★★★**③ 유저 2026-09-18: 「프레임2의 변형이 시작되야하는데 시작되지도
  /// 않는 문제」**, and in the same breath 「변형이 제대로 **프레임바뀌면
  /// 다음 프레임에 적용시작** 한다던가」.
  ///
  /// ⛔**AN OPEN BOX IS NOT A STARTED TRANSFORM**, and the pin above cannot
  /// tell the two apart — it counts ink, and a translation moves every
  /// pixel without changing how many there are. 유저's own next step says
  /// what「시작됐다」means: 「그 상태에서 **엔터버튼으로 확정**시키고」. So
  /// the question this asks is the one they asked: press Enter on the cel
  /// you walked to, and THAT cel must move by the numbers you carried.
  testWidgets('③stepping to another cel STARTS its transform — Enter there '
      'moves THAT cel by the numbers you carried', (tester) async {
    final keys = BrushCanvasFixture.createFrameKeys();
    final env = await pumpSelectionPanel(tester, tool: CanvasTool.move);

    // 유저: 「프레임1,2에 그림을 그려두고」 — and frame two's drawing is
    // somewhere ELSE on the canvas, the way a drawing that moves is.
    //
    // 🚨★★★**THAT IS THE POINT, AND IT IS 유저'S ANSWER TO F-164-Q1**
    // (2026-09-19): with no selection the box is 「the picture」, and which
    // picture that is depends on the cel you stand on — so the outline is
    // re-read here and frame two's own drawing is what gets lifted. Frame
    // ONE's silhouette is 28..62; (120,120) is nowhere near it, and it
    // still has to work.
    env.coordinator.selectFrame(keys[1]);
    env.coordinator.commitSourceStroke(sourceDabs: [dab(120, 120)]);
    env.coordinator.selectFrame(keys.first);
    await env.setTool(CanvasTool.move);

    // ⚠️Stated rather than dragged: a drag is in LAYER coordinates and the
    // answer is read in CANVAS ones, so a displacement written as a number
    // is the only one both ends agree about.
    env.commands.beginTransform();
    await tester.pump();
    env.commands.setTransformValues(
      tx: 15,
      ty: 15,
      rotationDegrees: 0,
      scale: 1,
    );
    await tester.pump();
    expect(env.commands.transformActive, isTrue, reason: 'the box is open');

    // Walk to frame two WITHOUT confirming — 유저: 「확정하지 않고, 프레임2
    // 가면」.
    env.coordinator.selectFrame(keys[1]);
    await env.setTool(CanvasTool.move);
    await tester.pump();
    expect(
      env.commands.transformActive,
      isTrue,
      reason: '②유저: 「확정버튼도 사라지는문제」 — the box survives the walk',
    );

    env.commands.commitTransform();
    await tester.pump();

    expect(
      inkAt(env.coordinator, 135, 135),
      isNonZero,
      reason:
          '유저: 「프레임2의 변형이 시작되야하는데」 — 배율·회전·이동의 '
          '편집값이 그대로 전달돼 이 셀 제 그림에 걸렸으니, 엔터가 그만큼 '
          '옮긴다',
    );
    expect(
      inkAt(env.coordinator, 120, 120),
      0,
      reason: '옮긴 것이지 복사한 것이 아니다',
    );
  });

  /// 🚨★★★**선택을 하던 안하던 동작이 바뀌는게 없다** (유저 2026-09-19,
  /// answering F-164-Q1: 「1번. 상자의 크기가 달라지는게 중요한게아니야.
  /// **중요한건 배율 회전 이동의 편집값이 그대로 전달되는거야**」).
  ///
  /// The two kinds of region ARE different things — one is a place the user
  /// drew, the other is 「the picture」 — so the law cannot be 「they behave
  /// identically」 in general. It is one sentence that covers both: **the
  /// numbers transfer, and the cel you arrive at moves its own pixels under
  /// whatever the region means there.**
  ///
  /// ⛔So this is not a pin on 「the code has no branch」, which a reader can
  /// check and a mutant cannot. It runs the two states through the SAME
  /// script on content BOTH regions cover, where the law says the answers
  /// must match — and they can only match if neither path is special.
  testWidgets('선택을 하던 안하던 — 걸어간 셀이 제 그림을 같은 값만큼 옮긴다', (
    tester,
  ) async {
    Future<int> confirmedOnFrameTwo({required bool withSelection}) async {
      final keys = BrushCanvasFixture.createFrameKeys();
      final env = await pumpSelectionPanel(tester, tool: CanvasTool.move);
      env.coordinator.selectFrame(keys[1]);
      env.coordinator.commitSourceStroke(sourceDabs: [dab(120, 120)]);
      env.coordinator.selectFrame(keys.first);
      await env.setTool(CanvasTool.move);
      if (withSelection) {
        // ⚠️A rect that covers BOTH cels' drawings, so the OUTLINE is not
        // what makes the two answers differ — otherwise this would be
        // measuring the fixture, not the law.
        env.commands.setRegion(
          CanvasSelectionRegion.shape(
            CanvasSelectionShape.rect(
              left: 20,
              top: 20,
              right: 160,
              bottom: 160,
            ),
          ),
        );
        await tester.pump();
      }
      env.commands.beginTransform();
      await tester.pump();
      env.commands.setTransformValues(
        tx: 15,
        ty: 15,
        rotationDegrees: 0,
        scale: 1,
      );
      await tester.pump();
      env.coordinator.selectFrame(keys[1]);
      await env.setTool(CanvasTool.move);
      await tester.pump();
      env.commands.commitTransform();
      await tester.pump();
      return inkAt(env.coordinator, 135, 135);
    }

    final drawn = await confirmedOnFrameTwo(withSelection: true);
    expect(
      drawn,
      isNonZero,
      reason: '⛔CONTROL: 선택이 있을 때는 옮겨졌다 — 두 0을 비교하지 않는다',
    );
    expect(
      await confirmedOnFrameTwo(withSelection: false),
      drawn,
      reason: '유저: 「선택을 하던 안하던 동작이 바뀌는게 없으니까」',
    );
  });

  /// 🚨★★★**THE PIVOT TRAVELS WITH THE BOX, NOT WITH THE NUMBERS.**
  ///
  /// 유저 2026-09-19: 「중요한건 **배율 회전 이동의 편집값이 그대로
  /// 전달**되는거야」. Carrying the cel-you-left's pivot would read the same
  /// in the panel and land this cel's drawing somewhere off to one side —
  /// the numbers would look transferred and not be.
  ///
  /// ⚠️**IT TAKES A SCALE TO SEE IT AT ALL.** 🧪Measured 2026-09-19: with
  /// the pins above, which all move the box by a pure translation, deleting
  /// the re-aim outright changed NOTHING — a translation is the same about
  /// any pivot. Only a scale (or a rotation) asks where the centre is.
  testWidgets('⛔×2 on the cel walked to grows ITS drawing where it stands, '
      'not about the pivot of the cel left behind', (tester) async {
    final keys = BrushCanvasFixture.createFrameKeys();
    final env = await pumpSelectionPanel(tester, tool: CanvasTool.move);

    // Frame ONE's picture is 28..62, so its centre is (45,45). Frame two's
    // single dab is at (120,120) — far enough that the two pivots send it
    // to places no tolerance could confuse.
    env.coordinator.selectFrame(keys[1]);
    env.coordinator.commitSourceStroke(sourceDabs: [dab(120, 120)]);
    env.coordinator.selectFrame(keys.first);
    await env.setTool(CanvasTool.move);

    env.commands.beginTransform();
    await tester.pump();
    env.commands.setTransformValues(
      tx: 0,
      ty: 0,
      rotationDegrees: 0,
      scale: 2,
    );
    await tester.pump();

    env.coordinator.selectFrame(keys[1]);
    await env.setTool(CanvasTool.move);
    await tester.pump();
    env.commands.commitTransform();
    await tester.pump();

    expect(
      inkAt(env.coordinator, 120, 120),
      isNonZero,
      reason:
          '×2 는 이 셀 제 그림의 중심에 걸린다 — 그림은 그 자리에서 커진다',
    );
    expect(
      inkAt(env.coordinator, 195, 195),
      0,
      reason:
          '⛔떠나온 셀의 피벗(45,45)으로 ×2 하면 (120,120)이 (195,195)로 '
          '날아간다. 숫자는 같아 보이는데 전달된 것이 아니다',
    );
  });

  /// 🚨★★★**BOTH AT ONCE — 「오른쪽으로 옮기고 2배 키운 상태」.**
  ///
  /// 🗣️유저 2026-09-20: 「즉 프레임 1을 오른쪽으로 옮기고, 2배 키운상태에서
  /// 프레임2가면 **오른쪽으로 옮긴 값이 사라지고 2배만 키워진단건가?**」.
  ///
  /// ⚠️**NEITHER PIN ABOVE COULD ANSWER THAT.** One moves the box and never
  /// scales it; the other scales it and never moves it. Each was built to
  /// kill one mutant, and between them they left the ordinary case — a user
  /// doing both — unmeasured. 유저 found the hole by reading the answer.
  ///
  /// 🔬The arithmetic it pins: the affine is 「scale about the pivot, THEN
  /// translate」 — `q = R·S·(p − pivot) + pivot + t`. Frame two's dab sits
  /// at its own box centre, so ×2 leaves it there and +50 carries it to
  /// (170,120). ⛔Both wrong answers are named: 120 would mean the move was
  /// dropped, 245 would mean frame one's pivot came along (45 + 75×2 + 50).
  testWidgets('오른쪽으로 옮기고 2배 키운 채로 걸어가면 — 옮긴 값도 배율도 '
      '둘 다 이 셀에 걸린다', (tester) async {
    final keys = BrushCanvasFixture.createFrameKeys();
    final env = await pumpSelectionPanel(tester, tool: CanvasTool.move);

    env.coordinator.selectFrame(keys[1]);
    env.coordinator.commitSourceStroke(sourceDabs: [dab(120, 120)]);
    env.coordinator.selectFrame(keys.first);
    await env.setTool(CanvasTool.move);

    env.commands.beginTransform();
    await tester.pump();
    env.commands.setTransformValues(
      tx: 50,
      ty: 0,
      rotationDegrees: 0,
      scale: 2,
    );
    await tester.pump();

    env.coordinator.selectFrame(keys[1]);
    await env.setTool(CanvasTool.move);
    await tester.pump();
    env.commands.commitTransform();
    await tester.pump();

    expect(
      inkAt(env.coordinator, 170, 120),
      isNonZero,
      reason:
          '유저: 옮긴 값은 사라지지 않는다 — 이 셀 제 그림이 제자리에서 2배가 '
          '되고, 그 다음 +50 만큼 오른쪽으로 간다',
    );
    expect(
      inkAt(env.coordinator, 120, 120),
      0,
      reason: '⛔120 에 남아 있으면 「2배만 되고 이동은 버려졌다」는 뜻이다',
    );
    expect(
      inkAt(env.coordinator, 245, 120),
      0,
      reason: '⛔245 면 떠나온 셀의 피벗이 따라온 것이다(45 + 75×2 + 50)',
    );
  });

  // TP4 (유저: 선택된 내부를 끌어야 변형툴이 움직이는데 … 변형툴 내부 사각형
  // 안이라면 언제든 작동하도록).
  /// 🚨★★★**F-116-b / F-164 — 여러 행·프레임 확정.**
  ///
  /// 🗣️유저 2026-09-17: 「몇 행에 걸쳐서 적용하던 **동시적용은 가능하게**.
  /// **적용시만 각 행에 따라 불가능하면 그냥 무시**하는방식」, and 2026-09-18:
  /// 「**여러프레임 확정가능**하게한다던가」. Rows and frames are one law —
  /// `pixelVerbCellKeys()` is that law, and it already skips what cannot
  /// take the edit.
  ///
  /// ⛔**AND THE SAME AFFINE, NOT THE SAME STAMP.** The float carries the
  /// pixels lifted from the cel it started on; stamping it onto another cel
  /// would paste the first cel's drawing there. Each cel lifts its OWN
  /// pixels through the same region and takes the same transform.
  testWidgets('a confirm over a frame RANGE moves every cel in it, each by '
      'its own pixels, as ONE undo', (tester) async {
    final keys = BrushCanvasFixture.createFrameKeys();
    final env = await pumpSelectionPanel(
      tester,
      tool: CanvasTool.move,
      // The ladder the session would hand in. ⚠️A FUNCTION, because the
      // range changes under the panel and a list would be the state as it
      // was when the panel was built.
      transformTargetKeys: () => [keys[0], keys[1]],
    );

    // Each frame gets ink of its OWN, in its own place — and each keeps a
    // witness OUTSIDE the selection. 🚨That witness is the whole point: a
    // landing derives against a BASE, and only pixels the move does not
    // touch can say which cel's base it was. Frame two's own is (70,20),
    // where frame one has nothing; frame one's is the fixture's (60,60).
    //
    // ⚠️Frame two's inside ink is OFF the box centre (25..55 centres at
    // 40,40) — at the centre a scale moves nothing, and this pin exists to
    // see the scale.
    env.coordinator.selectFrame(keys[1]);
    env.coordinator.commitSourceStroke(sourceDabs: [dab(50, 50), dab(70, 20)]);
    env.coordinator.selectFrame(keys.first);
    await env.setTool(CanvasTool.move);
    // ⛔A PARTIAL region, not the implicit whole picture: a whole-picture
    // erase clears the base before the stamp lands, so every cel would
    // come out the same however wrong the base was.
    env.commands.setRegion(
      CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: 25, top: 25, right: 55, bottom: 55),
      ),
    );
    await tester.pump();

    final entriesBefore = env.history.undoCount;
    // ⚠️The transform's own door rather than a pointer drag: a drag is in
    // LAYER coordinates and the region above is in CANVAS coordinates, so
    // a press written as a canvas point would only look like it landed
    // inside the outline. Stating the displacement says what is meant.
    env.commands.beginTransform();
    await tester.pump();
    // 🚨★★★**A MOVE AND A SCALE, TOGETHER** — 유저 2026-09-22, 실기:
    // 「이동+확대하고 둘다 동시적용 해봤는데 **한쪽 값의 확대가 사라졌어.
    // 이동은 남아있는데**」. ⛔A pin that sets one of them measures half the
    // law, and that is exactly why this one let the defect through.
    env.commands.setTransformValues(
      tx: 10,
      ty: 5,
      rotationDegrees: 0,
      scale: 2,
    );
    await tester.pump();
    env.commands.commitTransform();
    await tester.pump();

    expect(
      env.history.undoCount,
      entriesBefore + 1,
      reason: '유저: 한 번의 확정은 한 번의 언두다',
    );

    // Frame ONE moved: its (30,30) doubles about (40,40) to (20,20), then
    // +10,+5.
    expect(inkAt(env.coordinator, 30, 25), isNonZero);
    // And frame TWO took the SAME transform on its OWN ink: (50,50)
    // doubles about (40,40) to (60,60), then +10,+5.
    env.coordinator.selectFrame(keys[1]);
    expect(
      inkAt(env.coordinator, 70, 65),
      isNonZero,
      reason: '같은 아핀이 이 셀의 제 그림에 적용됐다 — 배율까지',
    );
    expect(
      inkAt(env.coordinator, 60, 55),
      0,
      reason:
          '⛔60,55 는 **이동만** 전달됐을 때 가는 자리다. 유저가 실기에서 '
          '찾은 그 결함이고, 여기가 그것을 잡는 곳이다',
    );
    expect(
      inkAt(env.coordinator, 50, 50),
      0,
      reason: '그리고 원래 자리는 비었다 — 복사가 아니라 이동이다',
    );
    // 🚨★★★THE BASE WAS THIS CEL'S. Both witnesses sit outside the
    // selection, so the move must not have touched either: frame two keeps
    // its own, and frame one's never arrives. ⛔A landing derived against
    // the standing cel passes every check above and fails exactly these
    // two — measured 2026-09-18, which is why they exist.
    expect(
      inkAt(env.coordinator, 70, 20),
      isNonZero,
      reason: '선택 밖은 그대로다 — 이 셀 자신의 그림 위에 착지했다',
    );
    expect(
      inkAt(env.coordinator, 60, 60),
      0,
      reason: '⛔프레임1의 선택 밖 그림이 여기 올 리 없다',
    );

    env.history.undo();
    await tester.pump();
    expect(
      inkAt(env.coordinator, 50, 50),
      isNonZero,
      reason: '⛔ONE undo takes BOTH cels back, or it was two entries',
    );
  });

  /// ⛔**A LADDER THAT NAMES THE STANDING CEL COSTS THE SAME.** The range a
  /// user selects normally DOES include the cel they are standing on, so
  /// the confirm must not land that one twice.
  ///
  /// 🧪The picture cannot report this — measured 2026-09-18, a duplicate
  /// landing draws the identical result, because the second erase clears
  /// the second stamp's ground and the stamp puts the same pixels back.
  /// What doubles is history: a second resample and a second pre-landing
  /// surface held for that cel. So the axis is BYTES, with the same
  /// confirm run twice and only the ladder differing.
  testWidgets('⛔the standing cel lands ONCE even when the ladder names it '
      'too — same bytes either way', (tester) async {
    final keys = BrushCanvasFixture.createFrameKeys();

    Future<int> bytesAfterConfirm(List<BrushFrameKey> ladder) async {
      final env = await pumpSelectionPanel(
        tester,
        tool: CanvasTool.move,
        transformTargetKeys: () => ladder,
      );
      env.coordinator.selectFrame(keys[1]);
      env.coordinator.commitSourceStroke(
        sourceDabs: [dab(40, 40), dab(50, 50)],
      );
      env.coordinator.selectFrame(keys.first);
      await env.setTool(CanvasTool.move);
      await dragOnLayer(tester, const Offset(45, 45), const Offset(55, 50));
      env.commands.confirmPendingMove();
      await tester.pump();
      return env.history.retainedBytes;
    }

    final without = await bytesAfterConfirm([keys[1]]);
    final with_ = await bytesAfterConfirm([keys[0], keys[1]]);

    expect(
      without,
      isNonZero,
      reason: '⛔a pin that compares two zeros measures nothing',
    );
    expect(
      with_,
      without,
      reason: '유저의 범위는 서 있는 셀을 포함한다 — 그 셀은 한 번만 착지한다',
    );
  });

  testWidgets('⛔a cel that cannot take it is skipped, and the rest still '
      'land — 유저: 「불가능하면 그냥 무시」', (tester) async {
    // The ladder is allowed to name a cel with nothing in it; the walk that
    // builds it already refuses those, and this is the belt: a target that
    // yields no lift must not take the whole confirm down with it.
    final keys = BrushCanvasFixture.createFrameKeys();
    final env = await pumpSelectionPanel(
      tester,
      tool: CanvasTool.move,
      // keys[2] is EMPTY — no stroke was ever committed there.
      transformTargetKeys: () => [keys[0], keys[2]],
    );

    final entriesBefore = env.history.undoCount;
    await dragOnLayer(tester, const Offset(45, 45), const Offset(55, 50));
    env.commands.confirmPendingMove();
    await tester.pump();

    expect(env.history.undoCount, entriesBefore + 1);
    expect(
      inkAt(env.coordinator, 40, 35),
      isNonZero,
      reason: 'the cel that COULD take it still did',
    );
  });

  testWidgets('⛔with no range the ladder is the standing cel, so nothing '
      'about a single confirm changed', (tester) async {
    // 🎯THE REASON THERE IS NO 「여러 개일 때만」 BRANCH. `pixelVerbCellKeys`
    // answers `[the cel you stand on]` when no range is live, so the
    // multi-cel path IS the single-cel path. A branch here would be the
    // second rule this round exists to avoid.
    final env = await pumpSelectionPanel(tester, tool: CanvasTool.move);
    final entriesBefore = env.history.undoCount;
    await dragOnLayer(tester, const Offset(45, 45), const Offset(55, 50));
    env.commands.confirmPendingMove();
    await tester.pump();

    expect(env.history.undoCount, entriesBefore + 1);
    expect(inkAt(env.coordinator, 40, 35), isNonZero);
    expect(inkAt(env.coordinator, 28, 28), 0);
  });

  testWidgets('the move tool grabs anywhere inside the BOX it draws, not '
      'only inside the outline', (tester) async {
    // A lasso triangle: its bounding box has corners the outline does not
    // fill, and those corners are what the user was pressing on.
    final env = await pumpSelectionPanel(
      tester,
      shapeKind: CanvasShapeKind.lasso,
    );
    final origin = tester.getTopLeft(find.byKey(layerKey));
    final gesture = await tester.startGesture(origin + const Offset(20, 20));
    await tester.pump();
    for (final point in const [Offset(120, 20), Offset(120, 120)]) {
      await gesture.moveTo(origin + point);
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    final region = env.commands.region!;
    // The press point: inside the box, OUTSIDE the triangle (the half the
    // hypotenuse cuts off) — and clear of every handle, whose hit radius
    // is 16 screen px and which would otherwise open a SCALE instead.
    final inBoxOutsideOutline = CanvasPoint(x: 40, y: 90);
    expect(
      region.containsPoint(inBoxOutsideOutline),
      isFalse,
      reason: 'precondition: this point is not in the lasso',
    );
    expect(
      region.selectedBounds.left <= inBoxOutsideOutline.x &&
          inBoxOutsideOutline.x <= region.selectedBounds.right &&
          region.selectedBounds.top <= inBoxOutsideOutline.y &&
          inBoxOutsideOutline.y <= region.selectedBounds.bottom,
      isTrue,
      reason: 'precondition: but it IS inside the drawn box',
    );

    await env.setTool(CanvasTool.move);
    expect(region.selectedBounds.left, 20, reason: 'precondition');

    await dragOnLayer(tester, const Offset(40, 90), const Offset(70, 90));

    expect(
      env.commands.movePending,
      isTrue,
      reason: 'the press inside the box started a move',
    );
    // ⚠️CONFIRM FIRST. A move is the affine's tx/ty now, so the committed
    // region stands still until Enter — exactly as a scale or a rotation
    // always has. What the drag moved is on screen and in X/Y; what lands
    // is what this reads.
    env.commands.confirmPendingMove();
    await tester.pump();
    // …and what moved is the LASSO's own outline, +30 across: the box
    // widened the door, it did not become the thing carried through it.
    expect(env.commands.region!.selectedBounds.left, 50);
    expect(env.commands.region!.selectedBounds.right, 150);
  });

  // TP5 (유저: 변형툴쓸때 확정하면 그림이 미세하게 바뀌거든? 살짝 움직이거나?).
  //
  // The confirm lands the stamp at `(centre - size/2).round()`, so a
  // fractional centre snapped AT COMMIT TIME and the artwork stepped by up
  // to half a canvas pixel the moment you pressed confirm. Zoom made it
  // visible: at 400% half a canvas pixel is two screen pixels.
  //
  // 유저 확정 A — round the MOVE itself, so the drag can only ever ask for
  // a whole-pixel translation and the preview is already standing where
  // the commit will write ("바이트단위로 동일해야하니까").
  testWidgets('a move asks for whole canvas pixels, so the confirm moves '
      'nothing', (tester) async {
    // Zoom 3: one screen pixel is a third of a canvas pixel, so a drag of
    // 10 screen px is 3.33… canvas px — fractional by construction.
    // ONE small dab at (40,40) — a 4px square, so "did it land a pixel
    // off" is a question the raster can answer.
    final env = await pumpSelectionPanel(
      tester,
      viewport: seedFromRender(tester, CanvasViewport(zoom: 3)),
      sourceDabs: [dab(40, 40)],
    );
    // Select it, then move: a selection makes the region's own bounds the
    // thing to measure. Screen ÷ 3 = canvas, so this marquee is canvas
    // 30..60 and the dab sits inside it.
    await dragOnLayer(tester, const Offset(90, 90), const Offset(180, 180));
    await env.setTool(CanvasTool.move);
    expect(env.commands.region!.selectedBounds.left, 30, reason: 'start');

    // 10 screen px = 3.33… canvas px: fractional by construction.
    await dragOnLayer(tester, const Offset(135, 135), const Offset(145, 135));

    // 🚨★★★**READ IT OFF X/Y — THAT IS WHERE A MOVE LIVES** (유저
    // 2026-09-22: 「이동값이 X,Y잖아. tvp도 그렇고」). ↩️This used to read the
    // committed region, because the drag walked it over on release; the
    // affine holds the move now and the region stands still until Enter,
    // like every other transform value.
    final moved = env.commands.transformValues!.tx;
    expect(
      moved,
      moved.roundToDouble(),
      reason:
          '유저: 「캔버스쪽 직접 손으로 끌어서 이동하는거는 소수점은 '
          '이동안되게. 즉 스냅. 15다음이 15.2 이런식말고 16되도록」',
    );
    expect(moved, isNot(0), reason: 'precondition: it did move');

    // And the CEL lands on exactly that: the commit rounds
    // `(centre - size/2)`, so a fractional ask would arrive a pixel away
    // from where the float had been showing it all through the drag.
    env.commands.confirmPendingMove();
    await tester.pump();
    await settle(tester);
    final shift = moved.round();
    expect(
      inkAt(env.coordinator, 40 + shift, 40),
      isNonZero,
      reason: 'the ink is exactly where the preview promised',
    );
    expect(
      inkAt(env.coordinator, 40 + shift + 3, 40),
      0,
      reason: 'and not one pixel past it',
    );
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
      isNonZero,
      reason: 'pending: nothing is written yet, so the cel is untouched '
          '(2026-09-17 — the hole lives in what the panel DRAWS)',
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

    // ⚠️Stated rather than dragged. ↩️This pressed at (45,45) and relied on
    // 「a press anywhere on the pasteboard grabs the whole picture」, which
    // 유저 superseded on 2026-09-22: 「사각형 밖 조작은 회전으로 통하도록」.
    // The subject here was never the gesture — it is the degenerate bounds
    // branch, where pasteboard-only ink used to collapse to an empty rect
    // and fall back to a whole canvas holding nothing.
    env.commands.beginTransform();
    await tester.pump();
    env.commands.setTransformValues(
      tx: 10,
      ty: 5,
      rotationDegrees: 0,
      scale: 1,
    );
    await tester.pump();
    env.commands.commitTransform();
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

  /// 🚨★★★**I-38 — 유저 2026-09-16**: 「변형 도구 사용시, 자유든 일반이든
  /// 뭐든 묻지말고 변형도구 사용시 **기존의 실루엣**(사각형 라인이나
  /// 메시워프든 **낡지 않을 구조로**)을 **초록색 선**(변형하지 않았다는 그
  /// 선 ui 그대로)으로 보여줌. **확정시 사라짐.** 즉 변형중에는 보이도록」.
  testWidgets('I-38: the box shows where it STARTED while it is open, and '
      'that line goes on the confirm', (tester) async {
    final env = await pumpSelectionPanel(tester, tool: CanvasTool.move);

    expect(
      antsOnScreen(tester)?.startShape,
      isNull,
      reason: '⛔fixture premise: nothing to show before a box is open',
    );

    env.commands.beginTransform();
    await tester.pump();
    final started = antsOnScreen(tester)?.startShape;
    expect(started, isNotNull, reason: '변형중에는 보이도록');

    // Moving the box does not move the line — that is the whole point of
    // it: it says where this started, against what the chrome now shows.
    await dragOnLayer(tester, const Offset(45, 45), const Offset(60, 50));
    expect(
      antsOnScreen(tester)?.startShape,
      same(started),
      reason:
          '🚨it is the shape the SESSION began with, not the live one — a '
          'line that followed the drag would be saying nothing',
    );

    env.commands.commitTransform();
    await tester.pump();
    expect(
      antsOnScreen(tester)?.startShape,
      isNull,
      reason: '유저: 「확정시 사라짐」',
    );
  });

  /// 🚨★★★**⑦상자 밖에서 시작한 드래그는 회전이다.**
  ///
  /// 🗣️유저 2026-09-22: 「우선 **사각형 밖 조작은 회전으로 통하도록**. 지금
  /// 있는 **회전 꼭짓점은 잔재 싹 삭제**하고. **사각형 내부 조작은 지금처럼
  /// 위치이동**」.
  testWidgets('⑦상자 밖에서 시작한 드래그는 회전, 안은 이동', (tester) async {
    final env = await pumpSelectionPanel(tester, tool: CanvasTool.move);
    env.commands.beginTransform();
    await tester.pump();
    expect(env.commands.transformValues!.rotationDegrees, 0, reason: '시작');

    // The implicit box frames the fixture's picture (28..62), so (100,100)
    // is outside it and still on the canvas.
    await dragOnLayer(tester, const Offset(100, 100), const Offset(100, 140));

    expect(
      env.commands.transformValues!.rotationDegrees,
      isNot(0),
      reason: '유저: 「사각형 밖 조작은 회전으로 통하도록」',
    );
    expect(
      env.commands.transformValues!.tx,
      0,
      reason: '⛔밖은 이동이 아니다 — 둘이 섞이면 그게 두 법이다',
    );
  });

  testWidgets('⑦…그리고 상자 안은 회전이 아니라 이동이다', (tester) async {
    // ⛔CONTROL for the pin above: without it, 「밖은 회전」 would also pass
    // on a box that rotates wherever you press.
    final env = await pumpSelectionPanel(tester, tool: CanvasTool.move);
    env.commands.beginTransform();
    await tester.pump();

    await dragOnLayer(tester, const Offset(45, 45), const Offset(55, 50));

    expect(env.commands.transformValues!.rotationDegrees, 0);
    expect(env.commands.transformValues!.tx, isNot(0));
  });

  /// 🚨★★★**⑪취소는 버튼이고, Escape와 같은 일을 한다.**
  ///
  /// 🗣️유저 2026-09-22: 「상자밖은 기본은 회전에 **확정/취소만 버튼** 만들면
  /// 쉽겟고」 — a press outside the box turns it now, so the way out cannot
  /// be a press outside the box.
  ///
  /// ⛔And it reverts the MOVE too. ↩️Cancel used to leave a box that had
  /// been moved pending while reverting one that had been scaled — two
  /// answers to 「취소」 by which handle you had used. That split was only
  /// real while the move lived outside the affine.
  testWidgets('⑪취소 버튼이 상자도 이동도 되돌린다', (tester) async {
    final env = await pumpSelectionPanel(tester, tool: CanvasTool.move);
    await dragOnLayer(tester, const Offset(45, 45), const Offset(55, 50));
    expect(env.commands.transformActive, isTrue, reason: '⛔전제: 상자가 열림');
    expect(env.commands.transformValues!.tx, isNot(0), reason: '⛔전제: 옮김');

    await tester.tap(
      find.byKey(const ValueKey<String>('selection-move-cancel')),
    );
    await tester.pump();

    expect(env.commands.transformActive, isFalse, reason: '상자가 닫혔다');
    expect(env.commands.movePending, isFalse, reason: '세션도 끝났다');
    expect(
      inkAt(env.coordinator, 30, 30),
      isNonZero,
      reason: '그림이 제자리로 — 취소는 취소다',
    );
    expect(inkAt(env.coordinator, 40, 35), 0, reason: '옮겨진 자리는 비었다');
  });

  /// 🚨★★★**⑧일반변형에도 각 변 중앙에 핸들이 있다.**
  ///
  /// 🗣️유저 2026-09-22: 「**일반변형도 자유변형처럼 각 변 중앙에 버튼? 두도록.
  /// 자유변형이랑 법 통일**해서. 이제 기본조작은 어떤 꼭짓점 편집하든
  /// 중심기준 크기변형이지만, **수정자통한 조작이 변 중앙의 꼭짓점 조작이
  /// 필요**해진다는게 이유임」.
  testWidgets('⑧일반변형의 변 중앙 핸들이 한 축만 늘린다', (tester) async {
    final env = await pumpSelectionPanel(tester, tool: CanvasTool.move);
    env.commands.beginTransform();
    await tester.pump();

    final chrome = antsOnScreen(tester)!.transformChrome!;
    final topMid = (chrome.box[0] + chrome.box[1]) / 2;
    // ⛔Found by WHERE it is, not by its index: the order `_scaleHandles`
    // happens to build in is spelling, and this pin is about the middle of
    // an edge having a grip.
    final grip = chrome.handles.reduce(
      (a, b) => (a - topMid).distance <= (b - topMid).distance ? a : b,
    );
    expect(
      (grip - topMid).distance,
      lessThan(1),
      reason: '변 중앙에 핸들이 있다',
    );

    // ⚠️Measured on the BOX, not on `transformValues.scale` — that field
    // carries `sx` alone, so a stretch along y is invisible to it. The box
    // is what the user sees and what the pin is about.
    double width(SelectionTransformChrome c) =>
        (c.box[1] - c.box[0]).distance;
    double height(SelectionTransformChrome c) =>
        (c.box[3] - c.box[0]).distance;
    final wasWide = width(chrome);
    final wasTall = height(chrome);

    await dragOnLayer(tester, grip, grip + const Offset(0, -20));

    final after = antsOnScreen(tester)!.transformChrome!;
    expect(height(after), greaterThan(wasTall), reason: '끌린 축이 늘었다');
    expect(
      width(after),
      closeTo(wasWide, 0.5),
      reason: '⛔그리고 다른 축은 그대로 — 변 핸들은 한 축이다',
    );
  });

  /// 🚨★★★**F-108 — 선택 없이 연 변형에는 개미가 없다.**
  ///
  /// 🗣️유저 2026-09-12: 「선택툴 안하고 그냥 변형사용시 … **선택툴의
  /// 개미행렬이 남아있음** … 그러지않도록」. Landed once (`d0d6089f`, the
  /// channel's `region`/`liveShape` split) and found again by hand on
  /// 2026-09-22: 「**아직도** 선택없이 변형시작하면 사각형에 뒤에 잘보면
  /// 개미행렬 있는데 … **구조적으로 생길수밖에 없는게 문제라면 구조를
  /// 바꾸라고**」.
  ///
  /// ⛔**AND NOTHING PINNED IT.** The whole file passed either way, which
  /// is how it came back. The structure it pins now is that the ants draw
  /// the SELECTION and the box draws itself — so an implicit shape, which
  /// R26 #13 already says is not a selection, gets no ants.
  testWidgets('🚨F-108: a box opened with NO selection draws no ants', (
    tester,
  ) async {
    final env = await pumpSelectionPanel(tester, tool: CanvasTool.move);
    env.commands.beginTransform();
    await tester.pump();
    expect(env.commands.transformActive, isTrue, reason: '⛔fixture: a box');

    expect(
      antsOnScreen(tester)?.committedRegion,
      isNull,
      reason:
          '유저: 「선택툴 안하고 그냥 변형사용시 … 개미행렬이 남아있음」 — '
          '암시 상자는 선택이 아니다(R26 #13)',
    );
    expect(
      env.commands.hasSelection,
      isFalse,
      reason: 'and the channel says the same thing, because it is the '
          'same question',
    );
  });

  testWidgets('⛔CONTROL for F-108: a REAL selection still draws its ants', (
    tester,
  ) async {
    // Without this the pin above passes on a painter that never draws.
    final env = await pumpSelectionPanel(tester);
    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    await env.setTool(CanvasTool.move);
    env.commands.beginTransform();
    await tester.pump();

    expect(antsOnScreen(tester)?.committedRegion, isNotNull);
    expect(env.commands.hasSelection, isTrue);
  });

  testWidgets('I-38: ⛔a session that OUTLIVED its box draws no before-line',
      (tester) async {
    // 🧪A mutant is why this exists. Dropping the 「is a box open」 guard
    // broke nothing, because a confirm ends the session and the shape goes
    // with it either way — the case the guard is actually for is a session
    // with NO box.
    //
    // ↩️That case used to be 「a plain move」, which no longer exists: an
    // inside grab opens the box and the numbers behind it (유저 2026-09-22,
    // 「이동값이 X,Y잖아」). And 취소 now reverts the whole session it
    // opened, so Escape is not the way in either.
    //
    // ★The way in is the IDENTITY confirm: a tap inside lifts and opens a
    // box, and Enter on a box that changed nothing closes it and leaves
    // the float pending — 「identity closes the box with the session still
    // pending」, which `_commitTransform` has said since R16-①.
    final env = await pumpSelectionPanel(tester, tool: CanvasTool.move);
    await tapOnLayer(tester, const Offset(45, 45));
    expect(env.commands.movePending, isTrue, reason: '⛔fixture premise');
    expect(env.commands.transformActive, isTrue, reason: '⛔and a box');

    env.commands.commitTransform();
    await tester.pump();
    expect(env.commands.movePending, isTrue, reason: 'the float pends on');
    expect(env.commands.transformActive, isFalse, reason: 'the box is gone');

    expect(
      antsOnScreen(tester)?.startShape,
      isNull,
      reason:
          'the before-line belongs to the BOX — with no box there is '
          'nothing to draw it beside',
    );
  });

  testWidgets('I-38: and it is whatever shape the session began with — a '
      'LASSO starts as a lasso', (tester) async {
    // 🎯유저: 「사각형 라인이나 메시워프든 **낡지 않을 구조로**」. Nothing in
    // the painter knows the shapes apart, which is what makes that true —
    // so the case that would break a rectangle assumption is the pin.
    final env = await pumpSelectionPanel(
      tester,
      shapeKind: CanvasShapeKind.lasso,
    );
    // A lasso needs a PATH — a straight two-point drag encloses nothing.
    final origin = tester.getTopLeft(find.byKey(layerKey));
    final gesture = await tester.startGesture(origin + const Offset(20, 20));
    await tester.pump();
    for (final point in const [Offset(120, 20), Offset(120, 120)]) {
      await gesture.moveTo(origin + point);
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
    expect(env.commands.hasSelection, isTrue);

    await env.setTool(CanvasTool.move);
    env.commands.beginTransform();
    await tester.pump();

    final started = antsOnScreen(tester)?.startShape;
    expect(started, isNotNull);
    expect(
      started!.singleShape?.points.length,
      3,
      reason:
          '⛔the TRIANGLE the drag traced, corner for corner. A rectangle '
          'would read 4, so this is what says nothing between the session '
          'and the painter flattened the shape into a box',
    );
  });

  testWidgets('H28: an OPEN box that has moved already reads as changed — 유저: '
      '「변형중일땐 … 변경사항이 있으면 … 빨간색」', (tester) async {
    final env = await pumpSelectionPanel(tester, tool: CanvasTool.move);

    env.commands.beginTransform();
    await tester.pump();
    expect(chromeOnScreen(tester), isNotNull, reason: 'the box is open');
    expect(
      antsOnScreen(tester)?.sessionHasChanges,
      isFalse,
      reason: 'an untouched box has changed nothing — green',
    );

    // Still OPEN: no confirm, no commit. 🚨Every place that sets the
    // move-session dirty flag is a COMMIT point, so this is exactly the
    // window that used to stay green however far the user dragged.
    await dragOnLayer(tester, const Offset(45, 45), const Offset(55, 45));
    expect(env.commands.transformActive, isTrue, reason: 'still open');
    expect(
      antsOnScreen(tester)?.sessionHasChanges,
      isTrue,
      reason:
          'the box would change pixels, and the user has not confirmed '
          'it — that is what red means',
    );
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
    // ↩️This asked the CEL until 2026-09-17 — 「the second lift has to ERASE
    // its origin too」 — and the defect it guards is the user's: 「원본그림
    // 존재하고 변형된 그림도 존재」. A session writes nothing now, so the cel
    // legitimately holds the original while the box is open; what must not
    // show the ink twice is the SCREEN, which 「전/중/후 같은 그림」 pins.
    expect(
      inkAt(env.coordinator, 40, 30),
      isNonZero,
      reason: 'the second lift wrote nothing either — the cel is untouched',
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

    // 🚨THE VEHICLE CHANGED, THE LAW DID NOT (F-42, 유저 2026-08-29). This
    // used to drag an EDGE handle, on the reasoning that an edge was an
    // affine scale in 퍼스 and so left every corner offset at zero. An edge
    // handle now carries its two quad corners, so it is no longer a way to
    // leave the quad untouched. An opened box that is only TRANSLATED is.
    env.commands.beginTransform();
    await tester.pump();
    expect(env.commands.transformActive, isTrue);
    await dragOnLayer(tester, const Offset(45, 45), const Offset(53, 45));
    final values = env.commands.transformValues;
    expect(values, isNotNull);
    expect(values!.rotationDegrees, 0, reason: 'a translate does not rotate');

    env.commands.commitTransform();
    await tester.pump();
    expect(env.commands.movePending, isFalse);
    // ⛔THE ASSERTION THE OLD TEST WAS MISSING. Its title said "resamples
    // through the AFFINE path" and it checked neither the path nor the
    // quad — it would have passed with every corner warped. The quad is
    // what "untouched" means, so the quad is what gets asserted.
    expect(
      env.commands
          .recallFor(TransformMode.perspective)!
          .cornerOffsets
          .every((offset) => offset.x == 0 && offset.y == 0),
      isTrue,
      reason:
          'nothing touched a corner, so the quad is identity and the '
          'commit had no homography to run',
    );
  });

  testWidgets('퍼스 mode: an EDGE handle carries that edge\'s two corners, '
      'so the side moves off its own axis (F-42)', (tester) async {
    // 🚨유저 2026-08-29: 「오른쪽 중앙 조절시 **상하가 안바뀌게 스냅되있는데
    // 스냅해제. 자유롭게 바뀌게**」 — and it was never a snap. The handle
    // drove a one-axis affine SCALE, and a scale cannot move a point along
    // the axis it does not scale, so dragging the right handle UP did
    // nothing however far the hand went. 유저 chose (F-42-Q1) to make the
    // handle carry the edge's two QUAD corners instead.
    final env = await pumpSelectionPanel(
      tester,
      transformMode: TransformMode.perspective,
    );
    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    await env.setTool(CanvasTool.move);

    // The RIGHT edge's midpoint, dragged straight UP — the exact gesture
    // that used to do nothing.
    await dragOnLayer(tester, const Offset(70, 45), const Offset(70, 31));
    expect(env.commands.transformActive, isTrue);

    env.commands.commitTransform();
    await tester.pump();
    final recall = env.commands.recallFor(TransformMode.perspective);
    // 🚨THE FIRST THING THE OLD BEHAVIOUR FAILED. Routed to the affine
    // scale, this exact drag changed NOTHING — a one-axis scale cannot move
    // a point along the axis it does not scale — so the box was never
    // dirty and the commit recorded no transform at all. That is precisely
    // 「상하가 안바뀌게」 as the user saw it.
    expect(
      recall,
      isNotNull,
      reason: 'dragging the right edge upward must BE a transform',
    );
    final offsets = recall!.cornerOffsets;
    expect(offsets, hasLength(4), reason: 'TL/TR/BR/BL');

    // ⛔THE PAIR, AND ONLY THE PAIR. Asserting "something moved" would pass
    // just as well if every corner had moved, which is a translation and
    // not what an edge handle means.
    expect(
      offsets[1].y,
      lessThan(0),
      reason: 'TR followed the hand upward — the whole point of F-42',
    );
    expect(
      offsets[2].y,
      moreOrLessEquals(offsets[1].y, epsilon: 0.01),
      reason:
          'BR moved by the SAME vector, so the right edge stayed straight '
          'instead of shearing',
    );
    expect(
      offsets[0].y,
      0,
      reason: 'TL is on the other edge and must not have moved',
    );
    expect(offsets[3].y, 0, reason: 'BL likewise');
  });

  group('a transform handle is where the hand and the quad say (F-127, F-42)', () {
    testWidgets('🚨F-127: a pen pressed just off a scale handle and moved one '
        'pixel moves the handle about one pixel — it never jumps to the pen', (
      tester,
    ) async {
      // 유저 2026-09-13: 「펜만 변형툴 사용하려고 꼭짓점 클릭시작하면 그 순간
      // 변형이 커진다거나? … 클릭하면 수치가 바로 바뀜. 마우스는 그냥 클릭해도
      // 클릭한다고 변형이 바뀌지 않는데. 로직 한번 확인」.
      final env = await pumpSelectionPanel(tester);
      await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
      await env.setTool(CanvasTool.move);
      env.commands.beginTransform();
      await tester.pump();
      final before = chromeOnScreen(tester)!;

      // The bottom-right handle, pressed 8px further down and right — inside
      // the grab radius, off the handle itself.
      var index = 0;
      for (var i = 1; i < before.handles.length; i += 1) {
        final candidate = before.handles[i];
        final best = before.handles[index];
        if (candidate.dx + candidate.dy > best.dx + best.dy) {
          index = i;
        }
      }
      final handle = before.handles[index];
      final origin = tester.getTopLeft(find.byKey(layerKey));
      final gesture = await tester.startGesture(
        origin + handle + const Offset(8, 8),
        kind: PointerDeviceKind.stylus,
      );
      await tester.pump();
      await gesture.moveBy(const Offset(1, 0));
      await tester.pump();

      final after = chromeOnScreen(tester)!;
      expect(
        (after.handles[index] - handle).distance,
        lessThan(2),
        reason: 'a one-pixel move is a one-pixel move, however far off the '
            'handle the pen came down',
      );
      await gesture.up();
      await tester.pump();
    });

    testWidgets('🚨F-42: in 퍼스 an edge handle stands at the middle of the '
        'quad edge it carries, once a corner has moved', (tester) async {
      // 유저 2026-08-31: 「작동은 하는데 변형툴 ui의 사각형, 상하좌우 중앙의
      // 사각형이 따라서 안움직임. 로직통일」.
      final env = await pumpSelectionPanel(
        tester,
        transformMode: TransformMode.perspective,
      );
      await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
      await env.setTool(CanvasTool.move);
      await dragOnLayer(tester, const Offset(20, 20), const Offset(34, 24));
      expect(env.commands.transformActive, isTrue, reason: 'fixture premise');

      final chrome = chromeOnScreen(tester)!;
      expect(chrome.handles, hasLength(8), reason: 'four corners, four edges');
      const pairs = [
        [0, 1],
        [1, 2],
        [2, 3],
        [3, 0],
      ];
      for (var edge = 0; edge < pairs.length; edge += 1) {
        final middle =
            (chrome.handles[pairs[edge][0]] + chrome.handles[pairs[edge][1]]) /
            2;
        expect(
          (chrome.handles[4 + edge] - middle).distance,
          lessThan(0.5),
          reason: 'edge ${pairs[edge]}',
        );
      }
    });

    testWidgets('🚨F-42: …and it is grabbed where it is drawn', (tester) async {
      final env = await pumpSelectionPanel(
        tester,
        transformMode: TransformMode.perspective,
      );
      await dragOnLayer(tester, const Offset(20, 20), const Offset(120, 120));
      await env.setTool(CanvasTool.move);
      // Far enough that the top edge's middle leaves the affine box's.
      await dragOnLayer(tester, const Offset(20, 20), const Offset(60, 50));
      final before = chromeOnScreen(tester)!;

      final topEdge = before.handles[4];
      await dragOnLayer(tester, topEdge, topEdge + const Offset(0, 10));

      final after = chromeOnScreen(tester)!;
      for (final corner in [0, 1]) {
        expect(
          (after.handles[corner] - before.handles[corner] - const Offset(0, 10))
              .distance,
          lessThan(0.5),
          reason: 'the top edge carries corner $corner',
        );
      }
      for (final corner in [2, 3]) {
        expect(
          (after.handles[corner] - before.handles[corner]).distance,
          lessThan(0.5),
          reason: 'corner $corner is not on the top edge',
        );
      }
    });
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
      viewport: seedFromRender(tester, CanvasViewport()),
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
      viewport: seedFromRender(tester, CanvasViewport()),
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
    // Mid-drag: the DOCUMENT is untouched — the session shows its hole and
    // its float without writing either (2026-09-17). ↩️Until then the base
    // carried the erase from the moment of the lift, and these two read 0.
    expect(inkAt(env.coordinator, 30, 30), isNonZero);
    expect(
      inkAt(env.coordinator, 45, 45),
      isNonZero,
      reason: 'the pixels under the grab are still the cel own pixels',
    );

    // Zero-move release: the session STAYS pending (the float keeps
    // showing the pixels); the document is still untouched.
    await gesture.up();
    await tester.pump();
    expect(env.commands.movePending, isTrue);
    expect(
      inkAt(env.coordinator, 45, 45),
      isNonZero,
      reason: 'the release did not land anything either',
    );

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



  /// 🪦**A 「the hole is DRAWN」 case stood here for one afternoon and was
  /// taken out, because it could not see the thing it claimed to measure**
  /// (2026-09-17). It read the composited panel at the origin and found it
  /// blank while a float was up — but the mutant that switches the
  /// session's holed surface off entirely left it GREEN, which is the only
  /// honest verdict on a pin: it was measuring something else.
  ///
  /// 🔬Why, measured: this harness passes no `viewportUnderlayBuilder`, so
  /// the panel draws its own `_canvasView` and never reaches the layer-stack
  /// composite — and the stack is exactly where an open session's holed
  /// surface is served ([_activeSurfacePainter]'s token). A fixture that
  /// mounts no underlay cannot answer a question about the underlay.
  ///
  /// ⇒ The document half of that law IS pinned, all through this file: the
  /// cel keeps every byte while a box is open, and the landing carries the
  /// erase with the stamp. The DRAWING half needs a host that composites —
  /// the board carries it as its own round rather than a green test that
  /// proves nothing.
  /// 🚨★★★**전/중/후 같은 그림 — THE ABSOLUTE CONDITION OF THIS ROUND.**
  /// 유저 2026-09-17, choosing the non-destructive session: 「**조작 전/중/후가
  /// 빈 프레임 존재안하고 눈에 보이는 결과가 달라지지 않는건 절대조건**」.
  ///
  /// The round moved WHERE the hole lives — out of the cel and into what the
  /// panel draws — and the whole risk of that is a seam frame: one paint in
  /// which the hole has arrived and the float has not, or the document has
  /// changed and the view has not caught up. Either reads as the picture
  /// flickering, and this file's own rule is that the raster is the oracle.
  ///
  /// ⛔**THE SCREEN, NOT THE CEL.** `inkAt` asks the document, which is
  /// exactly what this round stopped changing; a pin written against it
  /// cannot see a flash at all. [screenInkMask] is 「what the user's eye
  /// gets」 — base, hole, float and all.
  ///
  /// Two seams, because there are two moments a picture could jump:
  /// ① the GRAB — a zero-move lift must leave the screen exactly as it was
  /// ② the CONFIRM — which this mask CANNOT answer; the reason is measured
  ///    and written at the end of the case.
  testWidgets('🚨전/중/후 같은 그림: the GRAB leaves the screen exactly as '
      'it was — a hole without its float is a blank frame', (tester) async {
    final env = await pumpSelectionPanel(tester);
    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    expect(env.commands.hasSelection, isTrue, reason: 'fixture premise');
    await settle(tester);
    final before = await screenInkMask(tester);
    final beforeInk = before.where((on) => on).length;
    expect(beforeInk, greaterThan(0), reason: 'there is a picture to watch');

    // ① THE GRAB: press inside the box and let go without moving. The lift
    // happens, the float opens, and nothing may move on screen.
    await env.setTool(CanvasTool.move);
    final origin = tester.getTopLeft(find.byKey(layerKey));
    final grab = await tester.startGesture(origin + const Offset(45, 45));
    await tester.pump();
    await grab.up();
    await tester.pump();
    expect(env.commands.movePending, isTrue, reason: 'the session opened');
    await settle(tester);
    final atGrab = await screenInkMask(tester);
    final grabDelta = inkDelta(before, atGrab);
    expect(
      grabDelta.hole + grabDelta.ghost,
      lessThan((beforeInk * 0.02).round() + 1),
      reason:
          'the grab changed the picture: ${grabDelta.hole} pixels lost, '
          '${grabDelta.ghost} appeared — a hole without its float is the '
          'blank frame this round exists to make impossible',
    );

    // ⛔**THE CONFIRM SEAM CANNOT BE ASKED OF THIS MASK, AND THAT IS
    // MEASURED, NOT ASSUMED** (2026-09-17). A frame with the box open and a
    // frame after it closed differ by the box's own CHROME, which is ink to
    // a red predicate: 🔬moved=860 landed=48 here, and on master — with none
    // of this round in it — moved=822 landed=48. The 774 the old code
    // already 「loses」 at that seam are the outline and handles going away,
    // not artwork. ⚠️This file's own rule says so in [screenInkMask]:
    // 「Counting is not enough, and believing a count cost this file a wrong
    // conclusion once」.
    //
    // ⇒ The landing's correctness is a question about PIXELS, and the pins
    // that ask it are already here: 「the confirm lands ONE undoable pixel
    // move」 and 「a zero-move confirm is a byte-identical landing」. What
    // the screen can answer is the GRAB seam above, where both frames wear
    // the same chrome — and that is the one this round could have broken.
  });
  /// 🚨★★★**A WARNING MID-SESSION TAKES THE DERIVED PICTURE BACK, AND THE
  /// BOX GOES ON WORKING** (2026-09-17). The store's discipline over what an
  /// open tool holds is the half of 유저 확정 2026-09-08 that survived the
  /// reversal — what changed is that the held thing is a DERIVATION now, so
  /// it is given back by dropping it rather than by parking it to disk.
  ///
  /// ⛔**BYTES ALONE CANNOT SAY 「registered」**, and that is why this drives
  /// the warning instead of reading a number: a session whose hole empties
  /// its tiles legitimately owes ZERO (the holed picture holds FEWER tiles
  /// than the cel), so 「bytes > 0」 was the old world's shape and would
  /// have passed for the wrong reason here. 🔬Measured 2026-09-17 on this
  /// very fixture: `bytesNotSharedWith` = 0, because the marquee covers the
  /// whole stroke and the erased tile is dropped rather than rebuilt.
  for (final ending in const ['확정', '되돌리기']) {
    testWidgets('a memory warning mid-session gives the picture back, and '
        '$ending still lands correctly', (tester) async {
      final env = await pumpSelectionPanel(tester);
      final store = env.coordinator.frameStore;

      await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
      await env.setTool(CanvasTool.move);
      await dragOnLayer(tester, const Offset(45, 45), const Offset(60, 60));
      expect(env.commands.movePending, isTrue);
      expect(
        inkAt(env.coordinator, 30, 30),
        isNonZero,
        reason: 'the session wrote nothing — the premise of this round',
      );

      // The OS says memory is tight while the box is open.
      store.respondToMemoryPressure();
      await tester.pump();

      expect(
        env.commands.movePending,
        isTrue,
        reason: 'a warning must not end the user\'s session',
      );

      if (ending == '확정') {
        env.commands.confirmPendingMove();
        await tester.pump();
        expect(env.commands.movePending, isFalse);
        expect(
          inkAt(env.coordinator, 30, 30),
          0,
          reason: 'the landing carries the erase too — the origin is free',
        );
        expect(
          inkAt(env.coordinator, 45, 45),
          isNonZero,
          reason: 'and the pixels are where the move put them',
        );
      } else {
        env.commands.revertPendingMove();
        await tester.pump();
        expect(env.commands.movePending, isFalse);
        expect(
          inkAt(env.coordinator, 30, 30),
          isNonZero,
          reason: 'a revert has nothing to put back — it never left',
        );
      }
      expect(
        store.reclaimableViewBytes,
        0,
        reason: 'the session ended — going on weighing it is a leak',
      );
    });
  }

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

  testWidgets('click-away and Ctrl+D deselect', (tester) async {
    final env = await pumpSelectionPanel(tester);

    await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
    expect(env.commands.hasSelection, isTrue);

    // ↩️This test also nudged the session's float by one pixel and landed
    // it with the confirm. The nudge is gone (F-86, 유저 2026-09-12:
    // 「기능부터 잔존코드 싹 삭제」); a move session driven by a drag is pinned
    // by the free-transform group below.

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
        isNonZero,
        reason: 'Ctrl+T opened a session — and a session writes NOTHING '
            '(2026-09-17; it read 0 while the erase landed at lift time)',
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
      // all of them. The painter's answer to a missing image used to be to
      // borrow whatever decoded last at that COORDINATE within its stale
      // scope — and the float was the one painter in lib/ built without a
      // scope, which put it in a bucket shared by every float ever lifted.
      // The second Ctrl+T of a session therefore drew the FIRST one's
      // artwork, at the first one's place and size, into this float's tile
      // grid. (From 2026-09-11 every float tile knew its predecessor and
      // never reached that fallback; since 2026-09-17 there is no fallback
      // to reach — a tile pictures itself. The invariant below outlives both.)
      //
      // Stated as the invariant rather than the symptom: a painter may not
      // put ink where its own surface is empty. That holds whatever the
      // borrowing policy is.
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
        final floats = floatPainters(
          tester,
          env.coordinator.currentSurfaceOf(env.coordinator.activeFrameKey),
        );
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
        painter.lineage,
        isNotNull,
        reason: 'a scopeless painter shares the bucket every float writes to',
      );
    });

    testWidgets('a float that only MOVED keeps borrowing its own previous '
        'generation', (tester) async {
      // The regression the first version of this fix shipped, and the test
      // that would have caught it.
      //
      // `_floatSurface` used to be rebuilt from an empty surface at five
      // sites, and three of them regenerated a float that ALREADY EXISTED:
      // a drag release, every arrow-key nudge, and Ctrl+T over a pending
      // move. A rebuilt float wider than the painter's four-tile per-pixel
      // budget was three-quarters blank for a frame — and under a held
      // arrow key, which regenerated about thirty times a second, it
      // strobed.
      //
      // The float is built once per lift now (2026-09-11: once per stamp
      // IMAGE, so no site can rebuild it for the same pixels). This is the
      // "merely moves" half, and the fixture must be WIDER than four tiles
      // or the per-pixel path covers the mistake and the test proves
      // nothing.
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

      BitmapSurfacePainter floatPainter() => floatPainters(
        tester,
        env.coordinator.currentSurfaceOf(env.coordinator.activeFrameKey),
      ).first;

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

      // A SECOND MOVE: the same picture, ten pixels over.
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
      //
      // ↩️The second move was an arrow-key nudge. The nudge is gone (F-86,
      // 유저 2026-09-12: 「기능부터 잔존코드 싹 삭제」), so it is a second drag
      // through the same `_commitMove`.
      await dragOnLayer(tester, const Offset(310, 258), const Offset(320, 258));
      await tester.pump();
      final moved = floatPainter();
      expect(
        identical(moved.surface, lifted),
        isTrue,
        reason:
            'a second move rebuilt the float — it is a translation, not new '
            'pixels, and a rebuilt surface has no decoded tiles to paint',
      );
      var undecoded = 0;
      for (final tile in moved.surface.tiles.values) {
        if (BitmapTileImageCache.instance.imageFor(tile) == null) {
          undecoded += 1;
        }
      }
      expect(
        undecoded,
        0,
        reason:
            '$undecoded of the float\'s tiles cannot paint after a second '
            'move; the whole point of not rebuilding is that they already did',
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
        // Both candidates: the base's own painter (a widget's) and the
        // float's (inside the published description since TS1).
        final painters = <BitmapSurfacePainter>[
          ...tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .map((paint) => paint.painter)
              .whereType<BitmapSurfacePainter>(),
          ...tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .map((paint) => paint.painter)
              .whereType<SelectionFloatPainter>()
              .map((painter) => painter.float.surface)
              .whereType<BitmapSurfacePainter>(),
        ];
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
      final floats = floatPainters(tester, committed);
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
        'float-surface branch of the compose', (tester) async {
      // The move path hands the base a float SURFACE rather than a
      // resample image, and it is the path the 208,234-pixel
      // double-composite was measured on (when a hold still covered the
      // landing). Both branches need a landing wider than one decode
      // round, or the base paints it on its own and the test is vacuous.
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
      final floatSurfaces = floatPainters(
        tester,
        committedBefore,
      ).map((painter) => painter.surface).toList();
      expect(
        floatSurfaces,
        isNotEmpty,
        reason: 'no float is mounted during the session — bad premise',
      );
      for (final surface in [committedBefore, ...floatSurfaces]) {
        expect(
          surface.tiles.values.every(
            (tile) =>
                BitmapTileImageCache.instance.imageFor(tile) != null,
          ),
          isTrue,
          reason:
              'a tile on screen has no picture — the bound below '
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
        floatPainters(tester, committedBefore),
        isNotEmpty,
        reason: 'no float during the session — bad premise',
      );

      env.commands.confirmPendingMove();
      await tester.pump();
      final atConfirm = await screenBytes(tester);
      final committed = currentSurface(env.coordinator);
      final covers = floatPainters(tester, committed).length;

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

    testWidgets('confirm, then undo: the frame after the undo is the '
        'pre-lift picture, and nothing of the float is left to paint over '
        'it', (tester) async {
      // The undo restores the pre-lift snapshot — the very tile objects
      // that were on screen before the lift, pictures and all — so the
      // frame after it is whole by construction. What this pins is the
      // other half: that the confirm let the float go. A decoded resample
      // kept past its session paints the landing over whatever comes
      // next, the restored picture included — `ghost` ink where the
      // settled frame has none — and a picture that is let go cannot.
      //
      // A WARPED confirm, deliberately: a pure move has no resample image
      // to keep, so it could not catch a kept one.
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
      await settle(tester);
      expect(env.history.undoCount, greaterThan(0), reason: 'no entry to undo');

      env.history.undo();
      await tester.pump();
      final afterUndo = await screenInkMask(tester);
      expect(
        floatPainters(tester, currentSurface(env.coordinator)),
        isEmpty,
        reason: 'a float is still mounted after the undo',
      );
      expect(
        find.byKey(const ValueKey<String>('transform-resample-preview')),
        findsNothing,
        reason: 'a decoded resample is still mounted after the undo',
      );

      await settle(tester);
      final settled = await screenInkMask(tester);
      final settledInk = settled.where((on) => on).length;
      final delta = inkDelta(afterUndo, settled);
      expect(settledInk, greaterThan(0), reason: 'the restored picture has ink');
      expect(
        delta.ghost,
        0,
        reason:
            '${delta.ghost} pixels of the landing are still drawn over the '
            'restored picture',
      );
      expect(
        delta.hole,
        lessThan((settledInk * 0.1).round()),
        reason:
            'the undo frame lost the picture: ${delta.hole} of $settledInk '
            'absent',
      );
    });

    testWidgets('Enter in the middle of a handle drag lands the picture on '
        'screen: the landed tiles ARE the confirm frame, window or not', (
      tester,
    ) async {
      // Mid-drag the preview resamples only the viewport's window of the
      // picture (ABI 26), and Enter can arrive while the drag is down. The
      // confirm recomputes the whole rect, so the decoded window is not
      // `identical`ly what lands — until 2026-09-11 a hold covered the base
      // with it, and from then until 2026-09-17 it was composed onto the
      // base's tiles as their stand-in. Nothing stands in now: the landed
      // tiles picture themselves inside the confirm frame's paint, and this
      // frame has to come out exact wherever the window reached, which is
      // everything on screen.
      //
      const big = CanvasSize(width: 1800, height: 1400);
      final env = await pumpSelectionPanel(
        tester,
        tool: CanvasTool.move,
        canvasSize: big,
        // Past the 800×600 test viewport in both directions, so a window
        // really is smaller than the picture — and dense enough that the
        // viewport holds more inked tiles than the per-pixel path's four.
        sourceDabs: [
          for (var y = 100; y <= 1140; y += 80)
            for (var x = 100; x <= 1460; x += 80)
              dab(x.toDouble(), y.toDouble()),
        ],
        viewport: seedFromRender(tester, CanvasViewport()),
      );
      await settle(tester);

      // The top-left handle is the one on screen to grab.
      final origin = tester.getTopLeft(find.byKey(layerKey));
      final gesture = await tester.startGesture(
        origin + const Offset(100, 100),
      );
      await tester.pump();
      await gesture.moveTo(origin + const Offset(60, 55));
      await tester.pump();
      // The DECODE, not the resample: `previewIsUp` is the fallback
      // painter, which is up for the float surface as well.
      bool decodedPreviewIsUp() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<SelectionFloatPainter>()
          .any((painter) => painter.float.image != null);
      await pumpUntil(
        tester,
        decodedPreviewIsUp,
        reason: 'the drag-time resample to decode',
      );
      final window = debugLastResampledFloat!.stamp!;
      expect(
        window.width,
        lessThan(1200),
        reason:
            'the decoded preview is the whole picture, not a window of it '
            '— bad premise',
      );

      env.commands.commitTransform();
      // The release changes nothing about the landing — the box closed
      // under it, and its release only lowers the drag flags — but it
      // does change the CHROME, and both captures have to be taken with
      // the same chrome to compare pictures.
      await gesture.up();
      await tester.pump();
      final atConfirm = await screenBytes(tester);
      expect(
        floatPainters(tester, currentSurface(env.coordinator)),
        isEmpty,
        reason: 'the landing is still being covered for',
      );

      await settle(tester);
      final settled = await screenBytes(tester);
      final settledInk = await screenInkMask(tester);
      // Anti-vacuity: more inked tiles on screen than the per-pixel path
      // paints in a frame, or a refused window would go unnoticed.
      final inkedTiles = <int>{};
      for (var i = 0; i < settledInk.length; i += 1) {
        if (settledInk[i]) {
          inkedTiles.add((i ~/ 800 ~/ 256) * 16 + (i % 800) ~/ 256);
        }
      }
      expect(
        inkedTiles.length,
        greaterThan(4),
        reason: 'the landing on screen fits the per-pixel budget — vacuous',
      );
      // Ink absent on the confirm frame is a hole (a tile nothing painted);
      // ink present where the settled frame has none is a ghost (a wrong
      // picture). A channel step or two on a resampled edge is the
      // composition's premultiplied rounding, which the parity sweep
      // bounds at two — neither of the other two is allowed at all.
      bool red(Uint8List px, int i) =>
          px[i] > 128 && px[i + 1] < 100 && px[i + 2] < 100;
      var hole = 0;
      var ghost = 0;
      var worst = 0;
      final where = <String>[];
      for (var i = 0; i < settled.length; i += 4) {
        final now = red(atConfirm, i);
        final later = red(settled, i);
        var pixelWorst = 0;
        for (var c = 0; c < 4; c += 1) {
          final delta = (atConfirm[i + c] - settled[i + c]).abs();
          if (delta > pixelWorst) pixelWorst = delta;
        }
        if (pixelWorst > worst) worst = pixelWorst;
        if (later && !now) hole += 1;
        if (now && !later) ghost += 1;
        if (pixelWorst > 2 && where.length < 12) {
          where.add('(${(i ~/ 4) % 800},${(i ~/ 4) ~/ 800}):$pixelWorst');
        }
      }
      expect(
        worst,
        lessThanOrEqualTo(2),
        reason:
            'a channel moved by $worst on the confirm frame: $hole pixels of '
            'the landing absent, $ghost pixels of ink that is not there — '
            'first at ${where.join(' ')}',
      );
    });

    testWidgets('a second drag on a pending float does not rebuild it — '
        'the same tiles, moved', (tester) async {
      // A rebuild is new tile objects with no picture, for the same pixels
      // — the F-68 family's raw material — and it re-materializes the whole
      // stamp. The float is materialized once per lift; a move is carried
      // by the draw offset, so the surface the second drag paints is the
      // surface the first one made.
      final env = await pumpSelectionPanel(
        tester,
        tool: CanvasTool.move,
        sourceDabs: widePicture,
      );
      await dragOnLayer(tester, const Offset(300, 200), const Offset(340, 225));
      await tester.pump();
      final first = floatPainters(tester, currentSurface(env.coordinator));
      expect(first, hasLength(1), reason: 'no float after the first drag');

      await dragOnLayer(tester, const Offset(340, 225), const Offset(380, 250));
      await tester.pump();
      final second = floatPainters(tester, currentSurface(env.coordinator));
      expect(second, hasLength(1), reason: 'no float after the second drag');
      expect(
        identical(second.single.surface, first.single.surface),
        isTrue,
        reason:
            'the second drag rebuilt the float: new tile objects for the '
            'same pixels',
      );
    });

    testWidgets('a SHRINK confirms and settles to the cel: nothing on screen '
        'where the cel has nothing', (tester) async {
      // 유저 2026-09-11 (F-68 ③, hands-on on Windows debug AND iPad
      // release): 「축소시 변형툴 밖의 이전그림 위치에 그림 생기는건 여전히
      // 존재. 펜으로 바꿔서 그부분 그리려하면 정상적으로 사라짐. 진짜
      // 보이는거만 문제인듯.」 Every other pin in this group compares the
      // confirm frame to the SETTLED frame, and if the settled frame is
      // itself wrong they agree with each other and say nothing. This one
      // holds the settled screen against the CEL.
      final env = await pumpSelectionPanel(
        tester,
        tool: CanvasTool.move,
        sourceDabs: widePicture,
      );
      await settle(tester);
      env.commands.beginTransform();
      await tester.pump();
      env.commands.setTransformValues(
        tx: 0,
        ty: 0,
        rotationDegrees: 0,
        scale: 0.5,
      );
      await settle(tester);
      env.commands.commitTransform();
      await tester.pump();
      await settle(tester);

      final origin = tester.getTopLeft(find.byKey(layerKey));
      final screen = await screenInkMask(tester);
      final surface = currentSurface(env.coordinator);
      var truthInk = 0;
      var ghost = 0;
      var hole = 0;
      final where = <String>[];
      for (var y = 0; y < 600; y += 1) {
        for (var x = 0; x < 800; x += 1) {
          final cx = x - origin.dx.round();
          final cy = y - origin.dy.round();
          final rgba = cx < 0 || cy < 0
              ? 0
              : (surfacePixelRgba(surface, cx, cy) ?? 0);
          final ink = ((rgba >> 24) & 0xff) != 0;
          final shown = screen[y * 800 + x];
          if (ink) truthInk += 1;
          if (shown && !ink) {
            ghost += 1;
            if (where.length < 8) where.add('($x,$y)');
          }
          if (ink && !shown) hole += 1;
        }
      }
      expect(truthInk, greaterThan(0), reason: 'the landing has no ink');
      expect(
        ghost,
        0,
        reason:
            '$ghost pixels of ink on the settled screen where the cel has '
            'none (hole $hole of $truthInk) — first at ${where.join(' ')}',
      );
    });

    testWidgets('🚨the confirm frame IS the settled truth, byte for byte — '
        'and the float the user saw is within a channel step of it', (
      tester,
    ) async {
      // 유저 절대규칙 2026-09-17: 「보이는 중이랑 결과랑 절대로 다르면 안 되」.
      // The question a USER has: on the frame my edit lands, does the
      // picture change under me? Until 2026-09-17 the confirm frame was a
      // composed stand-in (N4 ②: srcOver of the float over the base, up to
      // two channel steps from the commit, one on this fixture) and the
      // truth arrived a decode round later. The landing's tiles picture
      // themselves inside the paint that lands them now, so the confirm
      // frame is measured against the settled truth and must BE it.
      //
      // ⚠️ THE FIXTURE IS THE WHOLE TEST. Every other confirm test here
      // lifts the WHOLE picture with hard opaque dabs, and that is exact by
      // construction: srcOver of an opaque source is exact. So none of
      // them has ever exercised a blend. This one lifts a SUB-REGION of a
      // soft, semi-transparent picture and drops it back on top of the
      // rest, which is the only shape where the float's GPU blend and the
      // commit's kernel can disagree at all — and the anti-vacuity
      // assertion below fails if a future change makes it stop blending.
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
      // the settled frame has no chrome.
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

      // ANTI-VACUITY. The float the user was looking at is the GPU's blend
      // and the landing is the commit kernel's: if no pixel differed
      // between them the landing never blended, and the judgement below
      // would be a statement about nothing.
      expect(
        vsScreen,
        greaterThan(500),
        reason:
            'only $vsScreen pixels differ between the float and the landing '
            '— the landing is not blending, so this measures nothing',
      );
      expect(
        chrome,
        greaterThan(0),
        reason: 'no chrome was masked — the session was not pending',
      );

      // THE JUDGEMENT. The confirm frame is the result: not one byte of it
      // moves when the frame settles.
      // ⛔Mutation: stand anything in for a landed tile (its predecessor's
      // picture, a composition, a blank) → this frame is not the truth.
      expect(
        vsTruth,
        0,
        reason:
            '$vsTruth pixels of the confirm frame differ from the settled '
            'truth (worst channel $vsTruthWorst) — a frame that is not the '
            'result',
      );
      // And the float preview the user confirmed is within one channel step
      // of what landed (the GPU blends premultiplied operands, the kernel
      // blends straight and premultiplies once).
      expect(
        vsScreenWorst,
        lessThanOrEqualTo(1),
        reason:
            'the confirm frame moved the picture under the user by '
            '$vsScreenWorst channel steps on $vsScreen pixels',
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
      // And nothing is built to stand in its place: the session ends on
      // the confirm, so a float surface built here would be new tiles with
      // no picture — measured 20 tiles, 0 decoded, contributing zero
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
            'a float was built for a session that is over: it cannot paint, '
            'and making it costs a full re-materialisation of the stamp',
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

    testWidgets('Escape with the handle still DOWN closes the box for good '
        '— the rest of the drag reopens nothing', (tester) async {
      // The box outlives a handle drag (Enter/Escape close it, not the
      // release), so a drag can outlive its box. `_clearTransform` used to
      // stop the leftover drag by nulling its five fields from outside;
      // once those fields moved onto the drag object, the fact that stops
      // it is the box being gone — and nothing measured that either way.
      final env = await pumpSelectionPanel(tester);
      await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
      env.commands.beginTransform();
      await tester.pump();
      expect(env.commands.transformActive, isTrue);

      final origin = tester.getTopLeft(find.byKey(layerKey));
      final gesture = await tester.startGesture(origin + const Offset(20, 20));
      await tester.pump();
      await gesture.moveTo(origin + const Offset(30, 30));
      await tester.pump();
      expect(
        env.commands.transformActive,
        isTrue,
        reason: 'precondition: the top-left handle drag is live',
      );

      env.commands.cancelTransform();
      await tester.pump();
      expect(env.commands.transformActive, isFalse, reason: 'Escape closed it');

      // The hand keeps going, and then comes off.
      await gesture.moveTo(origin + const Offset(50, 50));
      await tester.pump();
      expect(
        env.commands.transformActive,
        isFalse,
        reason: 'a scale solved from the drag\'s captured affine would put '
            'the box back up under a session the user has already cancelled',
      );
      await gesture.up();
      await tester.pump();
      expect(env.commands.transformActive, isFalse);
      expect(env.commands.movePending, isFalse);
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
    // A move drag lifts the lasso region's pixels into a pending session;
    // the confirm lands them moved (+20,0) — the raster is the record.
    // ↩️It was a (+2,0) arrow-key nudge until the nudge went (F-86, 유저
    // 2026-09-12: 「기능부터 잔존코드 싹 삭제」).
    await env.setTool(CanvasTool.move);
    await dragOnLayer(tester, const Offset(40, 40), const Offset(60, 40));
    env.commands.confirmPendingMove();
    await tester.pump();
    expect(inkAt(env.coordinator, 50, 30), isNonZero);
    expect(inkAt(env.coordinator, 30, 30), 0);
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

    // TS6 (유저: 폴리곤필 첫번째 점 찍을때 동그란 포인트 바로 보이게해줬으면함.
    // 지금은 세번째 포인트 찍어야 보여서 첫번째 점 찍은건지 만건지 모르겠음).
    //
    // ⛔The ring used to wait for `canClosePolygon`, on the grounds that it
    // must not promise a tap that would do nothing. The user's answer widened
    // the promise instead of hiding it: a tap there ENDS the trace, closing
    // when it can and abandoning when it cannot ("불가능할땐 그냥
    // 취소시켜버리면 되잖아. 클튜도 그렇게해"). So it is honest from the first
    // vertex — which is also the only thing that says the vertex landed.
    SelectionAntsPainter? antsPainter(WidgetTester tester) {
      for (final paint in tester.widgetList<CustomPaint>(
        find.descendant(
          of: find.byKey(layerKey),
          matching: find.byType(CustomPaint),
        ),
      )) {
        final painter = paint.painter;
        if (painter is SelectionAntsPainter) {
          return painter;
        }
      }
      return null;
    }

    testWidgets('the close ring is up from the FIRST vertex', (tester) async {
      final env = await pumpSelectionPanel(
        tester,
        shapeKind: CanvasShapeKind.polygon,
      );
      expect(antsPainter(tester)?.closeTarget, isNull, reason: 'nothing open');

      await tapOnLayer(tester, const Offset(20, 20));
      expect(antsPainter(tester)?.closeTarget, CanvasPoint(x: 20, y: 20));
      expect(
        antsPainter(tester)?.closeTargetArmed,
        isFalse,
        reason: 'it can only abandon yet, and it says so',
      );

      await tapOnLayer(tester, const Offset(80, 20));
      await tapOnLayer(tester, const Offset(80, 80));
      expect(antsPainter(tester)?.closeTargetArmed, isTrue);
      expect(env.commands.canClosePolygon, isTrue);
    });

    testWidgets('tapping the ring before it can close ABANDONS the trace', (
      tester,
    ) async {
      final env = await pumpSelectionPanel(
        tester,
        shapeKind: CanvasShapeKind.polygon,
      );
      await tapOnLayer(tester, const Offset(20, 20));
      await tapOnLayer(tester, const Offset(80, 20));
      expect(env.commands.polygonPoints, hasLength(2));

      await tapOnLayer(tester, const Offset(20, 20));
      expect(
        env.commands.hasOpenPolygon,
        isFalse,
        reason: 'two vertices enclose nothing, so the tap ends it',
      );
      expect(
        env.commands.region,
        isNull,
        reason: 'and nothing was selected on the way out',
      );
    });

    testWidgets('the rubber band follows the pointer and stops at the vertex', (
      tester,
    ) async {
      // 유저: "직선이 커서를 따라 이동하고 찍히면 고정이란 느낌 나야하는데
      // 그게 없음." The band IS the whole drawing while there is one vertex,
      // which is why the vertices themselves wear no dot.
      await pumpSelectionPanel(tester, shapeKind: CanvasShapeKind.polygon);
      await tapOnLayer(tester, const Offset(20, 20));

      final cursor = antsPainter(tester)?.cursor;
      expect(cursor, isNotNull, reason: 'a vertex-tapping shape has a band');

      final origin = tester.getTopLeft(find.byKey(layerKey));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      // A hover, not a drag: the band has to follow a pointer that is not
      // pressing anything, which is how a vertex is aimed with a pen or a
      // mouse. (A finger has no hover at all — there the band follows only
      // while the contact is down, which is that device's aiming window.)
      await gesture.addPointer(location: origin);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(origin + const Offset(60, 40));
      await tester.pump();
      expect(cursor!.value, const Offset(60, 40));

      // …and it keeps up without anyone rebuilding the layer: the notifier
      // is merged into the painter's own repaint.
      await gesture.moveTo(origin + const Offset(70, 50));
      await tester.pump();
      expect(cursor.value, const Offset(70, 50));
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

  // TS9 (유저: 지금 1핑거가 플립모드인데도 선택툴고르고 터치하면 선택이 작동함.
  // 명백한 버그지. 드로잉모드가 아닌이상은 툴이 작동하면 안되지).
  group('a finger only drives a tool when the one-finger slot draws', () {
    setUp(() {
      AppInput.settings.value = AppInput.settings.value.copyWith(
        touchDragOneFinger: CanvasTouchDragAction.flip,
      );
    });
    tearDown(() {
      AppInput.settings.value = AppInputSettings.testCorpusBaseline;
    });

    Future<void> dragWith(
      WidgetTester tester,
      PointerDeviceKind kind, {
      required Offset from,
      required Offset to,
    }) async {
      final origin = tester.getTopLeft(find.byKey(layerKey));
      final gesture = await tester.startGesture(origin + from, kind: kind);
      await tester.pump();
      await gesture.moveTo(origin + to);
      await tester.pump();
      await gesture.up();
      await tester.pump();
    }

    testWidgets('a touch marquee makes no selection; the pen still does', (
      tester,
    ) async {
      final env = await pumpSelectionPanel(tester);
      await dragWith(
        tester,
        PointerDeviceKind.touch,
        from: const Offset(20, 20),
        to: const Offset(70, 70),
      );
      expect(
        env.commands.hasSelection,
        isFalse,
        reason: 'the finger was flipping pages, not selecting',
      );

      await dragWith(
        tester,
        PointerDeviceKind.stylus,
        from: const Offset(20, 20),
        to: const Offset(70, 70),
      );
      expect(
        env.commands.hasSelection,
        isTrue,
        reason: 'the slot is about FINGERS — a pen is never in doubt',
      );
    });

    testWidgets('a touch cannot lay a polygon vertex either', (tester) async {
      final env = await pumpSelectionPanel(
        tester,
        shapeKind: CanvasShapeKind.polygon,
      );
      final origin = tester.getTopLeft(find.byKey(layerKey));
      final finger = await tester.startGesture(
        origin + const Offset(20, 20),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      await finger.up();
      await tester.pump();
      expect(env.commands.polygonPoints, isEmpty);
    });
  });

  group('🚨F-68 ②: a PARTIAL lift', () {
    // 「그림의 일부가 1프레임 이상한곳에 생겼다가 사라짐 … 매번 다른데」.
    //
    // Every other lift in this file takes the WHOLE picture, and a coordinate
    // taken whole is the one case the lift already answered: it drops the
    // base's stale entry there. This rect cuts through the tiles along all
    // four edges, so there the lift takes only PART of a tile — and makes
    // TWO new tiles with no picture: the base's, emptied where the float
    // came from, and the float's own. The painter answered for the base with
    // the pre-erase tile, lifted pixels included, and for the float with
    // nothing. While the float sat still the two lies cancelled.
    //
    // ⛔The base must have been ON SCREEN first: the stale fallback only
    // answers with pictures that decoded, and a cold cache would let the
    // first test below pass on the bug.
    const from = Offset(150, 110);
    const to = Offset(390, 330);

    testWidgets('leaves no copy of what it took in the old place, and no '
        'hole in the float, on the frame the float moves', (tester) async {
      final env = await pumpSelectionPanel(tester, sourceDabs: widePicture);
      await settle(tester);
      await dragOnLayer(tester, from, to);
      await env.setTool(CanvasTool.move);
      // A MOVE DRAG, not an open box: the drag translates the float's own
      // surface on the very next frame, while a box's translation waits for
      // its preview image to decode — and that wait is a different question
      // from the one this pin asks.
      final origin = tester.getTopLeft(find.byKey(layerKey));
      final hand = await tester.startGesture(origin + (from + to) / 2);
      await tester.pump();
      await hand.moveBy(const Offset(70, 50));
      // ⛔ONE frame, and no `runAsync` before the capture: the float has
      // moved and nothing the lift created has decoded yet.
      await tester.pump();
      final moved = await screenInkMask(tester);
      // ⛔Against the SAME frame state with its pictures landed: the finger
      // is still down, so the ants and the box sit exactly where they did.
      // Compared with a frame that had different chrome, the pixels under a
      // moved ant line count as ink gone — a first draft measured exactly
      // that and blamed it on the tiles.
      await settle(tester);
      final settled = await screenInkMask(tester);
      await hand.up();
      await tester.pump();
      final settledInk = settled.where((on) => on).length;
      final delta = inkDelta(moved, settled);
      expect(settledInk, greaterThan(0), reason: 'the picture has ink at all');
      expect(
        delta.ghost,
        0,
        reason:
            '${delta.ghost} pixels of artwork where the settled picture has '
            'none — what the lift took, drawn back in its old place',
      );
      expect(
        delta.hole,
        0,
        reason:
            '${delta.hole} of $settledInk pixels missing — the float had '
            'nothing to draw where it took only part of a tile',
      );
    });

    testWidgets('shows the picture whole on the frame it lifts', (
      tester,
    ) async {
      // The guard on the fix above, and why its two halves land together:
      // give the base the truth without giving the float pictures of its
      // own, and the lifted part vanishes on exactly this frame.
      final env = await pumpSelectionPanel(tester, sourceDabs: widePicture);
      await settle(tester);
      await dragOnLayer(tester, from, to);
      await env.setTool(CanvasTool.move);
      env.commands.beginTransform();
      await tester.pump();
      final lifted = await screenInkMask(tester);
      // ⛔Against the same box with its pictures landed, for the reason the
      // pin above gives: a frame with different chrome counts the ink under
      // an ant line as gone.
      await settle(tester);
      final settledLift = await screenInkMask(tester);
      final delta = inkDelta(lifted, settledLift);
      expect(
        delta.hole,
        0,
        reason: '${delta.hole} pixels of the picture gone on the lift frame',
      );
      expect(
        delta.ghost,
        0,
        reason: '${delta.ghost} pixels of ink the picture never had',
      );
    });
  });

  testWidgets('🚨a transform past the pasteboard wall builds only what can '
      'land — the preview buffer IS the wall, and everything inside the '
      'wall lands (C-ipad-crash)', (tester) async {
    // Scaled five times about its centre, a 60×40 picture spans
    // (-120,-80)..(180,120) and the pasteboard is (-60,-40)..(120,80).
    // Before the wall the resample built all 300×200 and the landing threw
    // two thirds of it away — at a phone's canvas size, hundreds of MB per
    // transform, and more for every larger scale.
    const canvasSize = CanvasSize(width: 60, height: 40);
    final env = await pumpSelectionPanel(
      tester,
      tool: CanvasTool.move,
      canvasSize: canvasSize,
      sourceDabs: [
        for (var y = 2.0; y < 40; y += 3)
          for (var x = 2.0; x < 60; x += 3) dab(x, y),
      ],
    );
    env.commands.setRegion(
      CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: 0, top: 0, right: 60, bottom: 40),
      ),
    );
    await tester.pump();

    debugLastResampledFloat = null;
    env.commands.beginTransform();
    await tester.pump();
    env.commands.setTransformValues(
      tx: 0,
      ty: 0,
      rotationDegrees: 0,
      scale: 5,
    );
    await tester.pump();

    final previewed = debugLastResampledFloat;
    expect(previewed, isNotNull, reason: 'fixture: the preview resampled');
    final stamp = previewed!.stamp!;
    expect(
      (
        left: (previewed.center.x - stamp.width / 2).round(),
        top: (previewed.center.y - stamp.height / 2).round(),
        width: stamp.width,
        height: stamp.height,
      ),
      (
        left: canvasSize.pasteboardLeft,
        top: canvasSize.pasteboardTop,
        width: canvasSize.pasteboardRightExclusive - canvasSize.pasteboardLeft,
        height: canvasSize.pasteboardBottomExclusive - canvasSize.pasteboardTop,
      ),
      reason:
          'the whole picture is on screen, so the preview is the buffer '
          'Enter lands — and it stops at the wall',
    );

    env.commands.commitTransform();
    await tester.pump();

    final right = canvasSize.pasteboardRightExclusive - 1;
    final bottom = canvasSize.pasteboardBottomExclusive - 1;
    for (final (x, y) in [
      (canvasSize.pasteboardLeft, canvasSize.pasteboardTop),
      (right, canvasSize.pasteboardTop),
      (canvasSize.pasteboardLeft, bottom),
      (right, bottom),
    ]) {
      expect(
        (inkAt(env.coordinator, x, y) >> 24) & 0xff,
        0xff,
        reason: 'the corner ($x,$y) of the wall is inside the picture',
      );
    }
  });

  /// 🚨★★★**A PENDING MOVE DOES NOT HOLD THE TIMELINE** — F-116 and F-86,
  /// 유저 2026-09-12: 「프레임 3개 그리고 … 버그나서 **타임라인쪽 조작이
  /// 안먹힘. 룰러쪽 선택해도 드래그안되고 화살표이동도 안먹고**」, and on
  /// 2026-09-17: 「둘다 해당 버그 상황에서 타임라인 조작 먹통되니까 원인 하나
  /// 공통되는거 있을거로 예상되니 근본/구조적으로 해결하고 법 통일」.
  ///
  /// R15-⑤ refuses every seek, scrub, row press and cut switch while an
  /// editing interaction is held, and that is right for a GESTURE: the
  /// playhead moves when the pen lifts, never under it. A pending session
  /// is not a gesture — the hand is already off it — and it was held only
  /// because the lift committed its erase, so walking away left a HOLE.
  /// `314aa6e8` stopped writing anything until the landing, and this is the
  /// consequence: there is nothing left behind to protect.
  ///
  /// ⛔The DRAG still holds it, and this asks for that too: what must come
  /// back to zero is the state after the hand lifts, not during it.
  group('a pending move does not hold the timeline', () {
    testWidgets('the hold is back to zero while the move is still pending', (
      tester,
    ) async {
      var held = 0;
      final env = await pumpSelectionPanel(
        tester,
        onSelectionInteractionChanged: (active) => held += active ? 1 : -1,
      );
      await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
      await env.setTool(CanvasTool.move);
      await dragOnLayer(tester, const Offset(45, 45), const Offset(55, 50));

      expect(
        env.commands.movePending,
        isTrue,
        reason: '🚨the session has to be OPEN or this proves nothing',
      );
      expect(
        held,
        0,
        reason:
            'the pending session is still holding the edit lock: every '
            'seek, scrub, row press and cut switch is refused while a box '
            'is open, which is 유저「타임라인쪽 조작이 안먹힘」',
      );
    });

    /// 🚨★★★**AND WALKING THE SHEET DOES NOT LAND IT** — 유저 2026-09-17:
    /// 「프레임이동이나 레이어이동등은 **착지시킬 이유가 없는것들은 착지안하고
    /// 편집중 그대로 유지**. 근데 여기서 **다른 도구 선택하는 등만 착지**
    /// 시키는거고」.
    ///
    /// ⛔This case only became possible with the lock gone: before it, the
    /// seek was refused outright, so a frame move never arrived here at all
    /// (🧪measured 2026-09-17: with a box open, next-frame left the playhead
    /// at 0 of 24).
    testWidgets('a cel change keeps the selection and lands NOTHING', (
      tester,
    ) async {
      final env = await pumpSelectionPanel(tester);
      final first = env.coordinator.activeFrameKey;
      final before = surfacePixelRgba(
        env.coordinator.currentSurfaceOf(first),
        30,
        30,
      );
      expect(before, isNonZero, reason: 'the fixture premise');

      await dragOnLayer(tester, const Offset(20, 20), const Offset(70, 70));
      await env.setTool(CanvasTool.move);
      await dragOnLayer(tester, const Offset(45, 45), const Offset(55, 50));
      expect(env.commands.movePending, isTrue, reason: 'the session opened');

      // Walk to the next cel, the way a seek does.
      final next = BrushCanvasFixture.createFrameKeys()[1];
      env.coordinator.selectFrame(next);
      await env.setTool(CanvasTool.move);

      expect(
        surfacePixelRgba(env.coordinator.currentSurfaceOf(first), 30, 30),
        before,
        reason:
            'the frame we walked away from was WRITTEN: a seek is not an '
            'ending, and landing here puts the user\'s edit into a frame '
            'they were only passing through',
      );
      expect(
        env.commands.hasSelection,
        isTrue,
        reason:
            'F-86: 「선택툴 선택한채로 프레임이나 인덱스 이동하면 사라지는데 '
            '뭘 하든 안사라지도록」 — the region walks with you',
      );
      expect(
        env.commands.movePending,
        isFalse,
        reason:
            'the float belonged to the cel we left; the next move lifts '
            'afresh from the one we are standing on',
      );
    });
  });

  /// 🚨★★★**F-108 — 암시적 모양은 선택이 아니다, 확정하고 되돌린 뒤에도.**
  ///
  /// > 「선택툴 안하고 그냥 변형사용시 … **변형하고 확정하고 되돌리면 선택툴의
  /// > 개미행렬이 남아있음. 그 상태에서 컨트롤d눌러야 되는 그런상황발생.** 아마
  /// > 그냥변형해도 선택툴이 작동되는게 로직인거같은데 그러지않도록. **법
  /// > 통합하되 그런부분은 제대로 독립**」 (유저 2026-09-12)
  ///
  /// R26 #13 already decided this and the confirm and the revert both honour
  /// it. What did not was everything DOWNSTREAM of the channel: the box was
  /// written there as an ordinary region, and that channel is what the lift
  /// captures as `regionBefore` and what the stroke clip reads. So the undo
  /// faithfully restored a selection the user never made.
  ///
  /// ⛔**한 필드가 두 질문에 답하고 있었다** — 「무슨 모양이 그려져 있나」와
  /// 「사용자가 무엇을 골랐나」. 이제 채널이 둘을 따로 답한다(`region` ·
  /// `liveShape`), 그래서 **바깥에서 잘못된 쪽을 읽을 수가 없다.**
  group('a transform with nothing selected is not a selection', () {
    testWidgets('the box is on the canvas and NOT in the document', (
      tester,
    ) async {
      final env = await pumpSelectionPanel(tester);
      expect(env.commands.hasRegion, isFalse, reason: 'the premise');

      await env.setTool(CanvasTool.move);
      await dragOnLayer(tester, const Offset(30, 30), const Offset(40, 35));

      expect(
        env.commands.movePending,
        isTrue,
        reason: '🚨the implicit session has to be OPEN or this proves nothing',
      );
      expect(
        env.commands.liveShape,
        isNotNull,
        reason: 'the box IS on screen — that is what is being transformed',
      );
      expect(
        env.commands.region,
        isNull,
        reason:
            '유저: 「그냥변형해도 선택툴이 작동되는게 로직인거같은데 '
            '그러지않도록」 — nothing was selected, so nothing clips a stroke '
            'and nothing is captured as the undo\'s 「before」',
      );
    });

    testWidgets('and confirming then undoing does not resurrect one', (
      tester,
    ) async {
      final env = await pumpSelectionPanel(tester);
      await env.setTool(CanvasTool.move);
      await dragOnLayer(tester, const Offset(30, 30), const Offset(40, 35));
      expect(env.commands.movePending, isTrue, reason: 'the session opened');

      env.commands.confirmPendingMove();
      await tester.pump();
      expect(
        env.commands.hasRegion,
        isFalse,
        reason: 'R26 #13: the confirm ends it — the premise for the undo',
      );

      env.history.undo();
      await tester.pump();
      expect(
        env.commands.hasRegion,
        isFalse,
        reason:
            '유저: 「변형하고 확정하고 되돌리면 선택툴의 개미행렬이 남아있음. '
            '그 상태에서 컨트롤d눌러야 되는」',
      );

      env.history.redo();
      await tester.pump();
      expect(
        env.commands.hasRegion,
        isFalse,
        reason: '리두도 같은 순서 문제를 갖는다 — 되살릴 선택이 애초에 없다',
      );
    });
  });
}

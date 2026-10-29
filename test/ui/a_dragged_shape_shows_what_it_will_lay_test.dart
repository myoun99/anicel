import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/shape_tool_options.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_commit_builder.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/plain_line_region.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';

import '../helpers/brush_canvas_fixture.dart';
import '../helpers/device_viewport.dart';

/// 🗣️I-69-Q4ⓒ (유저 2026-10-08): 「윤곽선은 손을 따라오고, 실제 결과는 따라
/// 그린다」 — while the shape tool's 「일반」 line or its fill is dragged, its
/// ACTUAL result comes up under the outline, laid a few pieces a frame and
/// shown whole or not at all; let go, and what showed is what lands.
///
/// The overlay is the host's here (the panel's merged mode), so what the
/// screen is given to draw can be read without capturing pixels.
void main() {
  const layerKey = ValueKey<String>('canvas-selection-layer');
  const size = CanvasSize(width: 400, height: 300);
  const plain = ShapeToolOptions(
    type: ShapeLineType.plain,
    size: 6,
    antiAlias: false,
  );

  tearDown(() => shapeShowFrameShare = const Duration(microseconds: 4000));

  Future<
    ({
      BrushFrameEditingCoordinator coordinator,
      HistoryManager history,
      ActiveStrokeOverlayModel overlay,
      ValueNotifier<BrushToolState> brush,
      ValueNotifier<double> opacity,
      CanvasSelectionCommands selection,
    })
  >
  pumpPanel(WidgetTester tester, {ShapeToolOptions options = plain}) async {
    final keys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: keys,
      canvasSize: size,
    );
    final history = HistoryManager();
    final overlay = ActiveStrokeOverlayModel();
    addTearDown(overlay.dispose);
    final brush = ValueNotifier(
      BrushToolState.defaults.copyWith(
        tool: CanvasTool.shape,
        drawShape: CanvasShapeKind.rect,
        shapeOptions: options,
      ),
    );
    // The active row's opacity, as the editor hands it to the panel.
    final opacity = ValueNotifier(1.0);
    addTearDown(opacity.dispose);
    final sink = BrushEditCacheInvalidationSink();
    final selection = CanvasSelectionCommands();
    final viewport = seedFromRender(tester, CanvasViewport());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<double>(
            valueListenable: opacity,
            builder: (context, contentOpacity, _) => BrushCanvasPanel(
              coordinator: coordinator,
              canvasSize: size,
              availableFrameKeys: keys,
              cacheInvalidationSink: sink,
              historyManager: history,
              brushToolState: brush,
              selectionCommands: selection,
              viewport: viewport,
              activeStrokeOverlayModel: overlay,
              interactiveContentOpacity: contentOpacity,
              viewportUnderlayBuilder: (context, viewport, painter, float) =>
                  painter == null
                  ? const SizedBox.shrink()
                  : CustomPaint(
                      painter: painter,
                      size: Size(
                        size.width.toDouble(),
                        size.height.toDouble(),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return (
      coordinator: coordinator,
      history: history,
      overlay: overlay,
      brush: brush,
      opacity: opacity,
      selection: selection,
    );
  }

  Future<TestGesture> press(WidgetTester tester, Offset at) async {
    final gesture = await tester.startGesture(
      tester.getTopLeft(find.byKey(layerKey)) + at,
    );
    await tester.pump();
    return gesture;
  }

  Future<void> moveTo(WidgetTester tester, TestGesture gesture, Offset to) =>
      gesture.moveTo(tester.getTopLeft(find.byKey(layerKey)) + to);

  BitmapSurface celOf(BrushFrameEditingCoordinator coordinator) =>
      coordinator.currentSurfaceOf(coordinator.activeFrameKey);

  int alphaAt(BrushFrameEditingCoordinator coordinator, int x, int y) =>
      (surfacePixelRgba(celOf(coordinator), x, y) ?? 0) & 0xFF;

  /// What laying the traced rectangle straight onto [base] lands — the
  /// shape tool's own area, by the builder and the commit, with nothing
  /// shown first: [plain]'s, or a line [width] across at [opacity].
  BitmapSurface laidStraight(
    BitmapSurface base,
    double right,
    double bottom, {
    double? width,
    double? opacity,
    bool antiAlias = false,
  }) {
    final region = plainLineRegion(
      points: CanvasSelectionShape.rect(
        left: 50,
        top: 50,
        right: right,
        bottom: bottom,
      ).points,
      closed: true,
      width: width ?? plain.size,
      corners: plain.corners,
    )!;
    return brushCommitResultForBrushDabSequenceOnBitmapSurface(
      surface: base,
      sequence: BrushDabSequence(
        buildRegionFillDabs(
          region: region,
          color: BrushToolState.defaults.color,
          opacity: opacity ?? plain.opacity,
          options: FloodFillOptions(expandPx: 0, antiAlias: antiAlias),
        ),
      ),
      layerId: const LayerId('oracle'),
      frameId: const FrameId('oracle'),
      blendMode: BrushBlendMode.color,
    ).afterSurface;
  }

  /// The first tile where [a] and [b] part, or null.
  TileCoord? firstDifference(BitmapSurface a, BitmapSurface b) {
    for (final coord in {...a.tiles.keys, ...b.tiles.keys}) {
      final ta = a.tileAt(coord)?.pixels;
      final tb = b.tileAt(coord)?.pixels;
      if (ta == null || tb == null) {
        if ((ta ?? tb)!.any((byte) => byte != 0)) {
          return coord;
        }
        continue;
      }
      for (var i = 0; i < ta.length; i += 1) {
        if (ta[i] != tb[i]) {
          return coord;
        }
      }
    }
    return null;
  }

  testWidgets('while it is dragged the shape comes up under its outline, '
      'and nothing lands until it is let go — then it lands as shown, one '
      'step back', (tester) async {
    final env = await pumpPanel(tester);
    final before = celOf(env.coordinator);
    final steps = env.history.undoCount;

    final gesture = await press(tester, const Offset(50, 50));
    await moveTo(tester, gesture, const Offset(330, 250));
    for (var frame = 0; frame < 40 && !env.overlay.hasStrokeContent; frame++) {
      await tester.pump();
    }
    expect(env.overlay.hasStrokeContent, isTrue, reason: 'the result shows');
    expect(alphaAt(env.coordinator, 50, 50), 0, reason: 'nothing landed');
    expect(env.history.undoCount, steps);

    await gesture.up();
    await tester.pump();
    expect(env.overlay.hasStrokeContent, isFalse, reason: 'it has landed');
    expect(env.history.undoCount, steps + 1, reason: 'one step back');
    expect(
      firstDifference(celOf(env.coordinator), laidStraight(before, 330, 250)),
      isNull,
      reason: 'what landed is the shape tool\'s own area, exactly',
    );
  });

  // R26 #18 (「선택하고 그리면 선택 내부만 그려진다」) while it is dragged
  // too: the maker cuts its pieces at the marquee, and the view lays what it
  // is handed (brush-fidelity-Q9's round took the cut out of the view, which
  // would have cut a held picture twice).
  testWidgets('under a marquee the dragged shape shows only what lands '
      'inside it', (tester) async {
    final env = await pumpPanel(tester);
    env.selection.setRegion(
      CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: 100, top: 0, right: 200, bottom: 300),
      ),
    );
    await tester.pump();

    final gesture = await press(tester, const Offset(50, 50));
    await moveTo(tester, gesture, const Offset(330, 250));
    for (var frame = 0; frame < 40 && !env.overlay.hasStrokeContent; frame++) {
      await tester.pump();
    }
    expect(env.overlay.hasStrokeContent, isTrue, reason: '⛔premise: shown');
    Future<int> shownAlphaAt(int x, int y) async {
      final side = env.overlay.tileSize;
      final picture =
          env.overlay.tileImages[TileCoord(x: x ~/ side, y: y ~/ side)];
      if (picture == null) {
        return 0;
      }
      final data = await tester.runAsync(
        () => picture.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      return data!.getUint8(((y % side) * side + x % side) * 4 + 3);
    }

    expect(await shownAlphaAt(150, 50), isNonZero, reason: 'its top, inside');
    expect(await shownAlphaAt(50, 150), 0, reason: 'its left side, outside');
    await gesture.up();
    await tester.pump();
    expect(alphaAt(env.coordinator, 150, 50), isNonZero, reason: 'landed');
    expect(alphaAt(env.coordinator, 50, 150), 0, reason: 'as shown');
  });

  // 🗣️F-419 (유저 2026-10-21): 「현재 선 레이어 불투명도 100에서 80정도로
  // 내렷다가 100으로 올리니 안그려지기 시작했어」 — the drawing view is built
  // anew each time the row's opacity crosses 1, and the shape it shows and
  // lands is the new view's, whichever way it crossed.
  for (final crossings in [
    [0.8],
    [0.8, 1.0],
  ]) {
    testWidgets('with the row\'s opacity taken through $crossings, a dragged '
        'shape still shows under its outline and lands', (tester) async {
      final env = await pumpPanel(tester);
      final before = celOf(env.coordinator);
      State<StatefulWidget> view() =>
          tester.state(find.byType(InteractiveBrushEditCanvasView));
      final viewBefore = view();
      for (final opacity in crossings) {
        env.opacity.value = opacity;
        await tester.pump();
      }
      expect(view(), same(viewBefore), reason: 'the view is not built anew');

      final gesture = await press(tester, const Offset(50, 50));
      await moveTo(tester, gesture, const Offset(330, 250));
      for (
        var frame = 0;
        frame < 40 && !env.overlay.hasStrokeContent;
        frame++
      ) {
        await tester.pump();
      }
      expect(env.overlay.hasStrokeContent, isTrue, reason: 'it shows');
      await gesture.up();
      await tester.pump();
      expect(
        firstDifference(
          celOf(env.coordinator),
          laidStraight(before, 330, 250),
        ),
        isNull,
        reason: 'it lands as on a view never built anew',
      );
    });
  }

  // 🗣️size-rack-0-7-under-the-brush-floor (유저 2026-10-17 「다른부분
  // 발견되는거있으면 법 통일」): a line under a pixel lands as the brush's
  // does — a pixel across, lighter by the width it lacks (`markUnderAPixel`).
  for (final antiAlias in [true, false]) {
    final how = antiAlias
        ? 'lighter by its width'
        : 'whole with anti-aliasing off (H39)';
    testWidgets('a plain line under a pixel lands as the one-pixel line, '
        '$how', (tester) async {
      final env = await pumpPanel(
        tester,
        options: plain.copyWith(size: 0.3, antiAlias: antiAlias),
      );
      final before = celOf(env.coordinator);

      final gesture = await press(tester, const Offset(50, 50));
      await moveTo(tester, gesture, const Offset(330, 250));
      await gesture.up();
      await tester.pump();

      expect(
        firstDifference(
          celOf(env.coordinator),
          laidStraight(
            before,
            330,
            250,
            width: 1,
            opacity: antiAlias ? plain.opacity * 0.3 : plain.opacity,
            antiAlias: antiAlias,
          ),
        ),
        isNull,
        reason: '↩️a 0.3px band landed whole where it crossed a pixel '
            'centre and nothing where it did not',
      );
    });
  }

  testWidgets('a shape is shown WHOLE or not at all: one piece a frame, the '
      'overlay stays as it was until the last is laid', (tester) async {
    shapeShowFrameShare = Duration.zero;
    final env = await pumpPanel(tester);

    final gesture = await press(tester, const Offset(50, 50));
    await moveTo(tester, gesture, const Offset(330, 290));
    var frames = 0;
    while (!env.overlay.hasStrokeContent) {
      await tester.pump();
      frames += 1;
      expect(frames, lessThan(40), reason: 'it comes up');
    }
    // The rectangle's outline crosses three rows of tiles: a piece for the
    // top row, one for each side in the middle row, one for the bottom —
    // never all in one frame when a frame lays one.
    expect(frames, greaterThan(3), reason: 'it took a frame a piece');
    final shown = env.overlay.tileImages.keys.toSet();
    await tester.pump();
    expect(
      env.overlay.tileImages.keys.toSet(),
      shown,
      reason: 'nothing more comes: it came up whole',
    );
    await gesture.up();
    await tester.pump();
  });

  testWidgets('the hand moved on while a shape was being laid: that one '
      'comes up whole, then the newest', (tester) async {
    shapeShowFrameShare = Duration.zero;
    final env = await pumpPanel(tester);

    final gesture = await press(tester, const Offset(50, 50));
    await moveTo(tester, gesture, const Offset(330, 250));
    await tester.pump(); // one piece of the big one
    await moveTo(tester, gesture, const Offset(100, 100));
    var frames = 0;
    while (!env.overlay.hasStrokeContent) {
      await tester.pump();
      frames += 1;
      expect(frames, lessThan(40));
    }
    expect(
      env.overlay.tileImages.keys,
      contains(TileCoord(x: 2, y: 1)),
      reason: 'the big one came up first, whole — its far corner too',
    );
    for (frames = 0; frames < 40; frames += 1) {
      await tester.pump();
      if (!env.overlay.tileImages.containsKey(TileCoord(x: 2, y: 1))) {
        break;
      }
    }
    expect(
      env.overlay.tileImages.keys.toSet(),
      {TileCoord(x: 0, y: 0)},
      reason: 'then the newest, 50..100, in the first tile alone',
    );
    await gesture.up();
    await tester.pump();
    expect(alphaAt(env.coordinator, 75, 50), isNonZero);
    expect(alphaAt(env.coordinator, 300, 50), 0, reason: 'the old one left');
  });

  testWidgets('let go before the shape is whole: it is finished then, and '
      'lands whole', (tester) async {
    shapeShowFrameShare = Duration.zero;
    final env = await pumpPanel(tester);
    final before = celOf(env.coordinator);

    final gesture = await press(tester, const Offset(50, 50));
    await moveTo(tester, gesture, const Offset(330, 290));
    await tester.pump(); // one of its four pieces laid
    expect(env.overlay.hasStrokeContent, isFalse, reason: '⛔premise');
    await gesture.up();
    await tester.pump();

    expect(
      firstDifference(celOf(env.coordinator), laidStraight(before, 330, 290)),
      isNull,
    );
    expect(env.overlay.hasStrokeContent, isFalse);
  });

  testWidgets('a cancelled drag takes what it showed back and lands '
      'nothing', (tester) async {
    final env = await pumpPanel(tester);
    final steps = env.history.undoCount;

    final gesture = await press(tester, const Offset(50, 50));
    await moveTo(tester, gesture, const Offset(330, 250));
    for (var frame = 0; frame < 40 && !env.overlay.hasStrokeContent; frame++) {
      await tester.pump();
    }
    expect(env.overlay.hasStrokeContent, isTrue, reason: '⛔premise');
    await gesture.cancel();
    await tester.pump();

    expect(env.overlay.hasStrokeContent, isFalse);
    expect(alphaAt(env.coordinator, 50, 50), 0);
    expect(env.history.undoCount, steps);
  });

  testWidgets('dragged back onto its press, the shape is no shape: what '
      'showed goes', (tester) async {
    final env = await pumpPanel(tester);

    final gesture = await press(tester, const Offset(50, 50));
    await moveTo(tester, gesture, const Offset(330, 250));
    for (var frame = 0; frame < 40 && !env.overlay.hasStrokeContent; frame++) {
      await tester.pump();
    }
    expect(env.overlay.hasStrokeContent, isTrue, reason: '⛔premise');
    await moveTo(tester, gesture, const Offset(50.5, 50.5));
    await tester.pump();
    expect(env.overlay.hasStrokeContent, isFalse);
    await gesture.up();
    await tester.pump();
    expect(alphaAt(env.coordinator, 50, 50), 0);
  });

  testWidgets('the hand resting on the shape it shows lays nothing again', (
    tester,
  ) async {
    final env = await pumpPanel(tester);

    final gesture = await press(tester, const Offset(50, 50));
    await moveTo(tester, gesture, const Offset(330, 250));
    for (var frame = 0; frame < 40 && !env.overlay.hasStrokeContent; frame++) {
      await tester.pump();
    }
    final shown = Map.of(env.overlay.tileImages);
    expect(shown, isNotEmpty, reason: '⛔premise');
    await moveTo(tester, gesture, const Offset(330, 250));
    for (var frame = 0; frame < 10; frame += 1) {
      await tester.pump();
    }
    expect(env.overlay.tileImages, shown, reason: 'the very same pictures');
    await gesture.up();
    await tester.pump();
  });

  testWidgets('let go on a shape the hand reached after the one on screen, '
      'its tiles are pictured as themselves — never as the old shape', (
    tester,
  ) async {
    final env = await pumpPanel(tester);

    final gesture = await press(tester, const Offset(50, 50));
    await moveTo(tester, gesture, const Offset(330, 250));
    for (var frame = 0; frame < 40 && !env.overlay.hasStrokeContent; frame++) {
      await tester.pump();
    }
    final oldPicture = env.overlay.tileImages[TileCoord(x: 0, y: 0)];
    expect(oldPicture, isNotNull, reason: '⛔premise');
    await moveTo(tester, gesture, const Offset(100, 100));
    await gesture.up();
    await tester.pump();

    // A fill's result tiles all wear one revision, so only the landing
    // showing ITS tiles first keeps the old shape's picture from being
    // handed to the new shape's tile.
    final landed = celOf(env.coordinator).tileAt(TileCoord(x: 0, y: 0))!;
    expect(
      BitmapTileImageCache.instance.heldFor(landed)?.image,
      isNot(same(oldPicture)),
    );
  });

  // The brush takes the selection layer away; the move tool keeps it.
  for (final tool in [CanvasTool.brush, CanvasTool.move]) {
    testWidgets('a tool switched away mid-drag (${tool.name}) takes back '
        'what it showed', (tester) async {
      final env = await pumpPanel(tester);

      final gesture = await press(tester, const Offset(50, 50));
      await moveTo(tester, gesture, const Offset(330, 250));
      for (
        var frame = 0;
        frame < 40 && !env.overlay.hasStrokeContent;
        frame++
      ) {
        await tester.pump();
      }
      expect(env.overlay.hasStrokeContent, isTrue, reason: '⛔premise');
      env.brush.value = env.brush.value.copyWith(tool: tool);
      await tester.pump();
      await tester.pump();

      expect(env.overlay.hasStrokeContent, isFalse);
      await gesture.up();
      await tester.pump();
      expect(alphaAt(env.coordinator, 50, 50), 0);
    });
  }

  /// A line of the BRUSH type is THE stroke of the brush in hand (I-69), so
  /// what comes up under its outline is that stroke, laid by the stroke's
  /// own code, and what lands is it.
  group('a line of the brush type', () {
    const brushLine = ShapeToolOptions(type: ShapeLineType.brush);

    Future<void> untilShown(
      WidgetTester tester,
      ActiveStrokeOverlayModel overlay,
    ) async {
      for (var frame = 0; frame < 400 && !overlay.hasStrokeContent; frame++) {
        await tester.pump();
      }
    }

    /// What the drag from (50,50) to (330,250) lands let go before a frame
    /// could lay any of it — the stroke laid in one go — on a panel of its
    /// own (the one before goes).
    Future<BitmapSurface> laidInOneGo(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      final env = await pumpPanel(tester, options: brushLine);
      final quick = await press(tester, const Offset(50, 50));
      await moveTo(tester, quick, const Offset(330, 250));
      await quick.up();
      await tester.pump();
      return celOf(env.coordinator);
    }

    testWidgets('comes up as the stroke itself while it is dragged, and '
        'lands as the same drag let go at once lands', (tester) async {
      final env = await pumpPanel(tester, options: brushLine);
      final steps = env.history.undoCount;

      final gesture = await press(tester, const Offset(50, 50));
      await moveTo(tester, gesture, const Offset(330, 250));
      await untilShown(tester, env.overlay);
      expect(env.overlay.hasStrokeContent, isTrue, reason: 'the stroke shows');
      expect(alphaAt(env.coordinator, 50, 50), 0, reason: 'nothing landed');
      expect(env.history.undoCount, steps);

      await gesture.up();
      await tester.pump();
      expect(env.overlay.hasStrokeContent, isFalse, reason: 'it has landed');
      expect(env.history.undoCount, steps + 1, reason: 'one step back');
      expect(alphaAt(env.coordinator, 50, 50), isNonZero, reason: 'fixture');
      final shownThenLanded = celOf(env.coordinator);

      expect(
        firstDifference(await laidInOneGo(tester), shownThenLanded),
        isNull,
      );
    });

    testWidgets('the hand resting on the stroke it shows lays nothing '
        'again', (tester) async {
      final env = await pumpPanel(tester, options: brushLine);

      final gesture = await press(tester, const Offset(50, 50));
      await moveTo(tester, gesture, const Offset(330, 250));
      await untilShown(tester, env.overlay);
      final shown = Map.of(env.overlay.tileImages);
      expect(shown, isNotEmpty, reason: '⛔premise');
      final laid = debugStrokeDabsLaid = <BrushDab>[];
      addTearDown(() => debugStrokeDabsLaid = null);
      await moveTo(tester, gesture, const Offset(330, 250));
      for (var frame = 0; frame < 10; frame += 1) {
        await tester.pump();
      }
      expect(laid, isEmpty, reason: 'nothing laid again');
      expect(env.overlay.tileImages, shown, reason: 'the very same pictures');
      await gesture.up();
      await tester.pump();
    });

    testWidgets('a cancelled drag takes back what it showed and lands '
        'nothing', (tester) async {
      final env = await pumpPanel(tester, options: brushLine);
      final steps = env.history.undoCount;

      final gesture = await press(tester, const Offset(50, 50));
      await moveTo(tester, gesture, const Offset(330, 250));
      await untilShown(tester, env.overlay);
      expect(env.overlay.hasStrokeContent, isTrue, reason: '⛔premise');
      await gesture.cancel();
      await tester.pump();

      expect(env.overlay.hasStrokeContent, isFalse);
      expect(alphaAt(env.coordinator, 50, 50), 0);
      expect(env.history.undoCount, steps);
    });

    // The overlay shows ONE shape. A stroke shown leaves its dabs on it and
    // an area shown leaves none, which is how the two pins below tell what
    // came up.

    testWidgets('turned 「일반」 mid-drag, the stroke being laid goes and the '
        'line\'s own area comes up, and lands', (tester) async {
      shapeShowFrameShare = Duration.zero;
      final env = await pumpPanel(tester, options: brushLine);
      final before = celOf(env.coordinator);

      final gesture = await press(tester, const Offset(50, 50));
      await moveTo(tester, gesture, const Offset(330, 250));
      await tester.pump(); // the stroke started, none of it shown
      expect(env.overlay.hasStrokeContent, isFalse, reason: '⛔premise');
      env.brush.value = env.brush.value.copyWith(shapeOptions: plain);
      await tester.pump();
      var strokeShown = false;
      void watch() => strokeShown |= env.overlay.dabs.isNotEmpty;
      env.overlay.addListener(watch);
      addTearDown(() => env.overlay.removeListener(watch));
      await moveTo(tester, gesture, const Offset(330.25, 250.25));
      await moveTo(tester, gesture, const Offset(330, 250));
      for (var frame = 0; frame < 200; frame += 1) {
        await tester.pump();
      }
      expect(strokeShown, isFalse, reason: 'the stroke went');
      expect(env.overlay.hasStrokeContent, isTrue, reason: 'the area shows');

      await gesture.up();
      await tester.pump();
      expect(
        firstDifference(
          celOf(env.coordinator),
          laidStraight(before, 330, 250),
        ),
        isNull,
        reason: 'the plain line alone — nothing of the stroke landed',
      );
    });

    testWidgets('turned to the brush mid-drag, the area being laid goes and '
        'the stroke comes up, and lands', (tester) async {
      shapeShowFrameShare = Duration.zero;
      final env = await pumpPanel(tester);

      final gesture = await press(tester, const Offset(50, 50));
      await moveTo(tester, gesture, const Offset(330, 250));
      await tester.pump(); // a piece of the area laid, none shown
      expect(env.overlay.hasStrokeContent, isFalse, reason: '⛔premise');
      env.brush.value = env.brush.value.copyWith(shapeOptions: brushLine);
      await tester.pump();
      var areaShown = false;
      void watch() => areaShown |=
          env.overlay.hasStrokeContent && env.overlay.dabs.isEmpty;
      env.overlay.addListener(watch);
      addTearDown(() => env.overlay.removeListener(watch));
      await moveTo(tester, gesture, const Offset(330.25, 250.25));
      await moveTo(tester, gesture, const Offset(330, 250));
      await untilShown(tester, env.overlay);
      expect(areaShown, isFalse, reason: 'the area went');
      expect(env.overlay.dabs, isNotEmpty, reason: 'the stroke shows');

      await gesture.up();
      await tester.pump();
      final shownThenLanded = celOf(env.coordinator);
      expect(
        firstDifference(await laidInOneGo(tester), shownThenLanded),
        isNull,
      );
    });
  });
}

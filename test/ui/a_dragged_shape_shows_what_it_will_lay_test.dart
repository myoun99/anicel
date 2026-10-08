import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
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
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/plain_line_region.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
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
    })
  >
  pumpPanel(WidgetTester tester) async {
    final keys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: keys,
      canvasSize: size,
    );
    final history = HistoryManager();
    final overlay = ActiveStrokeOverlayModel();
    addTearDown(overlay.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: coordinator,
            canvasSize: size,
            availableFrameKeys: keys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            historyManager: history,
            brushToolState: ValueNotifier(
              BrushToolState.defaults.copyWith(
                tool: CanvasTool.shape,
                drawShape: CanvasShapeKind.rect,
                shapeOptions: plain,
              ),
            ),
            selectionCommands: CanvasSelectionCommands(),
            viewport: seedFromRender(tester, CanvasViewport()),
            activeStrokeOverlayModel: overlay,
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
    );
    await tester.pump();
    return (coordinator: coordinator, history: history, overlay: overlay);
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
  /// shown first.
  BitmapSurface laidStraight(BitmapSurface base, double right, double bottom) {
    final region = plainLineRegion(
      points: CanvasSelectionShape.rect(
        left: 50,
        top: 50,
        right: right,
        bottom: bottom,
      ).points,
      closed: true,
      width: plain.size,
      corners: plain.corners,
    )!;
    return brushCommitResultForBrushDabSequenceOnBitmapSurface(
      surface: base,
      sequence: BrushDabSequence(
        buildRegionFillDabs(
          region: region,
          color: BrushToolState.defaults.color,
          opacity: plain.opacity,
          options: const FloodFillOptions(expandPx: 0, antiAlias: false),
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

  testWidgets('a shape is shown WHOLE or not at all: one piece a frame, the '
      'overlay stays as it was until the last is laid', (tester) async {
    shapeShowFrameShare = Duration.zero;
    final env = await pumpPanel(tester);

    final gesture = await press(tester, const Offset(50, 50));
    await moveTo(tester, gesture, const Offset(330, 250));
    var frames = 0;
    while (!env.overlay.hasStrokeContent) {
      await tester.pump();
      frames += 1;
      expect(frames, lessThan(40), reason: 'it comes up');
    }
    // The rectangle's outline crosses three rows of tiles: a piece for the
    // top row, two for each side row, one for the bottom — never all in
    // one frame when a frame lays one.
    expect(frames, greaterThan(2), reason: 'it took a frame a piece');
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
    await moveTo(tester, gesture, const Offset(330, 250));
    await tester.pump(); // one piece laid
    expect(env.overlay.hasStrokeContent, isFalse, reason: '⛔premise');
    await gesture.up();
    await tester.pump();

    expect(
      firstDifference(celOf(env.coordinator), laidStraight(before, 330, 250)),
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
}

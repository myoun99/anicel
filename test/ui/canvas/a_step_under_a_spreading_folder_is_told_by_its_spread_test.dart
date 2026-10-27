import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/services/guide_geometry.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

/// 🚨A STEP UNDER A FOLDER OR AN ADJUSTMENT THAT SPREADS IS TOLD BY ITS
/// SPREAD — where it moved, grown by as far as each chain it passes
/// through reads past a pixel, the row's own chain among them — and a step
/// on a row posed is not told at all ([StackedFrame.movedSince]): a canvas
/// that stands patches the first into its picture and draws the frame as it
/// stands for the second (one-picture-per-frame, 유저 2026-10-25 「원본 기준
/// 위에서 푼다」). ↩️A spread anywhere over the row was not told, and the
/// row's own until it read its spread off the canvas's grid
/// (nested-folder-buffers-read-past-the-view-Q1 = c).
///
/// The width is asserted, not that a rect came: a rect that is not grown
/// by the spread still comes, and patches a step whose blur it cuts.
void main() {
  // 24×8 at tile size 8: the dab's tile is 8 wide.
  const canvasSize = CanvasSize(width: 24, height: 8);
  final blur = [
    ResolvedLayerEffect(kind: EffectKind.blur, values: [4, 4]),
  ];

  BrushDab dabAt(double x) => BrushDab(
    center: CanvasPoint(x: x, y: 4),
    color: 0xFF000000,
    size: 3,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: 0,
  );

  /// What [nodes] say of a dab in the first tile, the live row drawn where
  /// [nodes] stand it.
  Future<({bool located, Rect? dirty})> aDabUnder(
    WidgetTester tester,
    List<CompositeNode<CanvasStackRow>> nodes,
  ) async {
    final overlay = ActiveStrokeOverlayModel(tileSize: 8);
    addTearDown(overlay.dispose);
    final rasterizer = BrushLiveStrokeRasterizer(
      pasteboard: canvasSize.pasteboardAt(PasteboardReach.whole),
    );
    final frame = stackedFrameOf(
      nodes,
      page: (
        canvasSize: canvasSize,
        pasteboardReach: PasteboardReach.whole,
        paintPaper: true,
        paperBackground: const ProjectBackground.color(0xFF00FF00),
      ),
      surfaceOf: (_) => null,
      live: (
        rows: (
          activeSurfacePainter: BitmapSurfacePainter(
            surface: BitmapSurface(
              canvasSize: canvasSize,
              tileSize: 8,
              tiles: {
                for (var x = 0; x < 3; x += 1)
                  TileCoord(x: x, y: 0): BitmapTile.blank(size: 8),
              },
            ),
            overlayModel: overlay,
            showTransparentBackground: false,
          ),
          floatOverlay: null,
          liftedRows: const {},
        ),
        painters: LiftedRowPainters(),
      ),
    );
    final before = frame.tokens;
    expect(before, isNotNull, reason: '⛔premise: the live row is in hand');
    await tester.runAsync(() async {
      rasterizer.blendFrom([dabAt(2)], from: 0);
      overlay.updateRegion(
        source: rasterizer,
        region: DirtyRegion.fromXYWH(x: 0, y: 2, width: 5, height: 5),
      );
    });
    final moved = frame.movedSince(before!);
    return (located: moved.located, dirty: moved.dirty);
  }

  CompositeNode<CanvasStackRow> row({
    GuideTransform? placement,
    List<ResolvedLayerEffect> effects = const [],
  }) => CompositeLeaf<CanvasStackRow>(
    CanvasActiveLayerRow(opacity: 1, placement: placement, effects: effects),
  );

  CompositeNode<CanvasStackRow> blurredFolder(
    List<CompositeNode<CanvasStackRow>> children,
  ) => CompositeGroup<CanvasStackRow>(
    children: children,
    opacity: 1,
    blendMode: LayerBlendMode.normal,
    effects: blur,
  );

  testWidgets('a row alone: its tile and the hairline', (tester) async {
    final moved = await aDabUnder(tester, [row()]);
    expect(moved.located, isTrue);
    expect(moved.dirty, const Rect.fromLTRB(-1, -1, 9, 9));
  });

  testWidgets('a row in a blurred folder: grown by the folder\'s blur', (
    tester,
  ) async {
    final moved = await aDabUnder(tester, [
      blurredFolder([row()]),
    ]);
    expect(moved.located, isTrue);
    expect(
      moved.dirty,
      const Rect.fromLTRB(-5, -5, 13, 13),
      reason: 'the 8-wide tile, the blur\'s 4 on each side and the hairline',
    );
  });

  testWidgets('a row in a blurred folder in a blurred folder: grown by both',
      (tester) async {
    final moved = await aDabUnder(tester, [
      blurredFolder([
        blurredFolder([row()]),
      ]),
    ]);
    expect(moved.located, isTrue);
    expect(moved.dirty, const Rect.fromLTRB(-9, -9, 17, 17));
  });

  testWidgets('a row under a blurring adjustment: grown by its blur', (
    tester,
  ) async {
    final moved = await aDabUnder(tester, [
      CompositeAdjustment<CanvasStackRow>(
        children: [row()],
        effects: blur,
        mix: 1,
      ),
    ]);
    expect(moved.located, isTrue);
    expect(moved.dirty, const Rect.fromLTRB(-5, -5, 13, 13));
  });

  testWidgets('⛔a posed row is not told', (tester) async {
    final moved = await aDabUnder(tester, [
      row(placement: const GuideTransform(1, 0, 0, 1, 3, 0)),
    ]);
    expect(moved.located, isFalse);
  });

  testWidgets('a row that blurs of its own: grown by its own blur', (
    tester,
  ) async {
    final moved = await aDabUnder(tester, [row(effects: blur)]);
    expect(moved.located, isTrue);
    expect(moved.dirty, const Rect.fromLTRB(-5, -5, 13, 13));
  });

  testWidgets('a row that blurs of its own in a blurred folder: grown by '
      'both', (tester) async {
    final moved = await aDabUnder(tester, [
      blurredFolder([row(effects: blur)]),
    ]);
    expect(moved.located, isTrue);
    expect(moved.dirty, const Rect.fromLTRB(-9, -9, 17, 17));
  });
}

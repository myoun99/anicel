import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

/// 🚨THE DIRTY RECT IS THE DAB, NOT THE STROKE.
///
/// The overlay's tile map ACCUMULATES for the stroke's whole life —
/// nothing leaves it until pen-up — so a dirty pass that unioned "every
/// overlay coordinate" was re-compositing the whole stroke's bounding box
/// on every step: by the third dab of a long line, the patch had quietly
/// grown back into the full-width recomposite the patch exists to avoid.
/// A count of patches cannot see this — a bloated patch still counts as
/// one patch — which is why this test asserts on WIDTH, not on whether a
/// patch happened.
///
/// The fix is identity per coordinate, exactly like the committed-tile
/// loop next to it: the overlay replaces a tile's IMAGE only when a dab
/// touched it, so an unchanged image object is "this tile did not move".
/// The rect is what a canvas that stands patches into its picture
/// ([StackedFrame.movedSince]). ↩️It was read off the canvas's display
/// buffer (`DisplayBufferCache.lastDirtyRect`), until nothing kept one
/// (one-picture-per-frame ②-5a).
void main() {
  // 24×8 at tile size 8: three tile columns, so "the stroke so far" and
  // "the newest dab" live in visibly different rects.
  const canvasSize = CanvasSize(width: 24, height: 8);

  BitmapSurface committedSurface() {
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: 8,
      tiles: {
        for (var x = 0; x < 3; x += 1)
          TileCoord(x: x, y: 0): BitmapTile.blank(
            size: 8,
          ),
      },
    );
  }

  BrushDab dabAt(double x, {int sequence = 0}) => BrushDab(
    center: CanvasPoint(x: x, y: 4),
    color: 0xFF000000,
    size: 3,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: sequence,
  );

  testWidgets('the second dab dirties its own tile, not the whole stroke', (
    tester,
  ) async {
    final overlay = ActiveStrokeOverlayModel(tileSize: 8);
    addTearDown(overlay.dispose);
    final rasterizer = BrushLiveStrokeRasterizer(
      pasteboard: canvasSize.pasteboardAt(PasteboardReach.whole),
    );
    final frame = stackedFrameOf(
      const [CompositeLeaf<CanvasStackRow>(CanvasActiveLayerRow(opacity: 1))],
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
            surface: committedSurface(),
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
    expect(before, isNotNull, reason: '⛔premise: the live row can be told');

    // Dab 1 lands in tile 0.
    await tester.runAsync(() async {
      rasterizer.blendFrom([dabAt(2)], from: 0);
      overlay.updateRegion(
        source: rasterizer,
        region: DirtyRegion.fromXYWH(x: 0, y: 2, width: 5, height: 5),
      );
    });
    final first = frame.movedSince(before!);
    expect(first.located, isTrue);
    expect(first.dirty, isNotNull, reason: 'the dab moved the live row');
    // ⛔THE RECT IS INFLATED BY ONE PIXEL, and that is not decoration: a
    // dab writes whole texels but the composite around it need not land on
    // them — a posed sibling or a rounded edge can put ink a fraction over
    // the line, and a patch trusting the exact rect leaves a hairline of
    // the previous frame.
    // 🚨MEASURED, BOTH WAYS (2026-09-04): the dab's tile is 8 wide and
    // this rect is 10 — one pixel added on each side. A `greaterThan(8)`
    // bound was the first try and it never failed, because the tile
    // already clears 8: a bound the mutation cannot cross pins nothing.
    // (Until 2026-09-17 the union was 24: the committed tiles' pictures
    // landed between the warm paints and this one, and a token that read
    // the picture called every tile dirty. A tile's token is the tile now
    // — its picture is made from its own bytes inside the paint.)
    expect(
      first.dirty!.width,
      10.0,
      reason:
          'the 8-wide tile plus the hairline inflate — an exact-rect '
          'patch leaves a line of the frame before along the dab',
    );

    // Dab 2 lands in tile 2 — the far end of the line. Tile 0's overlay
    // image is untouched by this step.
    await tester.runAsync(() async {
      rasterizer.blendFrom([dabAt(2), dabAt(21, sequence: 1)], from: 1);
      overlay.updateRegion(
        source: rasterizer,
        region: DirtyRegion.fromXYWH(x: 19, y: 2, width: 5, height: 5),
      );
    });
    final dirty = frame.movedSince(first.now!).dirty;
    expect(dirty, isNotNull, reason: 'the dab moved the live row');
    expect(
      dirty!.left,
      greaterThanOrEqualTo(15),
      reason:
          'tile 0 did not move, so the patch must not reach back into '
          'it — under the old union walk this rect spanned the whole '
          'stroke (left 0)',
    );
    expect(
      dirty.width,
      lessThanOrEqualTo(10),
      reason: 'one touched tile plus the hairline inflate',
    );
  });
}

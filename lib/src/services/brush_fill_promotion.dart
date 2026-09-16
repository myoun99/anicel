import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/brush_blend_mode.dart';
import '../models/brush_dab.dart';
import '../models/brush_dab_sequence.dart';
import '../models/frame_id.dart';
import '../models/layer_id.dart';
import 'brush_commit_builder.dart';
import 'brush_live_stroke_rasterizer.dart';
import 'canvas_selection_paint_clip.dart';
import 'canvas_selection_region.dart';

/// The stroke revision a promoted fill's tiles carry: a fill is one dab,
/// blended once, so there is exactly one revision to hand over at commit
/// ([ActiveStrokeOverlayModel.takeTileImageAt] compares it).
const int fillPromotionRevision = 1;

/// 🚨★★★A FILL IS A STROKE OF ONE DAB (유저 절대규칙 2026-09-17: 「보이는
/// 중이랑 결과랑 절대로 다르면 안 되」). The result tiles a fill tap will
/// land, made NOW by the commit's own function — the same clip the panel
/// runs on a stroke that arrives without live pixels, then
/// [brushCommitResultForBrushDabSequenceOnBitmapSurface] exactly as the
/// commit would call it — so what the screen shows before the commit IS
/// the commit, byte for byte and at every level (the tiles reach the
/// overlay as its pre-blended result tiles, and the commit installs these
/// very objects through `promotedTiles`, recomputing nothing).
///
/// 🪦R23 (2026-08) previewed a fill as ONE stamp image at its landing
/// rect, because blending it into live-raster tiles and re-decoding
/// thousands of them asynchronously stalled an 8K settle frame. That
/// image was reduced by nearest below 100% while the committed tiles are
/// exact box means (the level round), so the preview and the result
/// disagreed until the commit's decodes landed. Result tiles uploaded
/// synchronously (Impeller, every platform since 3.47) cost a tile's
/// upload each — tens of microseconds — and are the same pictures the
/// commit keeps, so nothing is decoded twice and nothing settles.
///
/// Empty when the fill lands nothing: wholly outside the selection, or a
/// no-op on these pixels.
List<PromotedStrokeTile> promoteFillDab({
  required BitmapSurface surface,
  required BrushDab dab,
  required BrushBlendMode blendMode,
  required CanvasSelectionRegion? selection,
  required LayerId layerId,
  required FrameId frameId,
}) {
  final clipped = selection == null
      ? null
      : clipDabsToSelection(
          dabs: [dab],
          canvasSize: surface.canvasSize,
          tileSize: surface.tileSize,
          region: selection,
        );
  if (selection != null && clipped == null) {
    return const [];
  }
  final result = brushCommitResultForBrushDabSequenceOnBitmapSurface(
    surface: surface,
    sequence: BrushDabSequence([dab]),
    layerId: layerId,
    frameId: frameId,
    prerasterizedStrokePixels: clipped?.pixels,
    prerasterizedStrokeBounds: clipped?.bounds,
    blendMode: blendMode,
  );
  if (!result.hasChanges) {
    return const [];
  }
  return [
    for (final coord in result.dirtyTiles.coords)
      PromotedStrokeTile(
        coord,
        // A coordinate the fill emptied (an erase) has no tile in the
        // result; a blank one says so, and the commit's put drops it
        // again ([BitmapSurface.putMaterializedTiles]).
        result.afterSurface.tileAt(coord) ??
            BitmapTile.blank(size: surface.tileSize),
        fillPromotionRevision,
      ),
  ];
}

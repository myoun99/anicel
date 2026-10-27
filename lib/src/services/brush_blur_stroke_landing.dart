import '../models/bitmap_surface.dart';
import '../models/brush_blend_mode.dart';
import '../models/brush_dab.dart';
import '../models/placed_tile.dart';
import 'brush_live_stroke_rasterizer.dart';
import 'canvas_selection_region.dart';

/// 🚨★★★I-75: A BLUR STROKE RE-DERIVED FROM ITS DABS IS LAID BY THE ONE
/// RASTERIZER THAT SHOWED IT — the commit when the cel moved under its
/// promotion, a selection's cut of it, 확정 laying it on another cel. A
/// blur has no stroke buffer to composite (`BrushBlurPicture`): what it
/// lands is the cel it found, rewritten dab by dab, so the only way to land
/// what the user watched is to run the same dabs through the same
/// `BrushLiveStrokeRasterizer` over [surface] — the cel as it stands now —
/// capped by [opacity] and [selection] exactly as the live stroke was.
///
/// The tiles that differ from [surface]; none when the stroke moved nothing.
List<PlacedTile> blurStrokeLandedOn(
  BitmapSurface surface,
  List<BrushDab> dabs, {
  required double opacity,
  CanvasSelectionRegion? selection,
}) {
  final rasterizer =
      BrushLiveStrokeRasterizer(
          pasteboard: surface.pasteboard,
          tileSize: surface.tileSize,
        )
        ..selectionRegion = selection
        ..strokeOpacity = opacity
        ..blurOver(surface);
  rasterizer.blendFrom(dabs);
  final promoted = rasterizer.promoteStrokeTiles(
    base: surface,
    // Neither is read by a blur: it lays no colour to blend or erase.
    mode: BrushBlendMode.color,
    erase: false,
  );
  rasterizer.clear();
  return [for (final entry in promoted) (coord: entry.coord, tile: entry.tile)];
}

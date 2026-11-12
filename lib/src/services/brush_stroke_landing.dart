import '../models/bitmap_surface.dart';
import '../models/brush_blend_mode.dart';
import '../models/brush_dab.dart';
import '../models/placed_tile.dart';
import 'brush_live_stroke_rasterizer.dart';
import 'selection_clip.dart';

/// 🚨★★★A STROKE THAT HAS NOTHING BUT ITS DABS IS LAID BY THE ONE RASTERIZER
/// THAT SHOWS A STROKE: [dabs] piled as the live stroke piles them
/// (`BrushLiveStrokeRasterizer`) and laid once over [surface] — the cel as
/// it stands now — in [mode], capped by [opacity] and [selection] exactly as
/// a live stroke is. So what lands is what a pen drawing the same dabs
/// would have shown, on whichever grid the surface is.
///
/// I-75: a BLUR stroke re-derived from its dabs — the commit when the cel
/// moved under its promotion, a selection's cut of it, 확정 laying it on
/// another cel. A blur has no stroke buffer to composite
/// (`BrushBlurPicture`): what it lands is the cel it found, rewritten dab by
/// dab, so the only way to land what the user watched is this one.
///
/// A run of brush dabs the engine lays (flip lane ⓒ,
/// `materializeBrushDabSequenceOnBitmapSurface` on the app's grid) comes
/// through here too, and each stroke of a vector layer an import draws
/// (`clipVectorTiles`), at the stroke's own opacity. ↩️Till 2026-11-12 the
/// blur had this to itself and the engine's run a copy with no ceiling and
/// no selection; the import's would have been the third.
///
/// The tiles that differ from [surface]; none when the stroke moved nothing.
List<PlacedTile> strokeLandedOn(
  BitmapSurface surface,
  List<BrushDab> dabs, {
  double opacity = 1,
  SelectionClip? selection,
  // Neither is read by a blur: it lays no colour to blend or erase.
  BrushBlendMode mode = BrushBlendMode.color,
  bool erase = false,
}) {
  final rasterizer =
      BrushLiveStrokeRasterizer(
          pasteboard: surface.pasteboard,
          tileSize: surface.tileSize,
        )
        ..selectionClip = selection
        ..strokeOpacity = opacity;
  if (dabs.firstOrNull?.blurs ?? false) {
    rasterizer.blurOver(surface);
  }
  try {
    rasterizer.blendFrom(dabs, from: 0);
    return [
      for (final promoted in rasterizer.promoteStrokeTiles(
        base: surface,
        mode: mode,
        erase: erase,
      ))
        (coord: promoted.coord, tile: promoted.tile),
    ];
  } finally {
    rasterizer.clear();
  }
}

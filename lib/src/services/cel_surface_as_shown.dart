import 'dart:typed_data';

import '../models/bitmap_surface.dart';
import '../models/cel_text.dart';
import '../models/dirty_region.dart';
import '../models/layer_effect.dart';
import 'bitmap_surface_geometry.dart'
    show bitmapSurfaceContentBounds, celTextPlateSurface;
import 'brush_stroke_blend.dart' show bitmapSurfaceRegionPixels;
import 'cel_source_effect_pass.dart';
import 'cel_text_laying.dart';

/// THE SEAM A CEL'S PICTURE CROSSES ON ITS WAY TO BEING SHOWN: the tiles a
/// row draws for [surface] under its effect chain [effects].
///
/// Two things are computed over a cel's own bytes before anything is drawn,
/// and their order is the order they exist in: the texts are part of the
/// picture ([celSurfaceWithTextsLaid]), and the colour keys are a filter
/// over that picture ([celSurfaceWithSourceEffects]) — so a key names a
/// letter's colour exactly as it names a drawn line's.
///
/// 🚨★★★EVERY ROUTE THAT DRAWS A CEL COMES THROUGH HERE — the shared plan
/// (`CutFrameCompositeLayer`: playback, export, the camera), the editing
/// stack's row images (`LayerFrameImageCache`), the row being drawn on and
/// the conte's live picture. A route that took the keys' pass alone would
/// show a cel without its texts, which is why the keys' pass is not called
/// from anywhere else (`a_cel_is_shown_through_one_seam_test`).
///
/// Pass `const []` where the row has no chain.
BitmapSurface celSurfaceAsShown(
  BitmapSurface surface,
  List<ResolvedLayerEffect> effects,
) => celSurfaceWithSourceEffects(celSurfaceWithTextsLaid(surface), effects);

/// THE SEAM, WHERE A TEXT A HAND CARRIES WILL LAND (F-344-Q3): the region
/// of its cel the carried text's ink covers, and the straight rgba the cel
/// will show there once it lands — a row the region's width. Null when it
/// holds no ink: the cel then shows the same with it and without it.
///
/// [under] is the cel without the text carried and without the texts
/// [above] it, which are over it in their order.
///
/// 🗣️유저 2026-10-15 (F-344-Q3): 「놓을 때와 같은 코드로 — 완전히 같게」. A
/// text floated over its cel is keyed by itself on a row with a colour
/// key, where its landing keys it with the ink under it. This is the
/// landing, asked where the text lies: [under] laid as [celSurfaceAsShown]
/// lays it, the carried plate and then the texts above it stamped over that
/// with the stamp a cel's texts are laid with ([layPixelsOverRegion]), and
/// the keys over all of it by the walk they take over a tile
/// ([celSourceEffectsOverStraight]) — each a pixel's own answer, so the
/// bytes are the landed cel's there. Outside the region the text holds no
/// ink, and the cel without it is the cel with it.
({DirtyRegion region, Uint8List straight})? celTextLandingAsShown({
  required BitmapSurface under,
  required CelTextPixels carried,
  required List<CelText> above,
  required List<ResolvedLayerEffect> effects,
}) {
  final region = _landingRegion(under, carried);
  if (region == null) {
    return null;
  }
  final straight = bitmapSurfaceRegionPixels(
    celSurfaceWithTextsLaid(under),
    region,
  );
  layPixelsOverRegion(straight, region, carried, on: under);
  for (final text in above) {
    layPixelsOverRegion(
      straight,
      region,
      (plate: text.plate, dx: 0, dy: 0),
      on: under,
    );
  }
  celSourceEffectsOverStraight(straight, effects);
  return (region: region, straight: straight);
}

/// The box round every pixel of [carried]'s plate that holds ink, where a
/// hand has it — on [on]'s grid. Null when it holds none.
DirtyRegion? _landingRegion(BitmapSurface on, CelTextPixels carried) {
  final ink = bitmapSurfaceContentBounds(
    celTextPlateSurface(
      carried.plate,
      canvasSize: on.canvasSize,
      tileSize: on.tileSize,
    ),
  );
  if (ink == null) {
    return null;
  }
  return DirtyRegion(
    left: ink.left + carried.dx,
    top: ink.top + carried.dy,
    rightExclusive: ink.rightExclusive + carried.dx,
    bottomExclusive: ink.bottomExclusive + carried.dy,
  );
}

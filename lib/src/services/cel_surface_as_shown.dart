import 'dart:typed_data';

import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/cel_text.dart';
import '../models/dirty_region.dart';
import 'bitmap_surface_geometry.dart'
    show bitmapSurfaceContentBounds, celTextPlateSurface;
import 'brush_stroke_blend.dart' show bitmapSurfaceRegionPixels;
import 'cel_text_laying.dart';

/// THE SEAM, AT ONE COORDINATE: what a cel whose drawing holds [tile] there
/// SHOWS there — [plates], the texts standing over the coordinate bottom →
/// top (`celTextPlatesOver`; null where none does), laid over it. The very
/// object [celSurfaceWithTextsLaid] holds at that coordinate once the cel
/// holds [tile] — the laying answers a tile it has seen from its memo — so
/// a picture made for one is the other's.
///
/// A live stroke's overlay shows its pictures in place of the cel's tiles,
/// and pen-up hands each to the tile this answers
/// (`ActiveStrokeOverlayModel.tileShownFor`).
BitmapTile celTileAsShown(
  BitmapTile tile,
  List<BitmapTile>? plates,
  int tileSize,
) => plates == null ? tile : celTileWithPlatesLaid(tile, plates, tileSize)!;

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
/// landing, asked where the text lies: [under] laid as
/// [celSurfaceWithTextsLaid] lays it, the carried plate and then the texts
/// above it stamped over that with the stamp a cel's texts are laid with
/// ([layPixelsOverRegion]) — the landed cel's bytes there, which the row's
/// chain then runs over with the cel's, as it runs over the landed cel.
/// Outside the region the text holds no ink, and the cel without it is the
/// cel with it.
///
/// ↩️On a row whose chain ran a plugin at its head, the landing was the
/// whole cel through it, made here on the CPU (🗣️I-132-Q32 b) — until the
/// plugin was a step of the row's chain (float-warp-resamples-in-the-c-
/// engine (2), 2026-11-11), which runs over the landing with the cel.
({DirtyRegion region, Uint8List straight})? celTextLandingAsShown({
  required BitmapSurface under,
  required CelTextPixels carried,
  required List<CelText> above,
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
  return (region: region, straight: straight);
}

/// The box round every pixel of [carried]'s plate that holds ink, where a
/// hand has it — on [on]'s grid. Null when it holds none.
DirtyRegion? _landingRegion(BitmapSurface on, CelTextPixels carried) {
  final ink = bitmapSurfaceContentBounds(
    celTextPlateSurface(
      carried.plate,
      canvasSize: on.canvasSize,
      pasteboardReach: on.pasteboardReach,
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

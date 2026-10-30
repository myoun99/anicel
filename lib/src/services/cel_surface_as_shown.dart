import 'dart:typed_data';

import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/cel_text.dart';
import '../models/dirty_region.dart';
import '../models/layer_effect.dart';
import '../models/tile_coord.dart';
import 'bitmap_surface_geometry.dart'
    show bitmapSurfaceContentBounds, celTextPlateMoved, celTextPlateSurface;
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

/// THE SEAM, AT ONE COORDINATE: what a cel whose drawing holds [tile] there
/// SHOWS there — [plates], the texts standing over the coordinate bottom →
/// top (`celTextPlatesOver`; null where none does), laid over it, then the
/// colour keys of [effects]. The very object [celSurfaceAsShown] holds at
/// that coordinate once the cel holds [tile] — each pass answers a tile it
/// has seen from its memo — so a picture made for one is the other's.
///
/// A live stroke's overlay shows its pictures in place of the cel's tiles,
/// and pen-up hands each to the tile this answers
/// (`ActiveStrokeOverlayModel.tileShownFor`).
BitmapTile celTileAsShown(
  BitmapTile tile,
  List<BitmapTile>? plates,
  List<ResolvedLayerEffect> effects,
  int tileSize,
) => celTileWithSourceEffects(
  plates == null ? tile : celTileWithPlatesLaid(tile, plates, tileSize)!,
  effects,
  tileSize,
);

/// [celTileAsShown] over one tile's bytes that are not a tile yet:
/// [straight], straight rgba written IN PLACE — a live stroke's result,
/// shown in place of the cel's tile until the pen comes up. Equal to the
/// last byte to what [celTileAsShown] makes of the tile they become: the
/// laying ends in the same stamp, and the keys walk each pixel as they walk
/// a tile's.
void celStraightTileAsShown(
  Uint8List straight,
  List<BitmapTile>? plates,
  List<ResolvedLayerEffect> effects,
  int tileSize,
) {
  if (plates != null) {
    layPlatesOverStraight(straight, plates, tileSize);
  }
  celSourceEffectsOverStraight(straight, effects);
}

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
  if (celSourcePlugin(effects) != null) {
    // The cel under the hand is drawn with the texts above the carried one
    // still on it.
    return celLandingShownWhole(
      under: under.withTexts([...under.texts, ...above]),
      landed: _textLanded(under, carried, above),
      effects: effects,
    );
  }
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

/// THE SEAM, WHERE WHAT A HAND CARRIES WILL LAND ON A ROW WHOSE CHAIN RUNS
/// A PLUGIN (🗣️I-132-Q32 b): the plugin may change the cel anywhere, so the
/// landing's picture is the whole cel as it will show once [landed] stands
/// in place of [under] — over every pixel either shows, so it covers the
/// cel under the hand wherever that is drawn. Null where neither shows any.
({DirtyRegion region, Uint8List straight})? celLandingShownWhole({
  required BitmapSurface under,
  required BitmapSurface landed,
  required List<ResolvedLayerEffect> effects,
}) {
  final shown = celSurfaceAsShown(landed, effects);
  DirtyRegion? box;
  for (final picture in [celSurfaceAsShown(under, effects), shown]) {
    final size = picture.tileSize;
    for (final coord in picture.tiles.keys) {
      final tile = DirtyRegion(
        left: coord.x * size,
        top: coord.y * size,
        rightExclusive: (coord.x + 1) * size,
        bottomExclusive: (coord.y + 1) * size,
      );
      box = box?.union(tile) ?? tile;
    }
  }
  final region = box?.intersection(
    DirtyRegion.wholePixelsOf(under.storableRect),
  );
  return region == null
      ? null
      : (region: region, straight: bitmapSurfaceRegionPixels(shown, region));
}

/// [under] with [carried] landed on it and [above] over that, laid as a
/// cel's texts are ([celTileWithPlatesLaid]) — what [celTextLandingAsShown]
/// stamps over a region, over the whole cel.
BitmapSurface _textLanded(
  BitmapSurface under,
  CelTextPixels carried,
  List<CelText> above,
) {
  final laid = celSurfaceWithTextsLaid(under);
  final plates = <TileCoord, List<BitmapTile>>{};
  void add(Map<TileCoord, BitmapTile> plate) {
    for (final MapEntry(key: coord, value: tile) in plate.entries) {
      (plates[coord] ??= []).add(tile);
    }
  }

  add(
    celTextPlateMoved(
      carried,
      canvasSize: under.canvasSize,
      pasteboardReach: under.pasteboardReach,
      tileSize: under.tileSize,
    ),
  );
  for (final text in above) {
    add(text.plate);
  }
  return laid.withRebuiltTiles({
    for (final MapEntry(key: coord, value: over) in plates.entries)
      coord: ?celTileWithPlatesLaid(laid.tileAt(coord), over, under.tileSize),
  });
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

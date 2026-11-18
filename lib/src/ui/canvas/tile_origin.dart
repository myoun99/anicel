import 'dart:ui' show Offset, Rect;

import '../../models/bitmap_surface.dart';
import '../../models/bitmap_tile.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/placed_tile.dart';
import '../../models/tile_coord.dart';
import '../../services/cel_text_laying.dart';

/// Where [placed]'s top-left corner sits in canvas space: the ONE place the
/// tile-coordinate-times-size product is turned into an [Offset] for a
/// draw (the surface paint pass, the painter's rects).
/// Coordinates may be negative — the pasteboard's tiles are.
///
/// ⚠️It takes the PAIR, not the tile: a tile does not know where it sits.
/// Its place is the map key it was stored under, and [PlacedTile] is how
/// that travels alongside it.
Offset tileOriginOffset(PlacedTile placed) =>
    tileCoordOriginOffset(placed.coord, placed.tile.size);

/// Where the tile at [coord] on a [tileSize] grid has its top-left corner
/// in canvas space — the product itself, for a draw that has a coordinate
/// and a grid but no tile: the live stroke's picture of a coordinate it
/// holds no tile at. ↩️A level tile, drawn at its block's origin on the
/// block's grid, too (4c, 2026-09-16), until one-picture-per-frame ②-5b-2.
Offset tileCoordOriginOffset(TileCoord coord, int tileSize) => Offset(
  (coord.x * tileSize).toDouble(),
  (coord.y * tileSize).toDouble(),
);

/// The canvas-space bounds of the tiles at [coords] on a [tileSize] grid, or
/// null when there are none. Integer-aligned by construction.
///
/// 🚨ONE UNION OF TILE RECTS (review 2026-09-15). A surface's content
/// (`surfaceContentWorldRect`), what the surface painter's live overlay
/// covers, the knee's flat projection (gone 2026-09-16) and a buffer
/// patch's dirty tiles each walked their coordinates and unioned the rects
/// by hand — one
/// in integers, the rest in doubles — and the painter's own tiles were about
/// to become one more.
Rect? tileCoordsWorldRect(Iterable<TileCoord> coords, int tileSize) {
  final walk = coords.iterator;
  if (!walk.moveNext()) {
    return null;
  }
  var left = walk.current.x;
  var top = walk.current.y;
  var right = left;
  var bottom = top;
  while (walk.moveNext()) {
    final coord = walk.current;
    if (coord.x < left) left = coord.x;
    if (coord.x > right) right = coord.x;
    if (coord.y < top) top = coord.y;
    if (coord.y > bottom) bottom = coord.y;
  }
  return Rect.fromLTRB(
    (left * tileSize).toDouble(),
    (top * tileSize).toDouble(),
    ((right + 1) * tileSize).toDouble(),
    ((bottom + 1) * tileSize).toDouble(),
  );
}

/// The tiles every rect below is measured from: [surface]'s picture as
/// shown — its drawing with the texts it carries laid over it
/// (`celSurfaceWithTextsLaid`).
///
/// 🚨★★★A PICTURE'S RECT CANNOT BE MEASURED WITHOUT ITS TEXTS (R9-rest,
/// 유저 2026-10-06: 「셀의 그림이랑 정확히 동일」): a text that reaches past
/// the drawing grows the rect exactly as a stroke there would. A surface
/// that carries no text comes back as the object it was.
Map<TileCoord, BitmapTile> _tilesShownBy(BitmapSurface surface) =>
    celSurfaceWithTextsLaid(surface).tiles;

/// The canvas rect UNIONED with every stored tile's rect — the extent of a
/// surface's content, pasteboard and all. Integer-aligned by construction.
Rect surfaceContentWorldRect(BitmapSurface surface) {
  final canvas = surface.canvasSize.canvasRect;
  final tiles = tileCoordsWorldRect(
    _tilesShownBy(surface).keys,
    surface.tileSize,
  );
  return tiles == null ? canvas : canvas.expandToInclude(tiles);
}

/// The part of [surfaceContentWorldRect] that holds the stored tiles —
/// where every pixel of the surface that is not transparent sits: the
/// tiles' rect, which the content holds.
///
/// ↩️It was pushed out to multiples of 4 counted from the content's
/// origin (the deepest playback level), so that at every level of the
/// display's pyramid its edges fell on whole texels of the whole content's
/// level — until no picture was halved (one-picture-per-frame ②-5b-3).
Rect surfaceInkWorldRect(BitmapSurface surface) =>
    tileCoordsWorldRect(_tilesShownBy(surface).keys, surface.tileSize) ??
    surfaceContentWorldRect(surface);

import 'dart:ui' show Offset, Rect;

import '../../models/placed_tile.dart';
import '../../models/tile_coord.dart';

/// Where [placed]'s top-left corner sits in canvas space: the ONE place the
/// tile-coordinate-times-size product is turned into an [Offset] for a
/// draw (the surface paint pass, the tiled compose, the provisional
/// pictures, the painter's rects). Coordinates may be negative — the
/// pasteboard's tiles are.
///
/// ⚠️It takes the PAIR, not the tile: a tile does not know where it sits.
/// Its place is the map key it was stored under, and [PlacedTile] is how
/// that travels alongside it.
Offset tileOriginOffset(PlacedTile placed) => Offset(
  (placed.coord.x * placed.tile.size).toDouble(),
  (placed.coord.y * placed.tile.size).toDouble(),
);

/// The canvas-space bounds of the tiles at [coords] on a [tileSize] grid, or
/// null when there are none. Integer-aligned by construction.
///
/// 🚨ONE UNION OF TILE RECTS (review 2026-09-15). A surface's content
/// (`surfaceContentWorldRect`), what the surface painter's live overlay
/// covers, the flat projection's ink bounds and a buffer patch's dirty
/// tiles each walked their coordinates and unioned the rects by hand — one
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

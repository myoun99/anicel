import 'dart:ui' show Offset;

import '../../models/placed_tile.dart';

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

import 'dart:ui' show Offset;

import '../../models/bitmap_tile.dart';

/// Where [tile]'s top-left corner sits in canvas space: the ONE place the
/// tile-coordinate-times-size product is turned into an [Offset] for a
/// draw (the surface paint pass, the tiled compose, the provisional
/// pictures, the painter's rects). Coordinates may be negative — the
/// pasteboard's tiles are.
Offset tileOriginOffset(BitmapTile tile) => Offset(
  (tile.coord.x * tile.size).toDouble(),
  (tile.coord.y * tile.size).toDouble(),
);

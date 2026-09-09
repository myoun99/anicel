import 'bitmap_surface.dart';
import 'bitmap_tile.dart';
import 'dirty_region.dart';
import 'tile_coord.dart';

/// One tile a region touches: the tile itself, where its top-left sits in
/// world pixels, and the part of the region that lands inside it (right
/// and bottom exclusive, world coordinates).
typedef CoveredTile = ({
  TileCoord coord,
  BitmapTile tile,
  int worldLeft,
  int worldTop,
  int left,
  int top,
  int rightExclusive,
  int bottomExclusive,
});

/// Every EXISTING tile [region] touches, row by row.
///
/// The tile box comes from [DirtyRegion.tileRange] — the floorDiv-not-`~/`
/// law for negative pasteboard coordinates lives in [tileAxisSpan], once.
///
/// ⛔MISSING TILES ARE SKIPPED, not treated as transparent: the surface is
/// sparse, an absent tile has no bytes, and every caller has to skip it
/// the same way or read past the end of a buffer that was never made.
Iterable<CoveredTile> tilesCovering(
  BitmapSurface surface,
  DirtyRegion region,
) sync* {
  final tileSize = surface.tileSize;
  final (:firstX, :lastX, :firstY, :lastY) = region.tileRange(
    tileSize: tileSize,
  );
  for (var ty = firstY; ty <= lastY; ty += 1) {
    final worldTop = ty * tileSize;
    for (var tx = firstX; tx <= lastX; tx += 1) {
      final coord = TileCoord(x: tx, y: ty);
      final tile = surface.tileAt(coord);
      if (tile == null) {
        continue;
      }
      final worldLeft = tx * tileSize;
      yield (
        coord: coord,
        tile: tile,
        worldLeft: worldLeft,
        worldTop: worldTop,
        left: region.left > worldLeft ? region.left : worldLeft,
        top: region.top > worldTop ? region.top : worldTop,
        rightExclusive: region.rightExclusive < worldLeft + tileSize
            ? region.rightExclusive
            : worldLeft + tileSize,
        bottomExclusive: region.bottomExclusive < worldTop + tileSize
            ? region.bottomExclusive
            : worldTop + tileSize,
      );
    }
  }
}

import 'bitmap_surface.dart';
import 'bitmap_tile.dart';
import 'dirty_region.dart';
import 'tile_coord.dart';

/// One tile a region touches: the tile itself, where its top-left sits in
/// world pixels, and the part of the region that lands inside it (right
/// and bottom exclusive, world coordinates).
typedef CoveredTile = ({
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
/// The range is [tileRangeCoveringPixels] — the one place that says why it
/// floors rather than truncates.
///
/// ⛔MISSING TILES ARE SKIPPED, not treated as transparent: the surface is
/// sparse, an absent tile has no bytes, and every caller has to skip it
/// the same way or read past the end of a buffer that was never made.
///
/// ⚠️ `tileAt`, NOT `surface.tiles[...]`. The `tiles` getter is
/// `Map.unmodifiable(_tiles)` — it copies the WHOLE map, and this is the
/// inner line of a nested loop over every tile the fill touches. Measured
/// at 82.7 ms for a 1024-tile canvas, which is a tap that feels broken
/// rather than a frame that is slightly late.
Iterable<CoveredTile> tilesCovering(
  BitmapSurface surface,
  DirtyRegion region,
) sync* {
  final tileSize = surface.tileSize;
  final range = tileRangeCoveringPixels(
    left: region.left,
    top: region.top,
    rightExclusive: region.rightExclusive,
    bottomExclusive: region.bottomExclusive,
    tileSize: tileSize,
  );
  for (var ty = range.firstY; ty <= range.lastY; ty += 1) {
    final worldTop = ty * tileSize;
    for (var tx = range.firstX; tx <= range.lastX; tx += 1) {
      final tile = surface.tileAt(TileCoord(x: tx, y: ty));
      if (tile == null) {
        continue;
      }
      final worldLeft = tx * tileSize;
      yield (
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

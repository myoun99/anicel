import 'bitmap_surface.dart';
import 'bitmap_tile.dart';
import 'dirty_region.dart';
import 'tile_coord.dart';

/// One tile a region's box touches, held or not: where its top-left sits in
/// world pixels, and the part of the region that lands inside it (right and
/// bottom exclusive, world coordinates).
typedef TileSpan = ({
  TileCoord coord,
  int worldLeft,
  int worldTop,
  int left,
  int top,
  int rightExclusive,
  int bottomExclusive,
});

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

/// Every tile [region]'s box touches at [tileSize], row by row, and the
/// part of [region] inside each — the ONE walk from a region to its tiles.
///
/// The tile box comes from [DirtyRegion.tileRange] — the floorDiv-not-`~/`
/// law for negative pasteboard coordinates lives in [tileAxisSpan], once.
///
/// 🚨It was written twice: here, and again in the native span staging for
/// the dab kernels (`stageTileSpans`), which needs every tile rather than
/// the held ones. The clone gate found the second when a batch of dabs
/// made it a union (2026-09-25, board `preset-spacing-minimum`).
Iterable<TileSpan> tileSpansOf(
  DirtyRegion region, {
  required int tileSize,
}) sync* {
  final (:firstX, :lastX, :firstY, :lastY) = region.tileRange(
    tileSize: tileSize,
  );
  for (var ty = firstY; ty <= lastY; ty += 1) {
    final worldTop = ty * tileSize;
    for (var tx = firstX; tx <= lastX; tx += 1) {
      final worldLeft = tx * tileSize;
      yield (
        coord: TileCoord(x: tx, y: ty),
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

/// Every EXISTING tile [region] touches, row by row ([tileSpansOf]).
///
/// ⛔MISSING TILES ARE SKIPPED, not treated as transparent: the surface is
/// sparse, an absent tile has no bytes, and every caller has to skip it
/// the same way or read past the end of a buffer that was never made.
Iterable<CoveredTile> tilesCovering(
  BitmapSurface surface,
  DirtyRegion region,
) sync* {
  for (final span in tileSpansOf(region, tileSize: surface.tileSize)) {
    final tile = surface.tileAt(span.coord);
    if (tile == null) {
      continue;
    }
    yield (
      coord: span.coord,
      tile: tile,
      worldLeft: span.worldLeft,
      worldTop: span.worldTop,
      left: span.left,
      top: span.top,
      rightExclusive: span.rightExclusive,
      bottomExclusive: span.bottomExclusive,
    );
  }
}

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/canvas/tile_blocks.dart';

/// The blocks a compose pictures a surface's tiles in (board
/// a-cold-cel-composes-tile-by-tile): squares of [tileBlockEdge] pixels,
/// each pictured over the rect of the tiles it has.
void main() {
  BitmapSurface surfaceOf(
    Iterable<(int, int)> coords, {
    int tileSize = 128,
    CanvasSize canvasSize = const CanvasSize(width: 2340, height: 1654),
  }) => BitmapSurface(
    canvasSize: canvasSize,
    tileSize: tileSize,
    tiles: {
      for (final (x, y) in coords)
        TileCoord(x: x, y: y): BitmapTile(
          size: tileSize,
          pixels: Uint8List(tileSize * tileSize * 4),
        ),
    },
  );

  /// Each block as (left, top, right, bottom) of its region, and how many
  /// tiles it holds.
  List<((int, int, int, int), int)> blocksOf(BitmapSurface surface) => [
    for (final block in tileBlocksOf(surface))
      (
        (
          block.region.left,
          block.region.top,
          block.region.rightExclusive,
          block.region.bottomExclusive,
        ),
        block.tiles.length,
      ),
  ];

  test('a block of 256 px: four tiles of 128 that fill it are ONE picture '
      'over the whole square', () {
    expect(tileBlockEdge, 256);
    final surface = surfaceOf([(0, 0), (1, 0), (0, 1), (1, 1)]);
    expect(blocksOf(surface), [((0, 0, 256, 256), 4)]);
  });

  test('a cel is cut on the block grid: tiles of two squares are two '
      'pictures, each over its own square', () {
    final surface = surfaceOf([(1, 0), (2, 0)]);
    expect(blocksOf(surface), [
      ((128, 0, 256, 128), 1),
      ((256, 0, 384, 128), 1),
    ]);
  });

  test('a part-filled block is pictured over the rect of the tiles it has — '
      'never its whole square', () {
    // One tile: itself.
    expect(blocksOf(surfaceOf([(1, 2)])), [((128, 256, 256, 384), 1)]);
    // A row of two, a column of two.
    expect(blocksOf(surfaceOf([(2, 0), (3, 0)])), [((256, 0, 512, 128), 2)]);
    expect(blocksOf(surfaceOf([(1, 2), (1, 3)])), [((128, 256, 256, 512), 2)]);
    // Two across a corner: the rect holds the gaps, transparent.
    expect(blocksOf(surfaceOf([(0, 0), (1, 1)])), [((0, 0, 256, 256), 2)]);
  });

  test('the pasteboard\'s tiles fall in blocks by FLOOR division: tile -1 '
      'is the last of the block before nought', () {
    final surface = surfaceOf([(-1, -1), (0, 0)]);
    expect(blocksOf(surface), [
      ((-128, -128, 0, 0), 1),
      ((0, 0, 128, 128), 1),
    ]);
  });

  test('a block is as many whole tiles a side as fit the edge — and one tile '
      'at least', () {
    // 96 px tiles: two a side, the third in the next block.
    expect(
      blocksOf(surfaceOf([(0, 0), (1, 0), (2, 0)], tileSize: 96)),
      [((0, 0, 192, 96), 2), ((192, 0, 288, 96), 1)],
    );
    // Tiles of the edge or past it are a block each.
    expect(
      blocksOf(surfaceOf([(0, 0), (1, 1)], tileSize: 256)),
      [((0, 0, 256, 256), 1), ((256, 256, 512, 512), 1)],
    );
    expect(
      blocksOf(surfaceOf([(0, 0), (1, 0)], tileSize: 1024)),
      [((0, 0, 1024, 1024), 1), ((1024, 0, 2048, 1024), 1)],
    );
  });
}

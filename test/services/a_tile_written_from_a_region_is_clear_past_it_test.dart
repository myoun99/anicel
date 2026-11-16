import 'dart:ffi';
import 'dart:typed_data';

import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/tile_blocks.dart';
import 'package:anicel/src/services/bitmap_surface_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

/// A tile [tilesOfRegion] writes comes off the lists holding whatever its
/// last holder left ([TileBlocks.alloc]), so it is cleared before the
/// region's rows go in: a tile the region covers in part is clear past it.
/// 🚨The clearing is `zeroBytes` since 2026-11-16 (card
/// the-tile-cutter-is-most-of-a-raster-import); taking it out left every
/// test green till this one.
void main() {
  // A side no other tile wears, so the list of its size holds only what
  // this test parks there.
  const side = 19;
  const red = [200, 10, 20, 255];

  test('🚨a tile the region covers in part is clear past it, whatever its '
      'block held', () {
    final length = BitmapTile.bytesFor(side);
    final parked = TileBlocks.alloc(length);
    parked.asTypedList(length).setAll(0, List.filled(length, 0xab));
    TileBlocks.free(parked);

    final region = DirtyRegion.fromXYWH(x: 3, y: 2, width: 4, height: 5);
    final straight = Uint8List(region.width * region.height * 4);
    for (var at = 0; at < straight.length; at += 4) {
      straight.setAll(at, red);
    }
    final tiles = tilesOfRegion(region, straight, tileSize: side);

    expect(tiles.keys, [TileCoord(x: 0, y: 0)]);
    tiles.values.single.readPixels((pointer, pixels) {
      expect(
        pointer.address,
        parked.address,
        reason: 'premise: the tile took the dirty block',
      );
      List<int> at(int x, int y) =>
          pixels.sublist((y * side + x) * 4, (y * side + x) * 4 + 4);
      expect(at(3, 2), red, reason: 'its first pixel');
      expect(at(6, 6), red, reason: 'its last pixel');
      const outside = [(2, 2), (7, 2), (3, 1), (3, 7), (0, 0), (18, 18)];
      for (final (x, y) in outside) {
        expect(at(x, y), [0, 0, 0, 0], reason: '($x, $y)');
      }
    });
  });
}

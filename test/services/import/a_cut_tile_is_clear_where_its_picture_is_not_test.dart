import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/native/tile_blocks.dart';
import 'package:anicel/src/services/import/tile_cutter.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';

/// A block comes off the lists holding whatever its last holder left
/// ([TileBlocks.alloc]), so the cutter clears it before the rows go in: a
/// tile the picture covers in part is clear where the picture is not.
/// 🚨The clearing is `zeroBytes` since 2026-11-16 (card
/// the-tile-cutter-is-most-of-a-raster-import) — this pins that it still
/// clears, and that the tiles keep their columns past the first.
void main() {
  // A side no other tile wears, so the list of its size holds only what
  // these tests park there.
  const side = 23;
  final length = BitmapTile.bytesFor(side);
  const red = [200, 10, 20, 255];

  /// A block of [length] full of 0xab, parked: the next ask's answer.
  int parkedDirty() {
    final block = TileBlocks.alloc(length);
    block.asTypedList(length).setAll(0, List.filled(length, 0xab));
    TileBlocks.free(block);
    return block.address;
  }

  /// [width] × [height] of red, cut at ([left], [top]) into tiles of [side].
  CutTiles cutRed(int left, int top, int width, int height) {
    final rgba = Uint8List(width * height * 4);
    for (var at = 0; at < rgba.length; at += 4) {
      rgba.setAll(at, red);
    }
    return cutRgbaRows(
      rgba,
      width: width,
      height: height,
      cut: (
        left: left,
        top: top,
        tileSize: side,
        tiles: (
          firstX: left ~/ side,
          lastX: (left + width - 1) ~/ side,
          firstY: top ~/ side,
          lastY: (top + height - 1) ~/ side,
        ),
      ),
    );
  }

  /// The pixel at (x, y) of a tile's block.
  List<int> pixelOf(LaidPixels pixels, int x, int y) {
    final address = (pixels as LaidBlock).address;
    final at = (y * side + x) * 4;
    return Pointer<Uint8>.fromAddress(
      address,
    ).asTypedList(length).sublist(at, at + 4);
  }

  test('🚨a block that held another picture is clear where this one is '
      'not', () {
    final dirty = parkedDirty();

    final tiles = cutRed(5, 4, 10, 7);
    addTearDown(() => giveBackCut(tiles));

    expect(tiles, hasLength(1));
    final tile = tiles.single;
    expect(
      (tile.pixels as LaidBlock).address,
      dirty,
      reason: 'premise: the cut took the dirty block',
    );
    expect(pixelOf(tile.pixels, 5, 4), red, reason: 'its first pixel');
    expect(pixelOf(tile.pixels, 14, 10), red, reason: 'its last pixel');
    const outside = [(4, 4), (15, 4), (5, 3), (5, 11), (0, 0), (22, 22)];
    for (final (x, y) in outside) {
      expect(pixelOf(tile.pixels, x, y), [0, 0, 0, 0], reason: '($x, $y)');
    }
  });

  test('a picture past the first column and row keeps its tiles where it '
      'lies', () {
    final tiles = cutRed(side + 4, side * 2 + 3, side + 2, 5);
    addTearDown(() => giveBackCut(tiles));

    expect({for (final tile in tiles) (tile.x, tile.y)}, {(1, 2), (2, 2)});
    final second = tiles.firstWhere((tile) => tile.x == 2);
    expect(pixelOf(second.pixels, 0, 3), red, reason: 'its column 23');
    expect(pixelOf(second.pixels, 5, 3), red, reason: 'its last column');
    expect(pixelOf(second.pixels, 6, 3), [0, 0, 0, 0], reason: 'past it');
    expect(pixelOf(second.pixels, 0, 2), [0, 0, 0, 0], reason: 'above it');
  });
}

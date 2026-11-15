import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show gpuTileBytes, gpuTileSide;
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/native/tile_blocks.dart';
import 'package:anicel/src/services/import/raster_cel_import.dart';
import 'package:anicel/src/services/import/tile_cutter.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';

/// A tile a picture is laid on in two runs — its halves, where one raster
/// cannot hold what it reaches — is one tile again ([laidTogether]): each
/// byte is one run's, the other's nothing there. And the tile the two made
/// is asked its colour again, as whoever lays a tile for another isolate
/// asks ([LaidPixels]): two halves of one colour are a tile of one colour,
/// which neither half was.
void main() {
  final side = gpuTileSide;
  const red = [200, 10, 20, 255];
  const blue = [10, 20, 200, 255];

  /// A tile's block whose rows from [from] up to [to] are [rgba], and
  /// nothing elsewhere — what a run over a part of a tile lays.
  LaidPixels rows(int from, int to, List<int> rgba) {
    final block = TileBlocks.alloc(gpuTileBytes);
    final bytes = block.asTypedList(gpuTileBytes)
      ..fillRange(0, gpuTileBytes, 0);
    for (var at = from * side * 4; at < to * side * 4; at += 1) {
      bytes[at] = rgba[at % 4];
    }
    return LaidBlock(block.address);
  }

  /// What [rows] lays, as bytes.
  Uint8List bytesOfRows(int from, int to, List<int> rgba) {
    final bytes = Uint8List(gpuTileBytes);
    for (var at = from * side * 4; at < to * side * 4; at += 1) {
      bytes[at] = rgba[at % 4];
    }
    return bytes;
  }

  /// [pixels] as the tile that adopts them reads them — its block goes
  /// back with the tile.
  Uint8List adoptedBytes(LaidPixels pixels) => pixels.adopted(side).pixels;

  test('a tile both runs laid is one tile, each byte one run\'s', () {
    final together = laidTogether(
      [(x: 0, y: 0, pixels: rows(0, 64, red))],
      [(x: 0, y: 0, pixels: rows(64, side, blue))],
    );

    expect([for (final tile in together) (tile.x, tile.y)], [(0, 0)]);
    expect(together.single.pixels, isA<LaidBlock>());
    final bytes = bytesOfRows(0, 64, red)
      ..setRange(
        64 * side * 4,
        gpuTileBytes,
        bytesOfRows(64, side, blue),
        64 * side * 4,
      );
    expect(adoptedBytes(together.single.pixels), bytes);
  });

  // ⚠️That the block the halves were put into goes back is pinned where a
  // laid block is asked its colour (`LaidPixels.keeping`, on a tile side of
  // its own): every tile of the app is of this side, and theirs park on
  // this list while a test looks at it.
  test('🚨two halves of one colour are a tile of one colour: its word '
      'crosses', () {
    final together = laidTogether(
      [(x: 0, y: 0, pixels: rows(0, 64, red))],
      [(x: 0, y: 0, pixels: rows(64, side, red))],
    );

    expect(together.single.pixels, isA<LaidWord>());
    final tile = together.single.pixels.adopted(side);
    expect(tile.pixels, bytesOfRows(0, side, red));
    expect(tile.ownBytes, 0);
  });

  test('a tile one run alone laid goes through as it was laid', () {
    final one = rows(0, 64, red);
    final other = rows(0, 64, blue);

    final together = laidTogether(
      [(x: 0, y: 0, pixels: one)],
      [(x: 1, y: 0, pixels: other)],
    );
    addTearDown(() => giveBackCut(together));

    expect([for (final tile in together) (tile.x, tile.y)], [(0, 0), (1, 0)]);
    expect(together[0].pixels, same(one));
    expect(together[1].pixels, same(other));
  });

  test('a tile a run laid as its word is put together as its bytes — no '
      'run over a part of a tile lays one, and the two shapes are still '
      'one tile', () {
    final word = oneWordOf(bytesOfRows(0, side, const [0, 0, 9, 0]))!;

    final together = laidTogether(
      [(x: 0, y: 0, pixels: LaidWord(word))],
      [(x: 0, y: 0, pixels: rows(0, 64, const [200, 0, 0, 255]))],
    );

    expect(together.single.pixels, isA<LaidBlock>());
    final bytes = bytesOfRows(0, side, const [0, 0, 9, 0])
      ..setRange(0, 64 * side * 4, bytesOfRows(0, 64, const [200, 0, 9, 255]));
    expect(adoptedBytes(together.single.pixels), bytes);
  });
}

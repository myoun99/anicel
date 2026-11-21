import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/native/tile_blocks.dart';
import 'package:anicel/src/services/import/tile_cutter.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';

/// Whoever lays a tile for another isolate asks whether it is one colour
/// ([LaidPixels]): a picture's paper, a movie's bars — a tile the cut made
/// of one colour crosses as its word and takes no block (card
/// `a-file-keeps-all-clear-tiles-in-its-cels`). The adoption reads nothing,
/// so a block of one colour adopted would be the weight the tile was to be
/// without.
void main() {
  // A side no other tile wears, so the blocks laid and held of its size
  // ([TileBlocks.debugLaid], [TileBlocks.debugHeld]) are these tests' and
  // nothing else's.
  const side = 22;
  final length = BitmapTile.bytesFor(side);
  const red = [200, 10, 20, 255];
  const blue = [10, 20, 200, 255];

  /// Every tile a test adopted, held till the file ends: one collected
  /// gives its block back when the collector chooses, under a later
  /// test's count.
  final adoptedHere = <BitmapTile>[];

  /// A tile's worth of [rgba].
  Uint8List filled(List<int> rgba) {
    final bytes = Uint8List(length);
    for (var at = 0; at < length; at += 1) {
      bytes[at] = rgba[at % 4];
    }
    return bytes;
  }

  /// Three tiles in a row: all red, red with one blue pixel, and nothing.
  CutTiles redRedAndBlueNothing() {
    const width = side * 3;
    final rgba = Uint8List(width * side * 4);
    for (var y = 0; y < side; y += 1) {
      for (var x = 0; x < side * 2; x += 1) {
        rgba.setAll((y * width + x) * 4, red);
      }
    }
    rgba.setAll((3 * width + side + 2) * 4, blue);
    return cutRgbaRows(
      rgba,
      width: width,
      height: side,
      cut: (
        left: 0,
        top: 0,
        tileSize: side,
        tiles: (firstX: 0, lastX: 2, firstY: 0, lastY: 0),
      ),
    );
  }

  test('🚨a tile the picture covers in one colour closes as its word and '
      'keeps no block — the tile beside it, of two, keeps its own', () {
    final laid = TileBlocks.debugLaid(length);
    final held = TileBlocks.debugHeld(length);

    final tiles = redRedAndBlueNothing();
    addTearDown(() => giveBackCut(tiles));

    expect([for (final tile in tiles) (tile.x, tile.y)], [(0, 0), (1, 0)]);
    expect(tiles[0].pixels, isA<LaidWord>());
    expect(tiles[1].pixels, isA<LaidBlock>());
    expect(
      TileBlocks.debugLaid(length),
      greaterThan(laid + 1),
      reason: '⛔premise: the cut laid a block for more than the one tile',
    );
    expect(
      TileBlocks.debugHeld(length),
      held + 1,
      reason: 'the red tile\'s block went back as it closed, and the '
          'clear one\'s: the tile of two colours holds the one left',
    );
  });

  test('adopted, each is the tile the picture laid there', () {
    final tiles = redRedAndBlueNothing();

    final whole = tiles[0].pixels.adopted(side);
    final marked = tiles[1].pixels.adopted(side);
    adoptedHere.addAll([whole, marked]);

    expect(whole.pixels, filled(red));
    expect(whole.ownBytes, 0);
    expect(marked.pixels, filled(red)..setAll((3 * side + 2) * 4, blue));
    expect(marked.ownBytes, length);
  });

  test('given back unadopted, the one block the cut kept goes back', () {
    final laid = TileBlocks.debugLaid(length);
    final held = TileBlocks.debugHeld(length);

    giveBackCut(redRedAndBlueNothing());

    expect(
      TileBlocks.debugLaid(length),
      greaterThan(laid),
      reason: '⛔premise: the cut laid blocks',
    );
    // With the red and the clear tiles' blocks, which went back as the
    // row closed.
    expect(TileBlocks.debugHeld(length), held);
  });

  group('laid pixels in a block — for whoever writes into a laid tile '
      'before it is adopted', () {
    test('a word\'s is a tile\'s worth of it, the caller\'s to free', () {
      final word = oneWordOf(filled(red))!;

      final block = LaidWord(word).inABlock(side);
      addTearDown(() => TileBlocks.free(block));

      expect(block.asTypedList(length), filled(red));
    });

    test('a block\'s is the block', () {
      final block = TileBlocks.alloc(length);
      addTearDown(() => TileBlocks.free(block));

      expect(
        LaidBlock(block.address, hasInk: false).inABlock(side).address,
        block.address,
      );
    });

    test('🚨and laid again it is asked its colour again: one colour gives '
        'the block back, two keep it', () {
      final one = TileBlocks.alloc(length);
      one.asTypedList(length).setAll(0, filled(red));
      final two = TileBlocks.alloc(length);
      two.asTypedList(length).setAll(0, filled(red)..[0] = 0);
      final held = TileBlocks.debugHeld(length);

      final laidOne = LaidPixels.keeping(one, one.asTypedList(length));
      final laidTwo = LaidPixels.keeping(two, two.asTypedList(length));
      addTearDown(laidTwo.giveBack);

      expect(laidOne, isA<LaidWord>());
      expect((laidOne as LaidWord).word, oneWordOf(filled(red)));
      expect(
        laidTwo,
        isA<LaidBlock>().having((b) => b.address, 'address', two.address),
      );
      expect(
        TileBlocks.debugHeld(length),
        held - 1,
        reason: 'the block of one colour went back, and the other is kept',
      );
    });
  });
}

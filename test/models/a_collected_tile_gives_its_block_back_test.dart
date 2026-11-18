@Tags(['gc'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/native/tile_blocks.dart';

import '../helpers/collect_garbage.dart';

/// A tile's pixels are a block of the lists ([TileBlocks]), and nothing
/// gives it back but a finalizer — the tile's for a block of its own, the
/// colour's for the block the tiles of one colour share: a block collected
/// without one is held for as long as the app runs — 64 KB a tile, and a
/// cel is hundreds of them.
void main() {
  /// Whether the next ask of [length] is answered with the block at
  /// [address] — it is parked on the lists.
  bool cameBack(int address, int length) {
    final block = TileBlocks.alloc(length);
    TileBlocks.free(block);
    return block.address == address;
  }

  test('a collected tile gives its block back to the lists — the next ask '
      'of its size is answered with it', () async {
    // A side no other tile wears, so the list of its size holds this
    // tile's block alone.
    const side = 40;
    final length = BitmapTile.bytesFor(side);
    // Of two colours: a tile of one holds no block of its own.
    BitmapTile? tile = BitmapTile(
      size: side,
      pixels: Uint8List(length)..[3] = 255,
    );
    expect(tile.ownBytes, length, reason: 'fixture: the block is its own');
    final address = tile.readPixels((pixels, _) => pixels.address);
    tile = null;

    // An ask before the finalizer ran is answered with a fresh block, and
    // the tile's parks over it when it comes.
    await collectGarbageUntil(() => cameBack(address, length));

    expect(
      cameBack(address, length),
      isTrue,
      reason: 'held still, it answers no ask',
    );
  });

  test('🚨a colour\'s block goes back when the LAST tile of the colour is '
      'collected — and not while one of them is alive', () async {
    const side = 41;
    const word = 0x00ffffff;
    final length = BitmapTile.bytesFor(side);
    BitmapTile? one = BitmapTile.ofOneColour(size: side, word: word);
    final other = BitmapTile.ofOneColour(size: side, word: word);
    final address = one.readPixels((pixels, _) => pixels.address);
    expect(
      other.readPixels((pixels, _) => pixels.address),
      address,
      reason: 'fixture: the two read one block',
    );
    final bytes = one.pixels;
    one = null;

    await collectGarbage();
    await collectGarbage();

    expect(
      cameBack(address, length),
      isFalse,
      reason: 'a tile of the colour is alive, and reads this block',
    );
    expect(other.pixels, bytes);
    expect(other.readPixels((pixels, _) => pixels.address), address);
  });

  test('and once the last is collected the next tile of the colour lays '
      'it again', () async {
    const side = 42;
    const word = 0x00ffffff;
    final length = BitmapTile.bytesFor(side);
    BitmapTile? last = BitmapTile.ofOneColour(size: side, word: word);
    final address = last.readPixels((pixels, _) => pixels.address);
    final bytes = last.pixels;
    last = null;

    await collectGarbageUntil(() => cameBack(address, length));

    expect(
      cameBack(address, length),
      isTrue,
      reason: 'held still, it answers no ask',
    );
    final again = BitmapTile.ofOneColour(size: side, word: word);
    expect(again.pixels, bytes);
    expect(again.ownBytes, 0);
  });
}

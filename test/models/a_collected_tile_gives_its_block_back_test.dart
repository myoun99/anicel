@Tags(['gc'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/native/tile_blocks.dart';

import '../helpers/collect_garbage.dart';

/// A tile's pixels are a block of the allocator's ([TileBlocks]), and
/// nothing gives it back but a finalizer — the tile's for a block of its
/// own, the colour's for the block the tiles of one colour share: a block
/// collected without one is held for as long as the app runs — 64 KB a
/// tile, and a cel is hundreds of them.
///
/// Read off the blocks' own books ([TileBlocks.debugHeld]), each test at a
/// side no other tile wears: the blocks held of its size are its own.
void main() {
  test('a collected tile gives its block back — none of its size is held '
      'any more', () async {
    const side = 40;
    final length = BitmapTile.bytesFor(side);
    // Of two colours: a tile of one holds no block of its own.
    BitmapTile? tile = BitmapTile(
      size: side,
      pixels: Uint8List(length)..[3] = 255,
    );
    expect(tile.ownBytes, length, reason: 'fixture: the block is its own');
    expect(TileBlocks.debugHeld(length), 1, reason: 'fixture: and held');
    tile = null;

    await collectGarbageUntil(() => TileBlocks.debugHeld(length) == 0);

    expect(TileBlocks.debugHeld(length), 0);
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
    expect(TileBlocks.debugHeld(length), 1, reason: 'fixture: the one');
    final bytes = one.pixels;
    one = null;

    await collectGarbage();
    await collectGarbage();

    expect(
      TileBlocks.debugHeld(length),
      1,
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
    final bytes = last.pixels;
    expect(TileBlocks.debugHeld(length), 1, reason: 'fixture: its block');
    final laid = TileBlocks.debugLaid(length);
    last = null;

    await collectGarbageUntil(() => TileBlocks.debugHeld(length) == 0);

    expect(TileBlocks.debugHeld(length), 0);
    final again = BitmapTile.ofOneColour(size: side, word: word);
    expect(again.pixels, bytes);
    expect(again.ownBytes, 0);
    expect(
      (TileBlocks.debugLaid(length), TileBlocks.debugHeld(length)),
      (laid + 1, 1),
      reason: 'laid anew, and one',
    );
  });
}

@Tags(['gc'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/native/tile_blocks.dart';

import '../helpers/collect_garbage.dart';

/// A tile's pixels are a block of the lists ([TileBlocks]), and nothing
/// gives it back but the tile's finalizer: a tile collected without one
/// holds its block for as long as the app runs — 64 KB a tile, and a cel is
/// hundreds of them.
void main() {
  test('a collected tile gives its block back to the lists — the next ask '
      'of its size is answered with it', () async {
    // A side no other tile wears, so the list of its size holds this
    // tile's block alone.
    const side = 40;
    final length = BitmapTile.bytesFor(side);
    BitmapTile? tile = BitmapTile.blank(size: side);
    final address = tile.readPixels((pixels, _) => pixels.address);
    tile = null;

    // An ask before the finalizer ran is answered with a fresh block, and
    // the tile's parks over it when it comes.
    bool cameBack() {
      final block = TileBlocks.alloc(length);
      TileBlocks.free(block);
      return block.address == address;
    }

    await collectGarbageUntil(cameBack);

    expect(cameBack(), isTrue, reason: 'held still, it answers no ask');
  });
}

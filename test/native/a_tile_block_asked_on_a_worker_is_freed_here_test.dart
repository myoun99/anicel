@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/on_a_worker.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/native/tile_blocks.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:anicel/src/services/persistence/thaw_in_worker.dart';

import '../helpers/cel_text_fixture.dart' show celTextTestKey;

/// 🚨A tile's block is the process's, whichever isolate asked for it
/// ([TileBlocks]): a worker that lays a thawed cel's tiles (card
/// `cel-thaw-holds-the-ui-thread`) takes blocks the main isolate's tiles
/// adopt, and their finalizers give back. A block carries a head in front
/// of its pixels, so one from anywhere else given back here — which a
/// tile's finalizer does — breaks the heap.
///
/// Read off the blocks' own books ([TileBlocks.debugLaid],
/// [TileBlocks.debugHeld]), the process's one: a worker with blocks of its
/// own would leave them as they were.
///
/// ↩️Till C ABI 82 the blocks were the C engine's: a worker was told their
/// functions' addresses, for its own probe could load another binary or
/// none, and this suite skipped wherever no C binary was built.
void main() {
  setUp(() {
    // A REAL worker: the corpus runs every worker's job here
    // (`flutter_test_config.dart`).
    debugWorkersRunHere = false;
  });

  tearDown(() {
    debugWorkersRunHere = true;
  });

  test('a block a worker asked for is held on the books read here, and '
      'held no more once it is freed here', () async {
    // A size no tile wears, so the books of it count this block alone.
    const length = 12345;
    final laid = TileBlocks.debugLaid(length);
    final held = TileBlocks.debugHeld(length);

    final address = await Isolate.run(() => TileBlocks.alloc(length).address);
    expect(
      (TileBlocks.debugLaid(length), TileBlocks.debugHeld(length)),
      (laid + 1, held + 1),
      reason: 'one allocator: blocks of the worker\'s own would be on no '
          'books this isolate reads',
    );
    TileBlocks.free(Pointer<Uint8>.fromAddress(address));

    expect(TileBlocks.debugHeld(length), held);
  });

  test('🚨and a cel thawed on a worker is laid in them', () async {
    // One tile, of the engine's side — the only one a cel's tile wears, so
    // the books of it are not this block's alone: the blocks laid only
    // grow, and the ones held are read right before the free and after.
    const tileSize = defaultCelTileSize;
    final length = BitmapTile.bytesFor(tileSize);
    // ↩️Deflate until the connection round (connection-round-checklist H),
    // so the worker had no C engine of its own to find: the compressor is
    // the code asset's now, which every isolate reaches, so the blob is
    // the zstd one a save writes.
    final blob = AnicelCelBlob.ofSurface(
      celTextTestKey,
      AnicelCelEntry(
        key: celTextTestKey,
        canvasSize: const CanvasSize(width: tileSize, height: tileSize),
        tileSize: tileSize,
        // Of two colours: a tile of one is laid as its word, in no block
        // (`LaidPixels`).
        tiles: [(x: 0, y: 0, pixels: Uint8List(length)..[3] = 255)],
      ).toSurface(),
    );
    final laidBefore = TileBlocks.debugLaid(length);

    final laid = await layCelInWorker(blob, reach: PasteboardReach.whole);

    expect(
      TileBlocks.debugLaid(length),
      greaterThan(laidBefore),
      reason: 'its block is on the books read here',
    );
    final block = Pointer<Uint8>.fromAddress(
      (laid.tiles.single.pixels as LaidBlock).address,
    );
    final held = TileBlocks.debugHeld(length);
    TileBlocks.free(block);
    expect(TileBlocks.debugHeld(length), held - 1);
  });
}

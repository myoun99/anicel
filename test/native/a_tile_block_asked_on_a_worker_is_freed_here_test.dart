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
/// of its pixels, so one from anywhere else given to the lists — which a
/// tile's finalizer does — breaks the heap.
///
/// ↩️Till C ABI 82 the lists were the C engine's: a worker was told their
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

  test('a block a worker asked for parks on the lists when it is freed '
      'here, and the next ask of its size here takes it', () async {
    // A size no tile wears, so the list of it holds this block alone.
    const length = 12345;

    final address = await Isolate.run(() => TileBlocks.alloc(length).address);
    TileBlocks.free(Pointer<Uint8>.fromAddress(address));
    final again = TileBlocks.alloc(length);
    addTearDown(() => TileBlocks.free(again));

    expect(
      again.address,
      address,
      reason: 'one allocator: lists of the worker\'s own would have '
          'answered this isolate with a fresh block',
    );
  });

  test('🚨and a cel thawed on a worker is laid in them', () async {
    // One tile, of the engine's side — the only one a cel's tile wears, so
    // its list is not this block's alone: the lists hand back the block
    // they parked last, which is the one freed here.
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
        tiles: [(x: 0, y: 0, pixels: Uint8List(length))],
      ).toSurface(),
    );

    final laid = await layCelInWorker(blob, reach: PasteboardReach.whole);
    final address = laid.tiles.single.pixels;
    TileBlocks.free(Pointer<Uint8>.fromAddress(address));
    final again = TileBlocks.alloc(length);
    addTearDown(() => TileBlocks.free(again));

    expect(again.address, address, reason: 'it was one of the lists\' own');
  });
}

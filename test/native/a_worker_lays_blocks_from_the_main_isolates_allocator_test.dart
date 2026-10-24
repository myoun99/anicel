@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/on_a_worker.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/native/qa_cel_compressor.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:anicel/src/services/persistence/thaw_in_worker.dart';

import '../helpers/cel_text_fixture.dart' show celTextTestKey;
import '../helpers/native_engine_path.dart';

/// 🚨A worker that lays a thawed cel's tiles (card
/// `cel-thaw-holds-the-ui-thread`) takes its blocks from the MAIN isolate's
/// allocator, by address ([BitmapTile.blocks]). A `qa_tile_alloc` block
/// carries a header in front of the pixels, so freeing one through
/// `malloc` — or a `malloc` block through `qa_tile_free`, which the main
/// isolate's finalizer is — breaks the heap. And the worker could not have
/// asked its own probe: this suite's path override is a static of the
/// main isolate alone.
///
/// Real-binary-or-skip, like every engine suite.
void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();
  final skip = libraryPath != null ? false : nativeEngineMissingSkipReason;

  setUp(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = libraryPath;
    // A REAL worker: the corpus runs every worker's job here
    // (`flutter_test_config.dart`), where any pool would be the engine's.
    debugWorkersRunHere = false;
  });

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    debugWorkersRunHere = true;
  });

  test('a block a worker got by the addresses it was told is the engine\'s '
      'own — it goes back into the engine\'s pool, and comes out of it '
      'again', () async {
    final engine = QaNativeEngine.instance;
    expect(engine, isNotNull, reason: 'the binary at $libraryPath loaded');
    final blocks = BitmapTile.blocks;
    expect(blocks.alloc, isNot(0));
    // A size no tile wears, so the pool's bucket for it holds this block
    // alone.
    const length = 12345;

    final address = await Isolate.run(
      () => tileBlocksHere(blocks).allocate(length).address,
    );
    engine!.tileFree(Pointer<Uint8>.fromAddress(address));
    final again = engine.tileAlloc(length);
    addTearDown(() => engine.tileFree(again));

    expect(
      again.address,
      address,
      reason: 'the pool parked it as one of its own — a malloc block has no '
          'header for it to read',
    );
  }, skip: skip);

  test('🚨and a cel thawed on a worker is laid in them — the thaw hands its '
      'worker those addresses, not a pool of the worker\'s own', () async {
    final engine = QaNativeEngine.instance;
    expect(engine, isNotNull, reason: 'the binary at $libraryPath loaded');
    // One tile, of a size no tile wears — as above.
    const tileSize = 24;
    final length = BitmapTile.bytesFor(tileSize);
    // Deflate: the worker reads it with no engine of its own to find.
    QaCelCompressor.debugInstanceOverride = () => null;
    final AnicelCelBlob blob;
    try {
      blob = AnicelCelBlob.encode(
        AnicelCelEntry(
          key: celTextTestKey,
          canvasSize: const CanvasSize(width: tileSize, height: tileSize),
          tileSize: tileSize,
          tiles: [(x: 0, y: 0, pixels: Uint8List(length))],
        ),
      );
    } finally {
      QaCelCompressor.debugInstanceOverride = null;
    }

    final laid = await layCelInWorker(
      blob,
      BitmapTile.blocks,
      reach: PasteboardReach.whole,
    );
    final address = laid.tiles.single.pixels;
    engine!.tileFree(Pointer<Uint8>.fromAddress(address));
    final again = engine.tileAlloc(length);
    addTearDown(() => engine.tileFree(again));

    expect(again.address, address, reason: 'it was one of the pool\'s own');
  }, skip: skip);
}

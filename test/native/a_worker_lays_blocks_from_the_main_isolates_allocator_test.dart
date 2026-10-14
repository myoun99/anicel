@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';

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
  });

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
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
}

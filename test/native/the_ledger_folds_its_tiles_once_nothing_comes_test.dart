import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';

import '../helpers/poll_until.dart';
import '../helpers/tiles_on_the_engine.dart';

/// The ledger folds its pool's tiles (🗣️F-610-Q5, 유저 2026-11-19, 채팅:
/// 「압축은 일단 중복줄이면서 하는데 결국은 3번대로 하자. 결과가 제일
/// 좋으니까」) by the fold's kernels once they are compiled, a batch at a
/// time, the isolate that asks waiting for no GPU
/// (`EngineTileLedger.foldABatch`): a tile folded keeps the slot that names
/// it, so each reads as it was. A rest folds them where a launch said so
/// (`EngineTileLedger.foldsAtRest`), whether the tiles were landed or
/// stored.
///
/// That a pool's page of folded tiles was made is read off its bytes: the
/// pool tells no more of where a tile lies, and the crate's own pins read
/// its books (rust/src/kernels/pool/folded_tests.rs).
///
/// On an engine and a ledger of the test's own: a device that is gone is
/// gone for its process, and the app has one.
void main() {
  late GpuEngine engine;
  late EngineTileLedger ledger;
  late GpuFold compiled;
  GpuFold? kernels;

  setUp(() {
    engine = GpuEngine.onFirstAdapter();
    kernels = compiled = GpuFold(engine);
    ledger = EngineTileLedger(engine, foldKernels: () => kernels);
  });
  // ⚠️The ledger's pool is not freed with its test: a tile collected after
  // it lets its slot go there (the ledger's finalizer), in a later test.
  tearDown(() {
    EngineTileLedger.foldsAtRest = false;
    compiled.free();
    engine.close();
  });

  List<BitmapTile> landed(List<BitmapTile?> unders, int value) =>
      landedOn(ledger, unders, value);

  test('a batch folds the tiles next to fold, the isolate that asks waiting '
      'for no GPU, and each reads as it was — then none is left', () async {
    final tiles = [
      for (final value in [1, 2, 3]) landed([null], value).single,
    ];

    final (bytes, waits) = (ledger.pool.bytes, debugWaitsHere);
    final onItsWay = ledger.foldABatch();
    expect(ledger.pool.bytes, bytes, reason: 'nothing was waited for');
    expect(await onItsWay, isTrue, reason: 'there may be more');
    expect(debugWaitsHere, waits, reason: 'no wait for the GPU here');
    expect(
      ledger.pool.bytes,
      greaterThan(bytes),
      reason: 'a page of folded tiles is the pool\'s',
    );

    final folded = ledger.pool.bytes;
    expect(await ledger.foldABatch(), isFalse, reason: 'none is left');
    expect(ledger.pool.bytes, folded);
    expect(
      [for (final tile in tiles) tile.pixels.toSet()],
      [
        {1},
        {2},
        {3},
      ],
    );
  });

  test('no tile is folded till the fold\'s kernels are compiled, and none '
      'by a ledger handed no kernels', () async {
    landed([null], 4);
    kernels = null;
    final bytes = ledger.pool.bytes;
    expect(await ledger.foldABatch(), isFalse);
    await engine.done();
    expect(ledger.pool.bytes, bytes);

    kernels = compiled;
    expect(await ledger.foldABatch(), isTrue);
    expect(ledger.pool.bytes, greaterThan(bytes));

    final bare = EngineTileLedger(engine);
    landedOn(bare, [null], 5);
    final none = bare.pool.bytes;
    expect(await bare.foldABatch(), isFalse);
    await engine.done();
    expect(bare.pool.bytes, none);
  });

  test('a fold the device refuses folds none, and the ledger says there '
      'is no more', () async {
    landed([null], 6);
    engine.debugLose();
    // The pool's own word, past the ledger's look at its engine: the
    // fold was handed over, and failed.
    expect(await ledger.pool.fold(compiled, EngineTileLedger.foldBatch), 0);
    expect(await ledger.foldABatch(), isFalse);
  });

  // The app opens the next engine once this one is gone, and the
  // kernels a ledger of the gone one reads are then the next one's —
  // no job on its own engine may name them.
  test('a ledger whose engine is gone hands no fold over, whatever '
      'kernels it reads', () async {
    landed([null], 6);
    engine.debugLose(forMemory: true);
    expect(engine.isGone, isTrue, reason: '⛔premise');
    final next = GpuEngine.onFirstAdapter();
    final theirs = GpuFold(next);
    addTearDown(() {
      theirs.free();
      next.close();
    });
    kernels = theirs;
    expect(await ledger.foldABatch(), isFalse);
  });

  test('where a launch said so, the tiles landed are folded once nothing '
      'has come for a rest — and the tiles stored', () async {
    EngineTileLedger.foldsAtRest = true;
    final tile = landed([null], 7).single;
    final bytes = ledger.pool.bytes;
    expect(await pollUntil(() => ledger.pool.bytes > bytes), isTrue);
    expect(tile.pixels.toSet(), {7});

    // A ledger of its own, whose tile is stored, not landed.
    final other = EngineTileLedger(engine, foldKernels: () => kernels);
    final stored = aTileOfItsOwn();
    other.held((hold) => hold.slotsOf(EngineTileLedger.landedCel, [stored]));
    final before = other.pool.bytes;
    expect(await pollUntil(() => other.pool.bytes > before), isTrue);
  });

  test('where no launch said so, a rest folds nothing', () async {
    landed([null], 8);
    final bytes = ledger.pool.bytes;
    await Future<void>.delayed(EngineTileLedger.rest * 2);
    await engine.done();
    expect(ledger.pool.bytes, bytes);
  });
}

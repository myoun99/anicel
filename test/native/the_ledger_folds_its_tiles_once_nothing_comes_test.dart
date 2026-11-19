import 'dart:io';

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
/// That its tiles were folded is read off the fold's own word and its
/// pool's bytes, which fall as the pages no tile lies on are given back:
/// the pool tells no more of where a tile lies, and the crate's own pins
/// read its books (rust/src/kernels/pool/folded_tests.rs).
///
/// On an engine and a ledger of the test's own: a device that is gone is
/// gone for its process, and the app has one.
void main() {
  /// The tiles a page of the ledgers here holds, so that a few fill one: a
  /// page with a slot free is its pool's room, and none of its tiles is a
  /// fold's (rust/src/kernels/pool/folded.rs).
  const aPage = 3;

  late GpuEngine engine;
  late EngineTileLedger ledger;
  late GpuFold compiled;
  GpuFold? kernels;

  setUp(() {
    engine = GpuEngine.onFirstAdapter();
    kernels = compiled = GpuFold(engine);
    ledger = EngineTileLedger(
      engine,
      foldKernels: () => kernels,
      debugTilesAPage: aPage,
    );
  });
  // ⚠️The ledger's pool is not freed with its test: a tile collected after
  // it lets its slot go there (the ledger's finalizer), in a later test.
  tearDown(() {
    EngineTileLedger.foldsAtRest = false;
    compiled.free();
    engine.close();
  });

  /// A page of tiles of [value] landed by [by] — the test's ledger where
  /// none is given —, full: its tiles are the next fold's.
  List<BitmapTile> aPageLanded(int value, {EngineTileLedger? by}) =>
      landedOn(by ?? ledger, List<BitmapTile?>.filled(aPage, null), value);

  test('a batch folds the tiles next to fold, the isolate that asks waiting '
      'for no GPU, and each reads as it was — then none is left, and the '
      'pages no tile lies on are the pool\'s no more', () async {
    final tiles = [...aPageLanded(1), ...aPageLanded(2)];

    final (bytes, waits) = (ledger.pool.bytes, debugWaitsHere);
    final onItsWay = ledger.foldABatch();
    expect(ledger.pool.bytes, bytes, reason: 'nothing was waited for');
    expect(await onItsWay, isTrue, reason: 'there may be more');
    expect(debugWaitsHere, waits, reason: 'no wait for the GPU here');

    // A batch here is a page's tiles — a page of folded tiles is as large
    // as one of tiles, and holds as many that fold to no less —, so the
    // second folds the rest: all lie on the one page of folded tiles, and
    // the two of tiles are given back.
    expect(await ledger.foldABatch(), isTrue);
    expect(ledger.pool.bytes, bytes ~/ 2);

    expect(await ledger.foldABatch(), isFalse, reason: 'none is left');
    expect(ledger.pool.bytes, bytes ~/ 2);
    expect(
      [for (final tile in tiles) tile.pixels.toSet()],
      [
        for (final value in [1, 2])
          for (var at = 0; at < aPage; at++) {value},
      ],
    );
  });

  test('no tile is folded till the fold\'s kernels are compiled, and none '
      'by a ledger handed no kernels', () async {
    aPageLanded(4);
    kernels = null;
    expect(await ledger.foldABatch(), isFalse);
    await engine.done();

    // As they were stored: the next fold's.
    kernels = compiled;
    expect(await ledger.foldABatch(), isTrue);

    final bare = EngineTileLedger(engine, debugTilesAPage: aPage);
    aPageLanded(5, by: bare);
    expect(await bare.foldABatch(), isFalse);
    await engine.done();
    // The pool's own word: its tiles are a fold's to take, every one.
    expect(await bare.pool.fold(compiled, EngineTileLedger.foldBatch), aPage);
  });

  test('a fold the device refuses folds none, and the ledger says there '
      'is no more', () async {
    aPageLanded(6);
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
    aPageLanded(6);
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
    // Two pages of them: folded, they lie on one, and theirs go back.
    final tiles = [...aPageLanded(7), ...aPageLanded(7)];
    final bytes = ledger.pool.bytes;
    expect(await pollUntil(() => ledger.pool.bytes < bytes), isTrue);
    expect(
      [for (final tile in tiles) tile.pixels.toSet()],
      everyElement({7}),
    );

    // A ledger of its own, whose tiles are stored, not landed.
    final other = EngineTileLedger(
      engine,
      foldKernels: () => kernels,
      debugTilesAPage: aPage,
    );
    final stored = [for (var at = 0; at < 2 * aPage; at++) aTileOfItsOwn()];
    other.held((hold) => hold.slotsOf(EngineTileLedger.landedCel, stored));
    final before = other.pool.bytes;
    expect(before, bytes, reason: '⛔premise: two pages of them, as above');
    expect(await pollUntil(() => other.pool.bytes < before), isTrue);
  });

  test('a rest folds batch behind batch, till one finds none left', () async {
    // A page of a batch and one tile more: a batch of them, one of the
    // last, and the one that finds none.
    const tiles = EngineTileLedger.foldBatch + 1;
    final counting = _Counting(
      engine,
      foldKernels: () => kernels,
      debugTilesAPage: tiles,
    );
    EngineTileLedger.foldsAtRest = true;
    landedOn(counting, List<BitmapTile?>.filled(tiles, null), 9);
    expect(await pollUntil(() => counting.batches == 3), isTrue);
  });

  test('a launch says so before its first frame', () {
    final launch = File('lib/main.dart').readAsStringSync();
    final said = launch.indexOf('EngineTileLedger.foldsAtRest = true;');
    expect(said, isNonNegative);
    expect(said, lessThan(launch.indexOf('runApp(')));
  });

  test('where no launch said so, a rest asks for no batch', () async {
    final counting = _Counting(
      engine,
      foldKernels: () => kernels,
      debugTilesAPage: aPage,
    );
    aPageLanded(8, by: counting);
    await Future<void>.delayed(EngineTileLedger.rest * 2);
    await engine.done();
    expect(counting.batches, 0);
    // As they were stored: the next fold's.
    expect(await counting.foldABatch(), isTrue);
  });
}

/// A ledger that counts the batches its rests ask for.
class _Counting extends EngineTileLedger {
  _Counting(super.engine, {super.foldKernels, super.debugTilesAPage});

  int batches = 0;

  @override
  Future<bool> foldABatch() {
    batches++;
    return super.foldABatch();
  }
}

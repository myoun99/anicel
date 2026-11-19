import 'dart:async';
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
/// it, so each reads as it was. Where a launch said so
/// (`EngineTileLedger.foldsAtRest`) they are folded a rest after they
/// come, landed or stored: the hand's landings put the folds off, and a
/// store puts none off (🔢브러시/렌더링 2026-11-20, F-610 — a band being
/// made stores at every frame, and its pool stood unfolded till it was
/// full).
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

  /// Every tile a test landed or stored, held till it ends.
  ///
  /// 🚨A TILE COLLECTED LETS ITS SLOT GO (the ledger's finalizer), and a
  /// page with a slot free is its pool's room, none of whose tiles a fold
  /// takes: a test that let go of the tiles it landed waited for a pool
  /// that never fell — once, in a batch beside seven suites (2026-11-19,
  /// the rest that came before the kernels).
  final kept = <BitmapTile>[];

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
    kept.clear();
    EngineTileLedger.foldsAtRest = false;
    compiled.free();
    engine.close();
  });

  /// A page of tiles of [value] landed by [by] — the test's ledger where
  /// none is given —, full: its tiles are the next fold's.
  List<BitmapTile> aPageLanded(int value, {EngineTileLedger? by}) {
    final landed = landedOn(
      by ?? ledger,
      List<BitmapTile?>.filled(aPage, null),
      value,
    );
    kept.addAll(landed);
    return landed;
  }

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

  test('where a launch said so, the tiles landed are folded once the hand '
      'has rested — and the tiles stored, a rest after', () async {
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
    kept.addAll(stored);
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
    kept.addAll(
      landedOn(counting, List<BitmapTile?>.filled(tiles, null), 9),
    );
    expect(await pollUntil(() => counting.batches == 3), isTrue);
  });


  // WHEN the folds come — on a pumped clock, the batches a test's to
  // answer ([_Answered]): the stores and the landings are the engine's
  // own, and no fold of them is.
  group('the folds are asked for a rest after what comes, and only the '
      'hand puts them off', () {
    final beat = EngineTileLedger.rest ~/ 5;
    late _Answered answered;

    setUp(() {
      answered = _Answered(engine, debugTilesAPage: aPage);
      EngineTileLedger.foldsAtRest = true;
    });

    void aStore() {
      final tile = aTileOfItsOwn();
      kept.add(tile);
      answered.held(
        (hold) => hold.slotsOf(EngineTileLedger.landedCel, [tile]),
      );
    }

    void aLanding() => kept.addAll(landedOn(answered, [null], 7));

    /// The batch asked for last is told [folded], and what waits for it
    /// goes on.
    Future<void> told(WidgetTester tester, {required bool folded}) async {
      answered.asked.last.complete(folded);
      await tester.pump();
    }

    /// Every batch still asked is told there is none left, and the rests
    /// asked for pass: a test leaves no timer behind it.
    Future<void> theRestsPass(WidgetTester tester) async {
      EngineTileLedger.foldsAtRest = false;
      for (final batch in answered.asked) {
        if (!batch.isCompleted) {
          batch.complete(false);
        }
      }
      await tester.pump(EngineTileLedger.rest * 2);
    }

    testWidgets('🚨a store puts no fold off: the folds are asked for a rest '
        'after the first store, whatever was stored since', (tester) async {
      for (var store = 0; store < 4; store++) {
        aStore();
        await tester.pump(beat);
      }
      expect(answered.asked, isEmpty, reason: 'a rest is five beats');

      aStore();
      await tester.pump(beat);

      expect(answered.asked, hasLength(1));
      await theRestsPass(tester);
    });

    testWidgets('a landing puts the folds off: they are asked for a rest '
        'after the hand\'s last', (tester) async {
      for (var landing = 0; landing < 6; landing++) {
        aLanding();
        await tester.pump(beat);
      }
      expect(answered.asked, isEmpty, reason: 'the hand landed a beat ago');

      await tester.pump(beat * 4);

      expect(answered.asked, hasLength(1));
      await theRestsPass(tester);
    });

    testWidgets('the folds under way go on through a store, and stop '
        'behind their batch as the hand lands', (tester) async {
      aStore();
      await tester.pump(EngineTileLedger.rest);
      expect(answered.asked, hasLength(1), reason: '⛔premise: under way');

      aStore();
      await told(tester, folded: true);
      expect(answered.asked, hasLength(2), reason: 'a store stops none');

      aLanding();
      await told(tester, folded: true);
      expect(answered.asked, hasLength(2), reason: 'the hand came');

      await tester.pump(EngineTileLedger.rest);
      expect(answered.asked, hasLength(3), reason: 'a rest after it');
      await theRestsPass(tester);
    });

    testWidgets('what is stored once the folds under way asked their last '
        'batch is folded behind them', (tester) async {
      aStore();
      await tester.pump(EngineTileLedger.rest);
      expect(answered.asked, hasLength(1), reason: '⛔premise: under way');
      // Stored as that batch is out, and its rest over before the batch
      // is told: the folds under way never see it.
      aStore();
      await tester.pump(EngineTileLedger.rest);
      expect(answered.asked, hasLength(1), reason: 'one loop at a time');

      await told(tester, folded: false);
      await tester.pump(EngineTileLedger.rest);

      expect(answered.asked, hasLength(2));
      await theRestsPass(tester);
    });
  });

  test('a rest that came before the fold\'s kernels folds once the '
      'ledger is told they are in', () async {
    EngineTileLedger.foldsAtRest = true;
    kernels = null;
    final counting = _Counting(
      engine,
      foldKernels: () => kernels,
      debugTilesAPage: aPage,
    );
    aPageLanded(10, by: counting);
    aPageLanded(10, by: counting);
    final bytes = counting.pool.bytes;
    expect(
      await pollUntil(() => counting.batches == 1),
      isTrue,
      reason: 'the rest asked, and found no kernels',
    );
    await Future<void>.delayed(EngineTileLedger.rest * 2);
    expect(counting.batches, 1, reason: 'and nothing asks again');

    kernels = compiled;
    counting.theFoldKernelsCame();
    expect(await pollUntil(() => counting.pool.bytes < bytes), isTrue);
  });

  test('the launch\'s list tells the app\'s ledger once the fold\'s '
      'kernels are in', () {
    final list = File(
      'lib/src/native/app_kernels_ahead.dart',
    ).readAsStringSync();
    final compiled = list.indexOf('await appGpuFoldKernels.warm();');
    final told = list.indexOf(
      'EngineTileLedger.opened?.theFoldKernelsCame();',
    );
    expect(compiled, isNonNegative);
    expect(told, greaterThan(compiled));
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

/// A ledger whose folds a test answers: each batch a rest asks for waits
/// for its word, and folds nothing.
class _Answered extends EngineTileLedger {
  _Answered(super.engine, {super.debugTilesAPage});

  final asked = <Completer<bool>>[];

  @override
  Future<bool> foldABatch() {
    final batch = Completer<bool>();
    asked.add(batch);
    return batch.future;
  }
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

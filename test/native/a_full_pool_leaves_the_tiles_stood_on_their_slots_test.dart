import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/native/tiles_stood_on.dart';

import '../helpers/collect_garbage.dart';
import '../helpers/tiles_on_the_engine.dart';

/// 🚨THE SLOTS OF THE HOT CELS OF THE FRAME AN EDITOR STANDS ON ARE NOT A
/// FULL POOL'S TO LET GO (card cel-originals-are-held-twice-in-ram-and-on-
/// the-gpu, 2026-11-20 — [TilesStoodOn] has why): a canvas says what it
/// stands on, that is read as a full pool makes its room, and the room is
/// made of the others — the ones stored longest ago that no hold has and
/// no canvas stands on —, past its budget where there are none.
///
/// With a batch of one and no budget, so each store lets go as many slots
/// as it is short and the one that goes is the one stored longest ago
/// (the_engine_keeps_a_slot_of_each_tile_asked_for_test.dart pins that
/// walk).
void main() {
  // Cels by the name a painter gives one.
  const a = (1, 1);
  const b = (1, 2);

  /// A full pool of one page whose ledger asks [stoodOn]: [first] stored
  /// first, then tiles of their own till the page is full, the `rest`.
  ({EngineTileLedger ledger, List<BitmapTile> rest, int page}) aFullPage(
    BitmapTile first, {
    TilesStoodOn? stoodOn,
  }) {
    final ledger = EngineTileLedger(
      appGpuEngine,
      byteBudget: 0,
      roomBatch: 1,
      stoodOn: stoodOn,
    );
    ledger.held((hold) => hold.slotsOf(a, [first]));
    final page = ledger.pool.bytes;
    final rest = [
      for (var tile = ledger.slotCount; tile < page ~/ gpuTileBytes; tile++)
        aTileOfItsOwn(),
    ];
    ledger.held((hold) => hold.slotsOf(a, rest));
    expect(ledger.pool.bytes, page, reason: '⛔premise: one page, full');
    return (ledger: ledger, rest: rest, page: page);
  }

  /// One more tile stored in another cel: a full pool makes room for it.
  void oneMoreStored(EngineTileLedger ledger) =>
      ledger.held((hold) => hold.slotsOf(b, [aTileOfItsOwn()]));

  test('⛔premise: with no canvas standing, the tile stored longest ago is '
      'the one a full pool lets go', () {
    final first = aTileOfItsOwn();
    final (:ledger, :rest, :page) = aFullPage(first, stoodOn: TilesStoodOn());

    oneMoreStored(ledger);

    expect(ledger.slotOf(first), isNull);
    expect(ledger.slotOf(rest.first), isNotNull);
    expect(ledger.pool.bytes, page);
  });

  test('🚨a full pool lets go no slot a canvas stands on: the next stored '
      'longest ago goes', () {
    final canvas = Object();
    final first = aTileOfItsOwn();
    final stoodOn = TilesStoodOn()..standsOn(canvas, () => [first]);
    final (:ledger, :rest, :page) = aFullPage(first, stoodOn: stoodOn);

    oneMoreStored(ledger);

    expect(ledger.slotOf(first), isNotNull, reason: 'the canvas stands on it');
    expect(ledger.slotOf(rest[0]), isNull, reason: 'the next longest ago');
    expect(ledger.slotOf(rest[1]), isNotNull, reason: 'and no more');
    expect(ledger.pool.bytes, page, reason: 'room made, no page');
  });

  test('🚨what a canvas stands on is read as room is made — where it '
      'stands then, not where it stood as it said so', () {
    final canvas = Object();
    final first = aTileOfItsOwn();
    var standsOn = [first];
    final stoodOn = TilesStoodOn()..standsOn(canvas, () => standsOn);
    final (:ledger, :rest, page: _) = aFullPage(first, stoodOn: stoodOn);

    // It went on to another frame: no word of it to anyone.
    standsOn = [rest[0]];
    oneMoreStored(ledger);

    expect(ledger.slotOf(first), isNull, reason: 'stood on no more');
    expect(ledger.slotOf(rest[0]), isNotNull, reason: 'stood on now');
    oneMoreStored(ledger);
    expect(ledger.slotOf(rest[0]), isNotNull);
    expect(ledger.slotOf(rest[1]), isNull, reason: 'the next longest ago');
  });

  test('🚨and read once each time room is made, never where a store fits',
      () {
    final canvas = Object();
    final first = aTileOfItsOwn();
    var asked = 0;
    final stoodOn = TilesStoodOn()
      ..standsOn(canvas, () {
        asked += 1;
        return [first];
      });
    final (:ledger, :rest, page: _) = aFullPage(first, stoodOn: stoodOn);
    // The page itself was made past a budget of none.
    final before = asked;

    // What the pool holds already, asked again: no room to make.
    ledger.held((hold) => hold.slotsOf(a, rest));
    expect(asked, before);

    oneMoreStored(ledger);
    expect(asked, before + 1);
    oneMoreStored(ledger);
    expect(asked, before + 2);
  });

  test('a canvas that says again stands on nothing it said before, and '
      'is asked once', () {
    final canvas = Object();
    final first = aTileOfItsOwn();
    final stoodOn = TilesStoodOn()..standsOn(canvas, () => [first]);
    final (:ledger, :rest, page: _) = aFullPage(first, stoodOn: stoodOn);

    var asked = 0;
    stoodOn.standsOn(canvas, () {
      asked += 1;
      return [rest[0]];
    });
    oneMoreStored(ledger);

    expect(ledger.slotOf(first), isNull);
    expect(ledger.slotOf(rest[0]), isNotNull);
    expect(asked, 1, reason: 'in the list once, however often it says');
  });

  test('🚨the ledger of the app asks the list of the app, and one handed '
      'none asks none', () {
    expect(EngineTileLedger.instance.debugAsks(TilesStoodOn.app), isTrue);
    expect(
      EngineTileLedger(appGpuEngine).debugAsks(TilesStoodOn.app),
      isFalse,
    );
  });

  test('a canvas that stood down stands on nothing', () {
    final canvas = Object();
    final first = aTileOfItsOwn();
    final stoodOn = TilesStoodOn()..standsOn(canvas, () => [first]);
    final (:ledger, rest: _, page: _) = aFullPage(first, stoodOn: stoodOn);

    stoodOn.standDown(canvas);
    oneMoreStored(ledger);

    expect(ledger.slotOf(first), isNull);
  });

  test('one of two canvases standing down leaves the other where it '
      'stands', () {
    final (one, other) = (Object(), Object());
    final first = aTileOfItsOwn();
    final stoodOn = TilesStoodOn();
    final (:ledger, :rest, page: _) = aFullPage(first, stoodOn: stoodOn);
    stoodOn
      ..standsOn(one, () => [first])
      ..standsOn(other, () => [first, rest[1]]);

    stoodOn.standDown(one);
    oneMoreStored(ledger);
    expect(ledger.slotOf(first), isNotNull, reason: 'the other stands on it');
    expect(ledger.slotOf(rest[0]), isNull);

    stoodOn.standDown(other);
    oneMoreStored(ledger);
    expect(ledger.slotOf(first), isNull, reason: 'nobody stands on it');
    expect(ledger.slotOf(rest[1]), isNotNull, reason: 'stored after it');
  });

  test('🚨a canvas that is gone stands on nothing: what it stood on is kept '
      'for no one', () async {
    final first = aTileOfItsOwn();
    final stoodOn = TilesStoodOn();
    late final WeakReference<Object> gone;
    // The canvas lives in this call alone.
    void saidByACanvas() {
      final canvas = Object();
      gone = WeakReference(canvas);
      stoodOn.standsOn(canvas, () => [first]);
    }

    saidByACanvas();
    final (:ledger, :rest, page: _) = aFullPage(first, stoodOn: stoodOn);
    await collectGarbageUntil(() => gone.target == null);
    expect(gone.target, isNull, reason: '⛔premise: the canvas is gone');

    oneMoreStored(ledger);

    expect(ledger.slotOf(first), isNull);
    expect(
      rest.map(ledger.slotOf),
      everyElement(isNotNull),
      reason: 'alive still, and stored after it',
    );
  });

  test('🚨where every slot is stood on, what a call holds is stored past '
      'the budget, and no slot stood on goes', () {
    final canvas = Object();
    final first = aTileOfItsOwn();
    final stoodOn = TilesStoodOn();
    final (:ledger, :rest, :page) = aFullPage(first, stoodOn: stoodOn);
    final all = [first, ...rest];
    stoodOn.standsOn(canvas, () => all);

    oneMoreStored(ledger);

    expect(ledger.pool.bytes, 2 * page, reason: 'a page past the budget');
    expect(all.map(ledger.slotOf), everyElement(isNotNull));
    expect(ledger.slotCount, all.length + 1);
  });

  group('at the line the OS gives', () {
    tearDown(() => EngineTileLedger.debugBeforeRead = null);

    test('🚨the tiles the engine alone holds that a canvas stands on are '
        'not moved here for room: the store goes past the line', () {
      final canvas = Object();
      final stoodOn = TilesStoodOn();
      final ledger = EngineTileLedger(appGpuEngine, stoodOn: stoodOn);
      final theirs = [ledger.debugOnEngine(aTileOfItsOwn())];
      final page = ledger.pool.bytes;
      ledger.debugKeepToOsBudget(0);
      final source = aTileOfItsOwn();
      theirs.addAll([
        for (var tile = 1; tile < page ~/ gpuTileBytes; tile++)
          ledger.debugOnEngine(source),
      ]);
      stoodOn.standsOn(canvas, () => theirs);
      final asked = <int>[];
      EngineTileLedger.debugBeforeRead = (tiles) => asked.add(tiles.length);

      oneMoreStored(ledger);

      expect(asked, isEmpty, reason: 'none read here to let its slot go');
      expect(theirs.every((tile) => tile.isOnlyOnEngine), isTrue);
      expect(theirs.map(ledger.slotOf), everyElement(isNotNull));
      expect(ledger.pool.bytes, 2 * page, reason: 'a page past the line');
    });

    test('🚨and the walk behind a move lets go no slot stood on, its bytes '
        'here or not', () {
      final canvas = Object();
      final stoodOn = TilesStoodOn();
      final ledger = EngineTileLedger(appGpuEngine, stoodOn: stoodOn);
      final kept = aTileOfItsOwn();
      ledger.held((hold) => hold.slotsOf(a, [kept]));
      stoodOn.standsOn(canvas, () => [kept]);
      final page = ledger.pool.bytes;
      ledger.debugKeepToOsBudget(0);
      final source = aTileOfItsOwn();
      final theirs = [
        for (var tile = 1; tile < page ~/ gpuTileBytes; tile++)
          ledger.debugOnEngine(source),
      ];
      final asked = <int>[];
      EngineTileLedger.debugBeforeRead = (tiles) => asked.add(tiles.length);

      oneMoreStored(ledger);

      expect(asked, [EngineTileLedger.readBatch], reason: '⛔premise: moved');
      expect(ledger.slotOf(theirs.first), isNull, reason: 'the oldest went');
      expect(ledger.slotOf(kept), isNotNull, reason: 'stood on, it stays');
      expect(ledger.pool.bytes, page, reason: 'no page past the line');
    });
  });
}

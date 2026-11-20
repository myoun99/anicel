@Tags(['gc'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';

import '../helpers/collect_garbage.dart';
import '../helpers/tiles_on_the_engine.dart';

/// A tile's slot on the engine goes with the tile (screen-on-the-engine
/// c4): its ledger's finalizer lets it go once the collector finds the
/// tile, and a tile whose slot a full pool let go already takes no slot
/// with it — not the one handed out again since — nor keeps a record of
/// it while it lives. What the ledger does
/// while its tiles live is the_engine_keeps_a_slot_of_each_tile_asked_for
/// _test.dart's.
void main() {
  // Cels by the name a painter gives one.
  const a = (1, 1);
  const b = (1, 2);

  /// Till the stores asked so far have read their tiles: a store holds them
  /// till its copy has (GpuPool.store), told of before a done asked behind
  /// it — not left to the collections that follow (🔬the Surface, the
  /// closed project's pin of the_engine_gives_back_the_pages_nobody_holds
  /// _test.dart).
  Future<void> theCopiesRead() => appGpuEngine.done();


  test('a tile collected lets its slot go, for the next to take', () async {
    final ledger = EngineTileLedger(appGpuEngine);
    BitmapTile? tile = aTileOfItsOwn();
    final slot = ledger.held((hold) => hold.slotsOf(a, [tile!]).single);
    await theCopiesRead();
    expect(ledger.slotCount, 1);

    tile = null;
    await collectGarbageUntil(() => ledger.slotCount == 0);

    expect(ledger.slotCount, 0, reason: 'the slot goes with its tile');
    expect(ledger.held((hold) => hold.slotsOf(a, [aTileOfItsOwn()])), [slot]);
  });

  // The first landing compiles the executor: 40 s on a machine this busy.
  const compiles = Timeout(Duration(minutes: 3));

  test('a tile the engine made lets its slot go', timeout: compiles, () async {
    final ledger = EngineTileLedger(appGpuEngine);
    final stroke = GpuStroke(appGpuEngine);
    addTearDown(stroke.free);
    stroke.pile([
      GpuDab(
        centreX: 0,
        centreY: 0,
        left: 0,
        top: 0,
        right: 8,
        bottom: 8,
        colour: 0xFFFFFFFF,
        opacity: 1,
        flow: 1,
        contrast: 1,
      ),
    ]);
    // In a call of its own: a tile is Finalizable, and a method called on
    // it here would keep it alive to the end of this function.
    void landAndDrop() {
      final tile = ledger.land(
        [(column: 0, row: 0, under: null)],
        ofTheHand: true,
        by: (pool, cel, asked) => stroke.land(
          appGpuComposite,
          pool,
          cel,
          asked,
          mode: GpuBlend.normal,
        ),
      ).single.tile;
      expect(tile!.isOnEngine, isTrue);
    }

    landAndDrop();
    expect(ledger.slotCount, 1);

    await collectGarbageUntil(() => ledger.slotCount == 0);

    expect(ledger.slotCount, 0, reason: 'the slot goes with its tile');
  });

  test('a tile let go by a full pool takes no slot with it when collected',
      () async {
    // A batch of one: the one slot the next cel is short of goes, the rest
    // of the page standing to be read below.
    final ledger = EngineTileLedger(
      appGpuEngine,
      byteBudget: 0,
      roomBatch: 1,
    );
    BitmapTile? gone = aTileOfItsOwn();
    final [first] = ledger.held((hold) => hold.slotsOf(a, [gone!]));
    // The rest of its page, so the next cel finds the pool full.
    final slots = ledger.pool.bytes ~/ gpuTileBytes;
    final rest = [for (var n = 1; n < slots; n++) aTileOfItsOwn()];
    ledger.held((hold) => hold.slotsOf(a, rest));
    final kept = aTileOfItsOwn();
    final [slot] = ledger.held((hold) => hold.slotsOf(b, [kept]));
    expect(slot, first, reason: 'the premise: let go, its slot handed out');
    expect(ledger.slotCount, slots);

    gone = null;
    // Bounded: what is waited for must not come.
    await collectGarbageUntil(() => ledger.slotCount != slots, rounds: 3);

    expect(ledger.slotCount, slots, reason: 'its slot went with the full pool');
    // Read here, [rest] is alive past the collection: their slots stand.
    expect(rest.map(ledger.slotOf), everyElement(isNotNull));
    expect(
      ledger.slotOf(kept),
      slot,
      reason: "the slot handed out again is still the kept tile's",
    );
  });

  // Read off the heap, as no pixel tells it: a release one line leaves out
  // is no equivalent (mutant D10, 관제 11-08 07:11).
  test('a tile let go by a full pool keeps no record of its slot while it '
      'lives', () async {
    final ledger = EngineTileLedger(appGpuEngine, byteBudget: 0);
    final lives = aTileOfItsOwn();
    ledger.held((hold) => hold.slotsOf(a, [lives]));
    final record = WeakReference(ledger.recordOf(lives)!);
    final place = ledger.placeOf(lives);
    // The rest of its page, so the next cel finds the pool full.
    final slots = ledger.pool.bytes ~/ gpuTileBytes;
    final rest = [for (var n = 1; n < slots; n++) aTileOfItsOwn()];
    ledger.held((hold) => hold.slotsOf(a, rest));
    ledger.held((hold) => hold.slotsOf(b, [aTileOfItsOwn()]));
    expect(ledger.slotOf(lives), isNull, reason: 'the premise: let go');

    await collectGarbageUntil(() => record.target == null);

    expect(record.target, isNull, reason: 'nothing holds the record');
    // Alive to the end, and stored again in a record of its own — in the
    // place it had: its finalizer is the one attached at its first store.
    ledger.held((hold) => hold.slotsOf(a, [lives]));
    expect(ledger.recordOf(lives), isNotNull);
    expect(ledger.placeOf(lives), same(place));
  });

  // Read off the heap: a walk that left it listed would keep every slot a
  // tile ever took with it, and no count tells.
  test('a slot let go with its tile is swept out by the next walk', () async {
    final ledger = EngineTileLedger(appGpuEngine);
    // In a call of its own, so no tile is alive past it.
    WeakReference<Object> recordOfATileDropped() {
      final tile = aTileOfItsOwn();
      ledger.held((hold) => hold.slotsOf(a, [tile]));
      return WeakReference(ledger.recordOf(tile)!);
    }

    final record = recordOfATileDropped();
    await theCopiesRead();
    await collectGarbageUntil(() => ledger.slotCount == 0);
    expect(ledger.slotCount, 0, reason: 'the premise: let go with its tile');

    ledger.respondToMemoryPressure();
    await collectGarbageUntil(() => record.target == null);

    expect(record.target, isNull, reason: 'the walk swept it out');
  });

  // 🗣️uniform-tiles-take-a-pool-slot-each (관제 2026-11-16): the slot the
  // tiles of a colour share is their colour's block's, and goes with the
  // block — not with one of its tiles.
  test('the tiles of one colour share a slot that goes with the last of '
      'them', () async {
    final ledger = EngineTileLedger(appGpuEngine);
    // A colour no other tile of this test is: its block is these two's.
    const word = 0x5A17C0DE;
    BitmapTile? first = BitmapTile.ofOneColour(size: gpuTileSide, word: word);
    BitmapTile? second = BitmapTile.ofOneColour(
      size: gpuTileSide,
      word: word,
    );
    ledger.held((hold) => hold.slotsOf(a, [first!, second!]));
    await theCopiesRead();
    expect(ledger.slotCount, 1, reason: 'the premise: one slot');

    first = null;
    // Bounded: what is waited for must not come.
    await collectGarbageUntil(() => ledger.slotCount != 1, rounds: 3);
    expect(ledger.slotCount, 1, reason: 'the other tile of it draws on it');
    expect(ledger.slotOf(second), isNotNull);

    second = null;
    await collectGarbageUntil(() => ledger.slotCount == 0);
    expect(ledger.slotCount, 0, reason: 'the slot goes with the colour');
  });
}

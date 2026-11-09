@Tags(['gc'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';

import '../helpers/collect_garbage.dart';

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

  BitmapTile aTile() => BitmapTile.blank(size: gpuTileSide);

  test('a tile collected lets its slot go, for the next to take', () async {
    final ledger = EngineTileLedger(appGpuEngine);
    BitmapTile? tile = aTile();
    final slot = ledger.held((hold) => hold.slotsOf(a, [tile!]).single);
    expect(ledger.slotCount, 1);

    tile = null;
    await collectGarbageUntil(() => ledger.slotCount == 0);

    expect(ledger.slotCount, 0, reason: 'the slot goes with its tile');
    expect(ledger.held((hold) => hold.slotsOf(a, [aTile()])), [slot]);
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
        a,
        stroke,
        [(column: 0, row: 0, under: null)],
        mode: GpuBlend.normal,
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
    final ledger = EngineTileLedger(appGpuEngine, byteBudget: 0);
    BitmapTile? gone = aTile();
    ledger.held((hold) => hold.slotsOf(a, [gone!]));
    // The rest of its page, so the next cel finds the pool full.
    final slots = ledger.pool.bytes ~/ gpuTileBytes;
    final rest = [for (var n = 1; n < slots; n++) aTile()];
    ledger.held((hold) => hold.slotsOf(a, rest));
    final kept = aTile();
    final [slot] = ledger.held((hold) => hold.slotsOf(b, [kept]));
    expect(ledger.slotOf(kept), slot);
    expect(rest.map(ledger.slotOf), everyElement(isNull));
    expect(ledger.slotCount, 1);

    gone = null;
    // Bounded: what is waited for must not come.
    await collectGarbageUntil(() => ledger.slotCount != 1, rounds: 3);

    expect(ledger.slotCount, 1, reason: 'its slot went with the full pool');
    expect(
      ledger.held((hold) => hold.slotsOf(b, [aTile()])),
      isNot([slot]),
      reason: "the slot handed out again is still the kept tile's",
    );
  });

  // Read off the heap, as no pixel tells it: a release one line leaves out
  // is no equivalent (mutant D10, 관제 11-08 07:11).
  test('a tile let go by a full pool keeps no record of its slot while it '
      'lives', () async {
    final ledger = EngineTileLedger(appGpuEngine, byteBudget: 0);
    final lives = aTile();
    ledger.held((hold) => hold.slotsOf(a, [lives]));
    final record = WeakReference(ledger.recordOf(lives)!);
    // The rest of its page, so the next cel finds the pool full.
    final slots = ledger.pool.bytes ~/ gpuTileBytes;
    final rest = [for (var n = 1; n < slots; n++) aTile()];
    ledger.held((hold) => hold.slotsOf(a, rest));
    ledger.held((hold) => hold.slotsOf(b, [aTile()]));
    expect(ledger.slotOf(lives), isNull, reason: 'the premise: let go');

    await collectGarbage();

    expect(record.target, isNull, reason: 'nothing holds the record');
    // Alive to the end, and stored again in a record of its own.
    ledger.held((hold) => hold.slotsOf(a, [lives]));
    expect(ledger.recordOf(lives), isNotNull);
  });
}

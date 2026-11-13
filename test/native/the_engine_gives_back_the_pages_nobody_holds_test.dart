@Tags(['gc'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/drawing_engines.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';

import '../helpers/census_where_textures_are_ram.dart';
import '../helpers/collect_garbage.dart';

/// The ledger gives back the engine's pages nobody holds
/// (pool-pages-given-back): on the memory warning and once a closed
/// project is collected — the C engine's parking with them
/// ([DrawingEngines]) —, and where its budget falls under the pages made.
/// A page a tile is held on stays. Where a page lies, how it is made
/// again, is the engine's own tests' (rust/src/kernels/pool/tests.rs).
///
/// And the engine's pictures, which lie in a pool of their own as the
/// cels' tiles do (engine-pictures-keep-to-pool-pages): the same warning
/// gives back its pages no picture is on, and till then the census
/// counts them. Which page stays is the engine's own tests'
/// (rust/src/kernels/composite/screen_tests.rs).
void main() {
  const a = (1, 1);

  BitmapTile aTile() => BitmapTile.blank(size: gpuTileSide);

  /// A ledger whose one tile was stored and collected, its slot let go: a
  /// page made that nobody holds.
  Future<EngineTileLedger> aPageNobodyHolds(EngineTileLedger ledger) async {
    BitmapTile? tile = aTile();
    ledger.held((hold) => hold.slotsOf(a, [tile!]));
    tile = null;
    await collectGarbageUntil(() => ledger.slotCount == 0);
    expect(ledger.slotCount, 0, reason: 'the premise: its slot let go');
    expect(ledger.pool.bytes, isPositive, reason: 'the premise: a page made');
    return ledger;
  }

  test('a page nobody holds goes back on the memory warning, and a cel '
      'that needs one again has it made', () async {
    final ledger = await aPageNobodyHolds(EngineTileLedger(appGpuEngine));
    final page = ledger.pool.bytes;

    ledger.respondToMemoryPressure();

    expect(ledger.pool.bytes, 0);
    ledger.held((hold) => hold.slotsOf(a, [aTile()]));
    expect(ledger.pool.bytes, page);
  });

  test('a page a tile is held on stays', () {
    final ledger = EngineTileLedger(appGpuEngine);
    final kept = aTile();
    ledger.held((hold) => hold.slotsOf(a, [kept]));
    final page = ledger.pool.bytes;

    ledger.respondToMemoryPressure();

    expect(ledger.pool.bytes, page);
    expect(ledger.slotOf(kept), isNotNull);
  });

  test('a budget falling under the pages gives back those nobody holds, '
      'not one within it', () async {
    final ledger = await aPageNobodyHolds(EngineTileLedger(appGpuEngine));
    final page = ledger.pool.bytes;

    ledger.byteBudget = page;
    expect(ledger.pool.bytes, page, reason: 'within the budget');
    ledger.byteBudget = page - 1;
    expect(ledger.pool.bytes, 0);
  });

  // A closed project's tiles are collected with it, and the give-back its
  // collection brings may land before their finalizers' messages.
  test("a collected tile's page goes back before its finalizer runs, and "
      'the finalizer lets nothing go again', () async {
    final ledger = EngineTileLedger(appGpuEngine);
    BitmapTile? tile = aTile();
    ledger.held((hold) => hold.slotsOf(a, [tile!]));
    tile = null;

    collectGarbageInThisTurn();
    expect(ledger.slotCount, 1, reason: 'the premise: no finalizer ran');
    ledger.respondToMemoryPressure();

    expect(ledger.pool.bytes, 0);
    expect(ledger.slotCount, 0);
    // The slot it had, handed out again before its finalizer runs.
    final kept = aTile();
    ledger.held((hold) => hold.slotsOf(a, [kept]));
    // Bounded: what is waited for must not come.
    await collectGarbageUntil(() => ledger.slotCount != 1, rounds: 3);
    expect(ledger.slotCount, 1, reason: 'its slot went once');
    final other = aTile();
    ledger.held((hold) => hold.slotsOf(a, [other]));
    expect(
      ledger.slotOf(other),
      isNot(ledger.slotOf(kept)),
      reason: "the slot handed out again is still the kept tile's",
    );
  });

  group("the engine's pictures", () {
    /// A screen's canvas composed on the app's engine and let go: a
    /// page of its pictures' pool made that no picture is on.
    void aPictureLetGo() {
      final pool = GpuPool(appGpuEngine, 1 << 30);
      addTearDown(pool.free);
      final plan = GpuPlan(appGpuEngine);
      addTearDown(plan.free);
      const whole = (0, 0, 1, 1);
      plan.solid(0xFF0000FF, 0, 0, 1, 1);
      GpuScreen(appGpuComposite, whole)
        ..compose(pool, plan, whole)
        ..free();
      expect(
        EnginePictures.idlePictureBytes,
        isPositive,
        reason: 'the premise: a page made that no picture is on',
      );
    }

    test('the memory warning gives back what no picture holds', () {
      aPictureLetGo();

      DrawingEngines.respondToMemoryPressure();

      expect(EnginePictures.idlePictureBytes, 0);
    });

    test("the census counts it with the frames' pictures", () {
      addTearDown(DrawingEngines.respondToMemoryPressure);
      int row() => collectMemoryCensusWhereTexturesAreRam(
        const [],
      ).items.firstWhere((item) => item.id == 'framePictures').bytes;
      expect(row(), 0, reason: 'the premise: no session, no picture');

      aPictureLetGo();

      expect(row(), EnginePictures.idlePictureBytes);
    });
  });

  group("the app's ledger", () {
    test('a warning opens none', () {
      expect(EngineTileLedger.opened, isNull, reason: 'the premise');

      DrawingEngines.respondToMemoryPressure();

      expect(EngineTileLedger.opened, isNull);
    });

    test('the memory warning gives its pages nobody holds back', () async {
      await aPageNobodyHolds(EngineTileLedger.instance);

      DrawingEngines.respondToMemoryPressure();

      expect(EngineTileLedger.appPoolBytes, 0);
    });

    test('a closed project collected gives its pages nobody holds back',
        () async {
      Object? project = Object();
      DrawingEngines.giveBackOnceCollected(project);
      BitmapTile? tile = aTile();
      EngineTileLedger.instance.held((hold) => hold.slotsOf(a, [tile!]));
      expect(EngineTileLedger.appPoolBytes, isPositive, reason: 'premise');
      // Both through collections first, as a closed project's surfaces and
      // their tiles are: a holder still young goes in a scavenge before a
      // tile the old space holds, and the give-back its going brings finds
      // the tile's slot held.
      await collectGarbage();

      project = null;
      tile = null;
      await collectGarbageUntil(() => EngineTileLedger.appPoolBytes == 0);

      expect(EngineTileLedger.appPoolBytes, 0);
    });
  });
}

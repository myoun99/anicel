@Tags(['gc'])
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/drawing_engines.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';

import '../helpers/census_where_textures_are_ram.dart';
import '../helpers/collect_garbage.dart';
import '../helpers/tiles_on_the_engine.dart';

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


  /// [tile] stored in [ledger] and read by its copy, as a closed project's
  /// tiles long are: a store holds its tiles till then (GpuPool.store), and
  /// its copy is told of before a done asked behind it.
  ///
  /// ⛔NOT LEFT TO THE COLLECTIONS THAT FOLLOW: where the copy is slower
  /// than they are, a tile dropped is held still, and a give-back that
  /// finds its slot held gives nothing back. 🔬The Surface Pro 11
  /// (2026-11-15): the closed project's pin below, its tile dropped with no
  /// wait, was red 7 runs of 7 — 134217728 bytes of page kept — and green
  /// 3 of 3 with this one; the trunk's machine was green either way.
  Future<void> storedAndRead(EngineTileLedger ledger, BitmapTile tile) async {
    ledger.held((hold) => hold.slotsOf(a, [tile]));
    await appGpuEngine.done();
  }

  /// A ledger whose one tile was stored and collected, its slot let go: a
  /// page made that nobody holds.
  Future<EngineTileLedger> aPageNobodyHolds(EngineTileLedger ledger) async {
    BitmapTile? tile = aTileOfItsOwn();
    await storedAndRead(ledger, tile);
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
    ledger.held((hold) => hold.slotsOf(a, [aTileOfItsOwn()]));
    expect(ledger.pool.bytes, page);
  });

  test('a page a tile is held on stays', () {
    final ledger = EngineTileLedger(appGpuEngine);
    final kept = aTileOfItsOwn();
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
    BitmapTile? tile = aTileOfItsOwn();
    await storedAndRead(ledger, tile);
    tile = null;

    collectGarbageInThisTurn();
    expect(ledger.slotCount, 1, reason: 'the premise: no finalizer ran');
    ledger.respondToMemoryPressure();

    expect(ledger.pool.bytes, 0);
    expect(ledger.slotCount, 0);
    // The slot it had, handed out again before its finalizer runs.
    final kept = aTileOfItsOwn();
    ledger.held((hold) => hold.slotsOf(a, [kept]));
    // Bounded: what is waited for must not come.
    await collectGarbageUntil(() => ledger.slotCount != 1, rounds: 3);
    expect(ledger.slotCount, 1, reason: 'its slot went once');
    final other = aTileOfItsOwn();
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
      final screen = GpuScreen(appGpuComposite, whole);
      unawaited(screen.compose(pool, plan, whole));
      screen.free();
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

    // With a binding: the census reads the image cache's too.
    testWidgets("the census counts it with the frames' pictures", (
      tester,
    ) async {
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
      BitmapTile? tile = aTileOfItsOwn();
      await storedAndRead(EngineTileLedger.instance, tile);
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

    /// Tiles stored in [ledger] past half its first page, so that a page is
    /// made ahead of the next — held [into] alone. In a call of its own: a
    /// suspended async body keeps what its frame held, and a tile kept
    /// there would keep its page.
    void storePastHalfAPage(EngineTileLedger ledger, List<BitmapTile> into) {
      into.add(aTileOfItsOwn());
      ledger.held((hold) => hold.slotsOf(a, into));
      final past = ledger.pool.bytes ~/ gpuTileBytes ~/ 2;
      final rest = [for (var n = 0; n < past; n++) aTileOfItsOwn()];
      ledger.held((hold) => hold.slotsOf(a, rest));
      into.addAll(rest);
    }

    // 🗣️관제 (2026-11-15, a-picture-lay-holds-the-raster-thread): the page
    // its pool makes ahead of the store that needs it is on the census's
    // books with its pages. The pool's own `bytes` leaves it to its budget,
    // and a share of the GPU no row names is what the census is there to
    // end. The census reads this number on its tile pictures' row.
    test('the bytes the census reads count the page made ahead', () async {
      final ledger = EngineTileLedger.instance;
      final held = <BitmapTile>[];
      storePastHalfAPage(ledger, held);
      final page = ledger.pool.bytes;
      await appGpuEngine.done();
      expect(ledger.pool.aheadBytes, page, reason: 'the premise: one made');

      expect(EngineTileLedger.appPoolBytes, 2 * page);

      held.clear();
      await collectGarbageUntil(() => ledger.slotCount == 0);
      DrawingEngines.respondToMemoryPressure();
      expect(EngineTileLedger.appPoolBytes, 0, reason: 'given back with them');
    });
  });
}

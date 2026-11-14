import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/native/qa_memory.dart';
import 'package:anicel/src/native/tile_blocks.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/services/brush_tip_stamp_cache.dart';
import 'package:anicel/src/services/memory_allowance.dart';
import 'package:anicel/src/services/persistence/app_memory_settings.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/cache_budgets.dart';
import 'package:flutter/painting.dart' show ImageCache;

import '../../helpers/poll_until.dart';

/// The memory tab's allowance (유저 2026-09-11): 「RAM/8얘기는 그걸 바탕으로
/// 정해진다던가?」 — every cache budget follows it, and the automatic one is
/// exactly what the app did before anyone could choose.
void main() {
  tearDown(() {
    AppMemory.settings.value = const AppMemorySettings();
  });

  // The framework's image cache is a plain object; a session is handed one
  // the way the screen hands it the binding's.
  final frameworkImageCache = ImageCache();

  EditorSessionManager newSession() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
      frameworkImageCache: frameworkImageCache,
    );
    addTearDown(session.dispose);
    return session;
  }

  /// Every budget at the automatic allowance: the device's, and the laws
  /// scale to it — where the RAM is not said, the laws' own total, so these
  /// ARE the laws.
  CacheBudgets automaticBudgetsOf(EditorSessionManager session) =>
      session.deviceCacheBudgets.toAllowance(session.automaticAllowance);

  test('the automatic allowance sets every budget to its device law, at '
      'the automatic allowance', () {
    final session = newSession();
    expect(
      session.deviceCacheBudgets,
      CacheBudgets.forDevice(
        physicalMemoryBytes: QaMemory.physicalMemoryBytes,
      ),
      reason: "this device's own laws",
    );
    final budgets = automaticBudgetsOf(session);
    expect(
      session.renderCaches.brushFrameStore.hotCelByteBudget,
      budgets.drawings,
    );
    expect(session.historyManager.byteBudget, budgets.undo);
    expect(
      session.playbackRig.playbackCache.playbackCacheByteBudget,
      budgets.playback,
    );
    expect(BrushTipStampCache.instance.byteBudget, budgets.brushTips);
    expect(
      BrushLiveStrokeRasterizer.residentResultByteBudget,
      budgets.liveStroke,
    );
    expect(frameworkImageCache.maximumSizeBytes, budgets.imageCache);
    expect(
      MemoryAllowance.factor.value,
      session.deviceCacheBudgets.factorFor(session.automaticAllowance),
      reason: 'exactly 1 where the RAM is not said; the device\'s factor '
          'where it is',
    );
  });

  test('🚨the sheet-ink stores share ONE cel store worth — each ran on a '
      'desktop 1.5GB of its own, on every device', () {
    final session = newSession();
    final caches = session.renderCaches;
    final stores = {
      caches.conteInkRowStore,
      caches.envelopeInkStore,
      caches.timesheetInkStore,
      caches.viewerInkStore,
    };
    expect(
      caches.sheetInkStores.toSet(),
      stores,
      reason: 'every sheet\'s ink is in the one list the walks read',
    );
    final share = automaticBudgetsOf(session).sheetInk ~/ stores.length;
    for (final store in stores) {
      expect(store.hotCelByteBudget, share);
    }
  });

  test('🚨the sheet-ink stores hear the memory warning too', () {
    final session = newSession();
    final stores = [
      session.renderCaches.conteInkRowStore,
      session.renderCaches.envelopeInkStore,
      session.renderCaches.timesheetInkStore,
      session.renderCaches.viewerInkStore,
    ];
    // A budget well above the halving's floor, so a warning that reaches
    // a store shows as exactly half of it.
    const gb = 1 << 30;
    for (final store in stores) {
      store.hotCelByteBudget = gb;
    }

    session.respondToMemoryPressure();

    for (final store in stores) {
      expect(store.hotCelByteBudget, gb ~/ 2);
    }
  });

  test('🚨a chosen allowance moves EVERY budget by the same factor — and '
      'the automatic one puts them back', () {
    final session = newSession();
    final laws = session.deviceCacheBudgets;
    final automatic = automaticBudgetsOf(session);
    AppMemory.settings.value = AppMemorySettings(
      allowanceBytes: laws.total ~/ 2,
    );

    final half = laws.toAllowance(laws.total ~/ 2);
    expect(
      session.renderCaches.brushFrameStore.hotCelByteBudget,
      half.drawings,
    );
    expect(session.historyManager.byteBudget, half.undo);
    expect(
      session.playbackRig.playbackCache.playbackCacheByteBudget,
      half.playback,
      reason: 'a fixed 600MB that ignored the allowance would make it a lie',
    );
    expect(BrushTipStampCache.instance.byteBudget, half.brushTips);
    expect(
      BrushLiveStrokeRasterizer.residentResultByteBudget,
      half.liveStroke,
    );
    // 유저 2026-09-16 (memory-allowance-Q2): the framework's image cache
    // was ceilinged once by the binding and never moved with the rest.
    expect(frameworkImageCache.maximumSizeBytes, half.imageCache);
    expect(MemoryAllowance.factor.value, closeTo(0.5, 0.001));

    AppMemory.settings.value = const AppMemorySettings();
    expect(
      session.renderCaches.brushFrameStore.hotCelByteBudget,
      automatic.drawings,
    );
    expect(
      session.playbackRig.playbackCache.playbackCacheByteBudget,
      automatic.playback,
    );
    expect(
      MemoryAllowance.factor.value,
      laws.factorFor(session.automaticAllowance),
    );
  });

  test('🚨the allowance caps what the tile blocks\' lists may park, and a '
      'lowered one frees the excess on the spot', () {
    final session = newSession();
    final laws = session.deviceCacheBudgets;
    const length = 64 * 1024;
    TileBlocks.free(TileBlocks.alloc(length));
    expect(
      TileBlocks.parkedBytes,
      greaterThanOrEqualTo(length),
      reason: 'fixture: a freed block parks under the automatic allowance',
    );

    // An allowance at which the lists' line is a kilobyte.
    final small = laws.total ~/ (laws.enginePool ~/ 1024);
    final pool = laws.toAllowance(small).enginePool;
    expect(pool, lessThan(length), reason: 'fixture: under the block');
    AppMemory.settings.value = AppMemorySettings(allowanceBytes: small);

    // 유저 2026-09-16 (memory-allowance-Q2): the lists' cap was a
    // compile-time 512MB, the one number the allowance did not reach.
    expect(TileBlocks.parkedBytes, lessThanOrEqualTo(pool));
  });

  test("a test's own playback budget still wins over the allowance", () {
    final session = newSession();
    session.playbackRig.playbackCache.debugSetPlaybackCacheBudgetBytes(1234);
    AppMemory.settings.value = AppMemorySettings(
      allowanceBytes: session.deviceCacheBudgets.total ~/ 2,
    );
    expect(session.playbackRig.playbackCache.playbackCacheByteBudget, 1234);
  });

  test('the automatic allowance is the device\'s, read once', () {
    // 유저 2026-09-16 (memory-allowance-Q1): by the law
    // automatic_allowance_test pins, from the engine's numbers. ↩️Under
    // flutter_test there was often no C engine, so RAM was unknown and this
    // was the laws' own total; the engine that answers now ships with the
    // app (connection-round-checklist H, 2026-11-08).
    final session = newSession();
    expect(
      session.automaticAllowance,
      automaticAllowanceBytes(
        physicalMemoryBytes: QaMemory.physicalMemoryBytes,
        appMemoryLimitBytes: QaMemory.appMemoryLimitBytes,
        floorBytes: CacheBudgets.floors.total,
        lawsTotalBytes: session.deviceCacheBudgets.total,
      ),
    );
    expect(
      session.automaticAllowance,
      greaterThanOrEqualTo(CacheBudgets.floors.total),
      reason: 'never under the least the app runs on',
    );
  });

  test('under 6GB of RAM the laws and the allowance are that machine\'s, '
      'not a desktop\'s', () {
    // 관제 2026-11-08 16:21: every machine the tests run on has 6GB or more,
    // where the laws stop scaling — a session that read no RAM passed every
    // pin there. A 4GB tablet is where the two part.
    const tablet = 4 * 1024 * 1024 * 1024;
    expect(
      CacheBudgets.forDevice(physicalMemoryBytes: tablet),
      isNot(CacheBudgets.forDevice(physicalMemoryBytes: null)),
      reason: 'fixture: the tablet\'s laws must not be the desktop default',
    );
    QaMemory.debugPhysicalMemoryBytes = () => tablet;
    addTearDown(() => QaMemory.debugPhysicalMemoryBytes = null);
    final session = newSession();
    expect(
      session.deviceCacheBudgets,
      CacheBudgets.forDevice(physicalMemoryBytes: tablet),
    );
    expect(
      session.automaticAllowance,
      automaticAllowanceBytes(
        physicalMemoryBytes: tablet,
        appMemoryLimitBytes: QaMemory.appMemoryLimitBytes,
        floorBytes: CacheBudgets.floors.total,
        lawsTotalBytes: session.deviceCacheBudgets.total,
      ),
    );
  });

  /// F-504: the line rising is room a resting warmer did not have. The user
  /// saw twenty frames go green after moving the allowance — while it
  /// played, when the playhead moving wakes the walk anyway; a line that
  /// rose while nothing played was waiting for the next move.
  testWidgets('a moved allowance has the playback warmer look again', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final session = newSession();
      final scheduler = session.playbackRig.prerenderScheduler;
      var rests = 0;
      scheduler.changes.addListener(() => rests += 1);
      session.warmActiveCut();
      await patiently(scheduler.idle);
      expect(rests, greaterThan(0), reason: 'premise: the walk came to rest');
      final before = rests;

      AppMemory.settings.value = AppMemorySettings(
        allowanceBytes: session.deviceCacheBudgets.total * 2,
      );
      await patiently(scheduler.idle);

      expect(
        rests,
        greaterThan(before),
        reason: 'a walk resting for want of room waits for something to move',
      );
    });
  });

  test('a disposed session stops listening', () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    final automatic = automaticBudgetsOf(session);
    session.dispose();

    AppMemory.settings.value = AppMemorySettings(
      allowanceBytes: session.deviceCacheBudgets.total ~/ 2,
    );

    expect(
      session.renderCaches.brushFrameStore.hotCelByteBudget,
      automatic.drawings,
    );
  });
}

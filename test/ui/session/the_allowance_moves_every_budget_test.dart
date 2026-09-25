import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/services/brush_tip_stamp_cache.dart';
import 'package:anicel/src/services/memory_allowance.dart';
import 'package:anicel/src/services/persistence/app_memory_settings.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/cache_budgets.dart';
import 'package:flutter/painting.dart' show ImageCache;

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

  /// Every budget at the automatic allowance. With no engine that is the
  /// laws' own total, so these ARE the laws; the native parity run loads
  /// one, and then the allowance is the device's and the laws scale to it.
  CacheBudgets automaticBudgetsOf(EditorSessionManager session) =>
      session.deviceCacheBudgets.toAllowance(session.automaticAllowance);

  test('the automatic allowance sets every budget to its device law, at '
      'the automatic allowance', () {
    final session = newSession();
    expect(
      session.deviceCacheBudgets,
      CacheBudgets.forDevice(
        physicalMemoryBytes: QaNativeEngine.instance?.physicalMemoryBytes,
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
      reason: 'exactly 1 with no engine; the device\'s factor with one',
    );
  });

  test('🚨the sheet-ink stores share ONE cel store worth — each ran on a '
      'desktop 1.5GB of its own, on every device', () {
    final session = newSession();
    final caches = session.renderCaches;
    final stores = {
      caches.conteInkRowStore,
      caches.conteInkPageStore,
      caches.envelopeInkStore,
      caches.timesheetInkStripStore,
      caches.timesheetInkPageStore,
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
      session.renderCaches.conteInkPageStore,
      session.renderCaches.envelopeInkStore,
      session.renderCaches.timesheetInkStripStore,
      session.renderCaches.timesheetInkPageStore,
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

  test("a test's own playback budget still wins over the allowance", () {
    final session = newSession();
    session.playbackRig.playbackCache.debugSetPlaybackCacheBudgetBytes(1234);
    AppMemory.settings.value = AppMemorySettings(
      allowanceBytes: session.deviceCacheBudgets.total ~/ 2,
    );
    expect(session.playbackRig.playbackCache.playbackCacheByteBudget, 1234);
  });

  test('the automatic allowance is the device\'s, read once — and with no '
      'engine it is the laws\' own total', () {
    // 유저 2026-09-16 (memory-allowance-Q1). Under flutter_test there is
    // usually no engine: RAM is unknown and the automatic allowance is the
    // sum of the laws, byte for byte — the shape every device law already
    // has. The native parity run loads one, and then it is the device's,
    // by the law automatic_allowance_test pins, from the engine's numbers.
    final session = newSession();
    final engine = QaNativeEngine.instance;
    expect(
      session.automaticAllowance,
      engine == null
          ? session.deviceCacheBudgets.total
          : automaticAllowanceBytes(
              physicalMemoryBytes: engine.physicalMemoryBytes,
              appMemoryLimitBytes: engine.appMemoryLimitBytes,
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

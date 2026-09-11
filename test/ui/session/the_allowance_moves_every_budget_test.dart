import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/services/brush_tip_stamp_cache.dart';
import 'package:anicel/src/services/memory_allowance.dart';
import 'package:anicel/src/services/persistence/app_memory_settings.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/cache_budgets.dart';

/// The memory tab's allowance (유저 2026-09-11): 「RAM/8얘기는 그걸 바탕으로
/// 정해진다던가?」 — every cache budget follows it, and the automatic one is
/// exactly what the app did before anyone could choose.
void main() {
  tearDown(() {
    AppMemory.settings.value = const AppMemorySettings();
  });

  EditorSessionManager newSession() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    return session;
  }

  test('the automatic allowance sets every budget to its device law', () {
    final session = newSession();
    final budgets = session.deviceCacheBudgets;
    expect(
      budgets,
      CacheBudgets.forDevice(
        physicalMemoryBytes: QaNativeEngine.instance?.physicalMemoryBytes,
      ),
      reason: "this device's own laws",
    );
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
    expect(MemoryAllowance.factor.value, 1);
  });

  test('🚨the three sheet-ink stores share ONE cel store worth — each ran '
      'on a desktop 1.5GB of its own, on every device', () {
    final session = newSession();
    final share = session.deviceCacheBudgets.sheetInk ~/ 3;
    for (final store in [
      session.renderCaches.conteInkRowStore,
      session.renderCaches.conteInkPageStore,
      session.renderCaches.envelopeInkStore,
    ]) {
      expect(store.hotCelByteBudget, share);
    }
  });

  test('🚨the sheet-ink stores hear the memory warning too', () {
    final session = newSession();
    final stores = [
      session.renderCaches.conteInkRowStore,
      session.renderCaches.conteInkPageStore,
      session.renderCaches.envelopeInkStore,
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
    final automatic = session.deviceCacheBudgets;
    AppMemory.settings.value = AppMemorySettings(
      allowanceBytes: automatic.total ~/ 2,
    );

    final half = automatic.toAllowance(automatic.total ~/ 2);
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
    expect(MemoryAllowance.factor.value, 1);
  });

  test("a test's own playback budget still wins over the allowance", () {
    final session = newSession();
    session.playbackRig.playbackCache.debugSetPlaybackCacheBudgetBytes(1234);
    AppMemory.settings.value = AppMemorySettings(
      allowanceBytes: session.deviceCacheBudgets.total ~/ 2,
    );
    expect(session.playbackRig.playbackCache.playbackCacheByteBudget, 1234);
  });

  test('a disposed session stops listening', () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    final automatic = session.deviceCacheBudgets;
    session.dispose();

    AppMemory.settings.value = AppMemorySettings(
      allowanceBytes: automatic.total ~/ 2,
    );

    expect(
      session.renderCaches.brushFrameStore.hotCelByteBudget,
      automatic.drawings,
    );
  });
}

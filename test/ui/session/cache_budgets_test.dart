import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/session/cache_budgets.dart';

/// The memory tab's allowance (유저 2026-09-11): every cache budget moves
/// with it, by the same factor, and none goes below what it keeps under a
/// memory warning.
void main() {
  const mb = 1024 * 1024;
  const gb = 1024 * mb;

  test('an unknown device keeps every desktop ceiling, byte for byte', () {
    final budgets = CacheBudgets.forDevice(physicalMemoryBytes: null);
    expect(budgets.drawings, 1536 * mb);
    expect(budgets.undo, HistoryManager.retainedByteBudget);
    expect(budgets.playback, 600 * mb);
    expect(budgets.viewerPages, 1536 * mb ~/ 6);
    expect(budgets.nativeUploads, 640 * mb);
  });

  test('a 3GB tablet gets the device laws — RAM/4 and RAM/8', () {
    final budgets = CacheBudgets.forDevice(physicalMemoryBytes: 3 * gb);
    expect(budgets.drawings, 3 * gb ~/ 4);
    expect(budgets.undo, 3 * gb ~/ 8);
    expect(
      budgets.sheetInk,
      budgets.drawings,
      reason: 'the three ink stores share ONE cel store worth',
    );
  });

  test('the automatic allowance is the budgets themselves — scaling to '
      'their own total changes nothing', () {
    final budgets = CacheBudgets.forDevice(physicalMemoryBytes: 6 * gb);
    expect(budgets.toAllowance(budgets.total), budgets);
  });

  test('🚨EVERY line follows the allowance, fixed ones included', () {
    final budgets = CacheBudgets.forDevice(physicalMemoryBytes: 16 * gb);
    final half = budgets.toAllowance(budgets.total ~/ 2);
    expect(half.drawings, budgets.drawings ~/ 2);
    expect(
      half.playback,
      budgets.playback ~/ 2,
      reason: 'a fixed 600MB that ignored the allowance would make it a lie',
    );
    expect(half.nativeUploads, budgets.nativeUploads ~/ 2);
    // 유저 2026-09-16 (memory-allowance-Q2): 「천장을 걸 수 있는 것은 전부
    // 허용치 안으로」 — the two that sat outside until then.
    expect(half.imageCache, budgets.imageCache ~/ 2);
    expect(half.enginePool, budgets.enginePool ~/ 2);
    expect(half.total, closeTo(budgets.total / 2, 16));

    final doubled = budgets.toAllowance(budgets.total * 2);
    expect(doubled.drawings, budgets.drawings * 2);
    expect(doubled.undo, budgets.undo * 2);
  });

  test('no line goes below what it keeps under a memory warning', () {
    final budgets = CacheBudgets.forDevice(physicalMemoryBytes: 4 * gb);
    final starved = budgets.toAllowance(1);
    expect(starved.drawings, BrushFrameStore.hotCelFloorBytes);
    expect(starved.undo, HistoryManager.retainedByteBudgetUnderPressure);
    expect(starved.total, CacheBudgets.floors.total);
    expect(
      CacheBudgets.floors.total,
      lessThan(budgets.total),
      reason: 'the slider has room below its automatic value',
    );
  });

  test('a holder is ONE line: the census rows it is the ceiling of are its '
      'own, and a row no line names is outside the allowance', () {
    // 유저 2026-09-16: 「타일그림이나 렌더링이나 그런 관련된거 바뀔수있으니
    // 낡지않을구조로」 — the tab asks this, so a cache that gains a ceiling
    // moves inside without a word of UI changing.
    expect(CacheBudgetLine.covers('drawings'), isTrue);
    expect(CacheBudgetLine.covers('layerImages'), isTrue, reason: 'playback');
    expect(CacheBudgetLine.covers('enginePool'), isTrue);
    expect(CacheBudgetLine.covers('imageCache'), isTrue);
    expect(CacheBudgetLine.covers('engineScratch'), isFalse);
    expect(CacheBudgetLine.covers('panelRasters'), isFalse);
    expect(CacheBudgetLine.covers('tileImages'), isFalse);
    // Every line names at least one row, or it is a budget nobody can see.
    for (final line in CacheBudgetLine.values) {
      expect(line.censusIds, isNotEmpty, reason: '$line');
    }
  });
}

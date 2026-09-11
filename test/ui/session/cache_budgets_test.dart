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
}

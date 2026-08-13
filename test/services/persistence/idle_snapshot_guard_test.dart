import 'dart:async';

import 'package:anicel/src/services/persistence/idle_snapshot_guard.dart';
import 'package:flutter_test/flutter_test.dart';

/// The crash guard's rule, which is one sentence and one trap: a snapshot
/// is owed for a BURST OF WORK, not for a stretch of time. The overlay
/// leaves the session dirty on purpose, so anything that rearmed on
/// dirtiness alone would become the periodic timer this round deleted.
void main() {
  /// A scheduler that hands the pending callback back to the test, so idle
  /// time passes exactly when the test says so.
  ({
    IdleSnapshotGuard guard,
    List<int> snapshots,
    void Function() elapse,
    int Function() pending,
  })
  makeGuard() {
    final snapshots = <int>[];
    var pendingCount = 0;
    void Function()? due;
    final guard = IdleSnapshotGuard(
      idleAfter: const Duration(seconds: 15),
      onIdle: () => snapshots.add(snapshots.length),
      scheduler: (duration, callback) {
        expect(duration, const Duration(seconds: 15));
        pendingCount += 1;
        due = callback;
        return Timer(Duration.zero, () {})..cancel();
      },
    );
    return (
      guard: guard,
      snapshots: snapshots,
      elapse: () {
        final callback = due;
        due = null;
        callback?.call();
      },
      pending: () => pendingCount,
    );
  }

  test('going quiet after work snapshots exactly once', () {
    final h = makeGuard();
    h.guard.noteActivity();
    expect(h.guard.isArmed, isTrue);
    h.elapse();
    expect(h.snapshots, hasLength(1));
    expect(h.guard.isArmed, isFalse, reason: 'firing disarms it');
  });

  test('🚨 staying quiet does NOT keep snapshotting', () {
    // The trap. The overlay does not clear the dirty set, so "is there
    // unsaved work?" is still true here. A guard that asked only that
    // would rewrite the same overlay for as long as the user was at lunch
    // — the five-minute clock, renamed.
    final h = makeGuard();
    h.guard.noteActivity();
    h.elapse();
    expect(h.snapshots, hasLength(1));

    // No further activity: nothing more is scheduled, and firing a stale
    // callback writes nothing.
    final scheduledSoFar = h.pending();
    h.elapse();
    h.elapse();
    expect(h.snapshots, hasLength(1), reason: 'an idle machine writes once');
    expect(h.pending(), scheduledSoFar, reason: 'and schedules nothing more');
  });

  test('touching something again owes a new one', () {
    final h = makeGuard();
    h.guard.noteActivity();
    h.elapse();
    h.guard.noteActivity();
    expect(h.guard.isArmed, isTrue);
    h.elapse();
    expect(h.snapshots, hasLength(2));
  });

  test('continuous work pushes the countdown back instead of piling up', () {
    // Input cancels and reschedules; a burst of drawing must not queue a
    // snapshot per pointer event.
    final h = makeGuard();
    for (var i = 0; i < 50; i += 1) {
      h.guard.noteActivity();
    }
    expect(h.snapshots, isEmpty, reason: 'nothing fires while the hand moves');
    h.elapse();
    expect(h.snapshots, hasLength(1), reason: 'one for the whole burst');
  });

  test('a lifecycle snapshot stands the guard down', () {
    // Leaving the app already wrote one. Firing again on return would
    // rewrite what was just written.
    final h = makeGuard();
    h.guard.noteActivity();
    h.guard.standDown();
    expect(h.guard.isArmed, isFalse);
    h.elapse();
    expect(h.snapshots, isEmpty);
  });

  test('standing down does not wedge it — later work still counts', () {
    final h = makeGuard();
    h.guard.noteActivity();
    h.guard.standDown();
    h.guard.noteActivity();
    h.elapse();
    expect(h.snapshots, hasLength(1));
  });

  test('a disposed guard neither arms nor fires', () {
    // The shell disposes on teardown; a countdown outliving the widget
    // would snapshot a session that is gone.
    final h = makeGuard();
    h.guard.noteActivity();
    h.guard.dispose();
    h.elapse();
    expect(h.snapshots, isEmpty);
    h.guard.noteActivity();
    expect(h.guard.isArmed, isFalse);
  });
}

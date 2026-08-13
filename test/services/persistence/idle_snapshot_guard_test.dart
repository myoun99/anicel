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
    void Function() elapseCeiling,
    int Function() pending,
  })
  makeGuard({Duration? ceiling}) {
    const idleAfter = Duration(seconds: 15);
    final snapshots = <int>[];
    var pendingCount = 0;
    // Two countdowns share one scheduler, told apart by their duration —
    // which is also how the test proves the ceiling restarts.
    void Function()? duePause;
    void Function()? dueCeiling;
    final guard = IdleSnapshotGuard(
      idleAfter: idleAfter,
      onSnapshot: () => snapshots.add(snapshots.length),
      scheduler: (duration, callback) {
        pendingCount += 1;
        if (duration == idleAfter) {
          duePause = callback;
        } else {
          dueCeiling = callback;
        }
        return Timer(Duration.zero, () {})..cancel();
      },
    );
    guard.configure(pauseEnabled: true, ceiling: ceiling);
    return (
      guard: guard,
      snapshots: snapshots,
      elapse: () {
        final callback = duePause;
        duePause = null;
        callback?.call();
      },
      elapseCeiling: () {
        final callback = dueCeiling;
        dueCeiling = null;
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

  group('the ceiling', () {
    test('covers the stretch a pause never gets to', () {
      // The reason it exists: a long focused session has no pause, so a
      // pause-only guard protects nothing during exactly the hours that
      // hold the most work.
      final h = makeGuard(ceiling: const Duration(minutes: 10));
      for (var i = 0; i < 200; i += 1) {
        h.guard.noteActivity();
      }
      expect(h.snapshots, isEmpty, reason: 'the hand never stopped');
      h.elapseCeiling();
      expect(h.snapshots, hasLength(1));
    });

    test('🔑 is a ceiling, not a cadence — any snapshot restarts it', () {
      // A pause at 9:50 followed by a tick at 10:00 would write two
      // byte-identical files: nothing happened in between, and the overlay
      // is "what changed since the last manual save". So the ten minutes
      // are counted from the last SNAPSHOT, whoever took it.
      final h = makeGuard(ceiling: const Duration(minutes: 10));
      h.guard.noteActivity();
      final beforePause = h.pending();
      h.elapse();
      expect(h.snapshots, hasLength(1), reason: 'the pause wrote it');
      expect(
        h.pending(),
        greaterThan(beforePause),
        reason: 'the ceiling was rescheduled from now, not left running',
      );
    });

    test('and a ceiling snapshot settles the pause that was armed', () {
      // The mirror image, and the one a deferred fire used to leak.
      final h = makeGuard(ceiling: const Duration(minutes: 10));
      h.guard.noteActivity();
      expect(h.guard.isArmed, isTrue);
      h.elapseCeiling();
      expect(h.snapshots, hasLength(1));
      expect(h.guard.isArmed, isFalse, reason: 'the debt is paid');
      h.elapse();
      expect(h.snapshots, hasLength(1), reason: 'no identical second write');
    });

    test('off means off — no ceiling countdown exists', () {
      final h = makeGuard();
      h.guard.noteActivity();
      h.elapseCeiling();
      expect(h.snapshots, isEmpty);
    });

    test('turning it on starts counting from now, not from app launch', () {
      final h = makeGuard();
      h.guard.configure(
        pauseEnabled: true,
        ceiling: const Duration(minutes: 10),
      );
      h.elapseCeiling();
      expect(h.snapshots, hasLength(1));
    });
  });

  group('a stroke in flight', () {
    test('holds the write until the pen lifts', () {
      // A snapshot reads the cel store on the caller's isolate, so landing
      // one mid-stroke is the cost this repo minds most.
      final h = makeGuard(ceiling: const Duration(minutes: 10));
      h.guard.noteActivity(strokeInFlight: true);
      h.elapseCeiling();
      expect(h.snapshots, isEmpty, reason: 'deferred, not dropped');
      expect(h.guard.isDeferred, isTrue);

      h.guard.noteActivity(strokeInFlight: false);
      expect(h.snapshots, hasLength(1));
      expect(h.guard.isDeferred, isFalse);
    });

    test('a held write still settles the pause it interrupted', () {
      // The leak: the ceiling defers past the stroke, the pen lifts, and
      // the pause nobody cleared writes the same bytes seconds later.
      final h = makeGuard(ceiling: const Duration(minutes: 10));
      h.guard.noteActivity(strokeInFlight: true);
      h.elapseCeiling();
      h.guard.noteActivity(strokeInFlight: false);
      expect(h.snapshots, hasLength(1));
      h.elapse();
      expect(h.snapshots, hasLength(1), reason: 'not twice for one moment');
    });
  });

  group('switching the pause off', () {
    test('stops it firing, and the ceiling carries on alone', () {
      final h = makeGuard(ceiling: const Duration(minutes: 10));
      h.guard.noteActivity();
      h.guard.configure(
        pauseEnabled: false,
        ceiling: const Duration(minutes: 10),
      );
      h.elapse();
      expect(h.snapshots, isEmpty);
      h.elapseCeiling();
      expect(h.snapshots, hasLength(1), reason: 'the other trigger stands');
    });

    test('switching it back on starts owing again', () {
      final h = makeGuard();
      h.guard.configure(pauseEnabled: false, ceiling: null);
      h.guard.noteActivity();
      expect(h.guard.isArmed, isFalse);
      h.guard.configure(pauseEnabled: true, ceiling: null);
      h.guard.noteActivity();
      expect(h.guard.isArmed, isTrue);
      h.elapse();
      expect(h.snapshots, hasLength(1));
    });
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

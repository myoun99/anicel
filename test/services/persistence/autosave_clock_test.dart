import 'dart:async';

import 'package:anicel/src/services/persistence/autosave_clock.dart';
import 'package:flutter_test/flutter_test.dart';

/// **F-1 — autosave is a clock, and that is the whole policy.**
///
/// 유저 2026-08-26: 「**자동저장 on off만 남기고**, 앱 떠날때·손 멈출때
/// 스냅샷 기능 삭제. 심플하게 **명시적저장 / n분주기 자동저장**만 남김」.
///
/// ⚠️This replaces `idle_snapshot_guard_test.dart`. Most of that file
/// tested the PAUSE trigger — armed by activity, disarmed by firing, one
/// write per burst of work — and the pause is gone with the lifecycle
/// snapshot beside it. What survives is the clock and the one thing it
/// still has to get right: never landing a write mid-stroke.
void main() {
  /// A fake scheduler: timers fire when the test says so, so nothing here
  /// waits on real minutes.
  ///
  /// 🚨It has to honour CANCEL. The clock restarts by cancelling and
  /// rescheduling, so a fake that only appends makes "one countdown is
  /// pending" unaskable — and that is precisely what the ceiling tests are
  /// about.
  late List<_Pending> scheduled;
  late int snapshots;

  Timer schedule(Duration duration, void Function() callback) {
    final pending = _Pending(duration, callback);
    scheduled.add(pending);
    return _FakeTimer(() => scheduled.remove(pending));
  }

  AutosaveClock clockOf() => AutosaveClock(
    onSnapshot: () => snapshots += 1,
    scheduler: schedule,
  );

  /// Fires the countdown that is currently pending.
  void fireLatest() {
    final pending = scheduled.removeLast();
    pending.callback();
  }

  setUp(() {
    scheduled = [];
    snapshots = 0;
  });

  group('off means off', () {
    test('a clock with no interval schedules nothing and never fires', () {
      final clock = clockOf()..configure();
      expect(clock.isRunning, isFalse);
      expect(scheduled, isEmpty);
      addTearDown(clock.dispose);
    });

    test('switching it off mid-session stops the countdown', () {
      final clock = clockOf()
        ..configure(interval: const Duration(minutes: 10));
      expect(clock.isRunning, isTrue);

      clock.configure();

      expect(clock.isRunning, isFalse, reason: 'the countdown was cancelled');
      addTearDown(clock.dispose);
    });
  });

  group('the interval', () {
    test('fires after the interval, then starts over', () {
      final clock = clockOf()
        ..configure(interval: const Duration(minutes: 10));
      addTearDown(clock.dispose);

      expect(scheduled.single.duration, const Duration(minutes: 10));
      fireLatest();

      expect(snapshots, 1);
      expect(
        scheduled.single.duration,
        const Duration(minutes: 10),
        reason: 'a fire restarts the count — this is a repeating clock',
      );
    });

    test('🔑 counts from the last SNAPSHOT: a manual save restarts it', () {
      final clock = clockOf()..configure(interval: const Duration(minutes: 10));
      addTearDown(clock.dispose);
      final first = scheduled.single;

      clock.standDown();

      expect(snapshots, 0, reason: 'standing down writes nothing itself');
      expect(scheduled, hasLength(1));
      expect(
        identical(scheduled.single, first),
        isFalse,
        reason:
            'a fresh countdown — ten minutes means "never more than ten '
            'minutes of work at risk", not "write every ten minutes"',
      );
    });

    test('turning it on starts counting from NOW, not from app launch', () {
      final clock = clockOf()..configure();
      addTearDown(clock.dispose);
      expect(scheduled, isEmpty);

      clock.configure(interval: const Duration(minutes: 3));

      expect(scheduled.single.duration, const Duration(minutes: 3));
    });

    test('⛔reconfiguring to the SAME interval does not restart it', () {
      final clock = clockOf()..configure(interval: const Duration(minutes: 10));
      addTearDown(clock.dispose);
      final first = scheduled.single;

      clock.configure(interval: const Duration(minutes: 10));

      expect(
        identical(scheduled.single, first),
        isTrue,
        reason:
            'the settings notifier fires on every unrelated change (a '
            'folder pick), and a clock that reset there would never reach '
            'its own interval',
      );
    });
  });

  group('never mid-stroke', () {
    test('holds the write until the pen lifts', () {
      final clock = clockOf()..configure(interval: const Duration(minutes: 10));
      addTearDown(clock.dispose);

      clock.noteActivity(strokeInFlight: true);
      fireLatest();

      expect(snapshots, 0, reason: 'held, not written');
      expect(clock.isDeferred, isTrue);

      clock.noteActivity();

      expect(snapshots, 1, reason: 'the pen-up released it');
      expect(clock.isDeferred, isFalse);
    });

    test('and the released write restarts the clock like any other', () {
      final clock = clockOf()..configure(interval: const Duration(minutes: 10));
      addTearDown(clock.dispose);

      clock.noteActivity(strokeInFlight: true);
      fireLatest();
      expect(scheduled, isEmpty, reason: 'the fired timer is spent');

      clock.noteActivity();

      expect(scheduled.single.duration, const Duration(minutes: 10));
    });

    test('⛔a pen-up with nothing deferred writes nothing', () {
      final clock = clockOf()..configure(interval: const Duration(minutes: 10));
      addTearDown(clock.dispose);

      clock.noteActivity(strokeInFlight: true);
      clock.noteActivity();

      expect(
        snapshots,
        0,
        reason:
            'activity is not a trigger — the clock is a ceiling on work, '
            'and drawing is what winds it rather than what fires it',
      );
    });

    test('⛔and repeated pen-downs do not pile up deferrals', () {
      final clock = clockOf()..configure(interval: const Duration(minutes: 10));
      addTearDown(clock.dispose);

      clock.noteActivity(strokeInFlight: true);
      clock.noteActivity(strokeInFlight: true);
      fireLatest();
      clock.noteActivity();
      clock.noteActivity();

      expect(snapshots, 1);
    });
  });

  test('a disposed clock neither schedules nor fires', () {
    final clock = clockOf()..configure(interval: const Duration(minutes: 10));
    final pending = scheduled.single;
    clock.dispose();

    expect(clock.isRunning, isFalse);
    pending.callback();
    clock.configure(interval: const Duration(minutes: 3));

    expect(snapshots, 0);
    expect(
      scheduled,
      isEmpty,
      reason: 'dispose cancelled the pending one and scheduled no more',
    );
  });
}

/// One scheduled countdown the test can fire by hand.
class _Pending {
  _Pending(this.duration, this.callback);

  final Duration duration;
  final void Function() callback;
}

/// A [Timer] that only knows how to be cancelled — which is the one thing
/// the clock asks of it.
class _FakeTimer implements Timer {
  _FakeTimer(this._onCancel);

  final void Function() _onCancel;
  bool _active = true;

  @override
  void cancel() {
    _active = false;
    _onCancel();
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

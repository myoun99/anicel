import 'package:anicel/src/services/persistence/autosave_clock.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/due_timers.dart';

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
  /// The clock's timers, fired when the test says so, so nothing here
  /// waits on real minutes.
  ///
  /// 🚨They honour CANCEL ([DueTimers.running]). The clock restarts by
  /// cancelling and rescheduling, so timers that only pile up make "one
  /// countdown is pending" unaskable — and that is precisely what the
  /// ceiling tests are about.
  late DueTimers timers;
  late int snapshots;

  AutosaveClock clockOf() => AutosaveClock(
    onSnapshot: () => snapshots += 1,
    scheduler: timers.arm,
  );

  /// The countdown pending now.
  Due pending() => timers.running.single;

  setUp(() {
    timers = DueTimers();
    snapshots = 0;
  });

  group('off means off', () {
    test('a clock with no interval schedules nothing and never fires', () {
      final clock = clockOf()..configure();
      expect(clock.isRunning, isFalse);
      expect(timers.armed, isEmpty);
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

      expect(pending().after, const Duration(minutes: 10));
      pending().fire();

      expect(snapshots, 1);
      expect(
        pending().after,
        const Duration(minutes: 10),
        reason: 'a fire restarts the count — this is a repeating clock',
      );
    });

    test('🔑 counts from the last SNAPSHOT: a manual save restarts it', () {
      final clock = clockOf()..configure(interval: const Duration(minutes: 10));
      addTearDown(clock.dispose);
      final first = pending();

      clock.standDown();

      expect(snapshots, 0, reason: 'standing down writes nothing itself');
      expect(timers.running, hasLength(1));
      expect(
        identical(pending(), first),
        isFalse,
        reason:
            'a fresh countdown — ten minutes means "never more than ten '
            'minutes of work at risk", not "write every ten minutes"',
      );
    });

    test('turning it on starts counting from NOW, not from app launch', () {
      final clock = clockOf()..configure();
      addTearDown(clock.dispose);
      expect(timers.armed, isEmpty);

      clock.configure(interval: const Duration(minutes: 3));

      expect(pending().after, const Duration(minutes: 3));
    });

    test('⛔reconfiguring to the SAME interval does not restart it', () {
      final clock = clockOf()..configure(interval: const Duration(minutes: 10));
      addTearDown(clock.dispose);
      final first = pending();

      clock.configure(interval: const Duration(minutes: 10));

      expect(
        identical(pending(), first),
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
      pending().fire();

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
      pending().fire();
      expect(timers.running, isEmpty, reason: 'the fired timer is spent');

      clock.noteActivity();

      expect(pending().after, const Duration(minutes: 10));
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
      pending().fire();
      clock.noteActivity();
      clock.noteActivity();

      expect(snapshots, 1);
    });
  });

  test('a disposed clock neither schedules nor fires', () {
    final clock = clockOf()..configure(interval: const Duration(minutes: 10));
    final countdown = pending();
    clock.dispose();

    expect(clock.isRunning, isFalse);
    clock.configure(interval: const Duration(minutes: 3));

    expect(snapshots, 0);
    expect(
      timers.armed,
      [countdown],
      reason: 'it scheduled no more',
    );
    expect(
      countdown.isActive,
      isFalse,
      reason: 'dispose cancelled the pending one',
    );
  });
}

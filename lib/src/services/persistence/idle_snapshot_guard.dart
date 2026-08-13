import 'dart:async';

/// When to snapshot for a crash, given that leaving the app is not the only
/// way work is lost.
///
/// The lifecycle triggers cover the ordinary exits. They cannot cover a
/// SIGSEGV or a dead battery ninety minutes into a session — no callback
/// runs for those, and this project has seen one on a tablet. This is the
/// guard for that case: the app goes quiet, so the work so far is put
/// somewhere it survives.
///
/// 🚨 **Not a clock, and the difference is one flag.** The recovery overlay
/// deliberately does not clear the session's dirty set — adopting refs is
/// exactly what broke incremental saving — so "is there unsaved work?" stays
/// true after a snapshot lands. A guard that rearmed on that alone would
/// rewrite the same overlay every few seconds for as long as the user was
/// away from the desk, which is precisely the five-minute timer this round
/// removed, wearing a different name.
///
/// So the guard is ARMED BY ACTIVITY and DISARMED BY FIRING. One snapshot
/// per burst of work, and none at all until the user touches something
/// again. An idle machine writes nothing, forever.
class IdleSnapshotGuard {
  IdleSnapshotGuard({
    required this.idleAfter,
    required this.onIdle,
    Timer Function(Duration, void Function())? scheduler,
  }) : _schedule = scheduler ?? _realTimer;

  static Timer _realTimer(Duration duration, void Function() callback) =>
      Timer(duration, callback);

  /// How quiet it has to get. Not a setting: the interval field went with
  /// the clock and the on/off switch is the knob that survived. This number
  /// only decides how much of one burst of drawing a crash can cost, and
  /// the write is a delta.
  final Duration idleAfter;

  /// Take a snapshot now. Must not block and must not throw — a guard that
  /// stutters the canvas is paid for by every session to help a rare one.
  final void Function() onIdle;

  final Timer Function(Duration, void Function()) _schedule;

  Timer? _countdown;
  bool _owed = false;
  bool _disposed = false;

  /// Whether a snapshot is still owed for the current burst — the flag the
  /// class exists for, exposed so a test can watch it disarm.
  bool get isArmed => _owed;

  /// The user did something. Push the countdown back and owe a snapshot.
  void noteActivity() {
    if (_disposed) {
      return;
    }
    _owed = true;
    _countdown?.cancel();
    _countdown = _schedule(idleAfter, _fire);
  }

  /// Someone else just snapshotted (a lifecycle trigger), so this one is
  /// no longer owed. Without this the guard would fire again moments after
  /// the app came back, writing what was just written.
  void standDown() {
    _countdown?.cancel();
    _countdown = null;
    _owed = false;
  }

  void dispose() {
    _disposed = true;
    standDown();
  }

  void _fire() {
    _countdown = null;
    if (!_owed || _disposed) {
      return;
    }
    // Disarmed BEFORE the work, not after: [onIdle] is fire-and-forget, so
    // clearing afterwards would leave the flag set for however long the
    // write takes and let a second countdown start behind it.
    _owed = false;
    onIdle();
  }
}

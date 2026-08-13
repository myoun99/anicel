import 'dart:async';

/// When to snapshot for a crash, given that leaving the app is not the only
/// way work is lost.
///
/// The lifecycle triggers cover the ordinary exits. They cannot cover a
/// SIGSEGV or a dead battery ninety minutes into a session — no callback
/// runs for those, and this project has seen one on a tablet. This decides
/// the other two moments:
///
/// - **A pause.** The app goes quiet, so the work so far is put somewhere
///   it survives. Free, in the sense that nobody is drawing.
/// - **A ceiling.** Optional, off by default. A pause-only guard covers
///   nothing during exactly the stretch that carries the most risk: a long
///   focused session never pauses. The ceiling says how much work may be
///   at risk at once.
///
/// 🚨 **A pause is not a clock, and the difference is one flag.** The
/// recovery overlay deliberately does not clear the session's dirty set —
/// adopting refs is exactly what broke incremental saving — so "is there
/// unsaved work?" stays true after a snapshot lands. A guard that rearmed
/// on that alone would rewrite the same overlay every few seconds for as
/// long as the user was away from the desk, which is the five-minute timer
/// this round removed, wearing a different name. So the pause is ARMED BY
/// ACTIVITY and DISARMED BY FIRING: one snapshot per burst of work, and an
/// idle machine writes once and then nothing, forever.
///
/// 🔑 **The ceiling counts from the last SNAPSHOT, not from the last tick.**
/// Every write, whoever asked for it, restarts it. Ten minutes means "never
/// more than ten minutes of work at risk", not "write every ten minutes" —
/// a pause at 9:50 followed by a tick at 10:00 would otherwise write two
/// byte-identical files.
class IdleSnapshotGuard {
  IdleSnapshotGuard({
    required this.idleAfter,
    required this.onSnapshot,
    Timer Function(Duration, void Function())? scheduler,
  }) : _schedule = scheduler ?? _realTimer;

  static Timer _realTimer(Duration duration, void Function() callback) =>
      Timer(duration, callback);

  /// How quiet it has to get before a pause counts. Not a setting: the
  /// number only decides how much of one burst a crash can cost, and the
  /// write is a delta. The knob users asked for is [ceiling], which answers
  /// a different question.
  final Duration idleAfter;

  /// Take a snapshot now. Must not block and must not throw — a guard that
  /// stutters the canvas is paid for by every session to help a rare one.
  final void Function() onSnapshot;

  final Timer Function(Duration, void Function()) _schedule;

  /// Whether a pause is worth a snapshot at all.
  bool pauseEnabled = true;

  /// The longest stretch of work allowed without a snapshot, or null for
  /// "pauses only".
  Duration? ceiling;

  Timer? _pauseCountdown;
  Timer? _ceilingCountdown;
  bool _owed = false;
  bool _disposed = false;

  /// True between pointer-down and pointer-up. A snapshot reads the cel
  /// store on the caller's isolate before handing bytes off, so landing one
  /// mid-stroke is the single cost this repo minds most; the fire is held
  /// until the hand lifts.
  bool _strokeInFlight = false;
  bool _deferredFire = false;

  /// Whether a pause snapshot is still owed for the current burst — the
  /// flag this class exists for, exposed so a test can watch it disarm.
  bool get isArmed => _owed;

  /// Whether a fire is waiting for the stroke to end.
  bool get isDeferred => _deferredFire;

  /// Applies the live policy. Turning the ceiling off stops its countdown;
  /// turning it on starts one from now, because "how long since the last
  /// snapshot" is the only thing it ever measured.
  void configure({required bool pauseEnabled, Duration? ceiling}) {
    if (_disposed) {
      return;
    }
    this.pauseEnabled = pauseEnabled;
    if (!pauseEnabled) {
      _pauseCountdown?.cancel();
      _pauseCountdown = null;
      _owed = false;
    }
    final changed = this.ceiling != ceiling;
    this.ceiling = ceiling;
    if (changed) {
      _restartCeiling();
    }
  }

  /// The user did something. Push the pause back and owe a snapshot.
  void noteActivity({bool strokeInFlight = false}) {
    if (_disposed) {
      return;
    }
    if (strokeInFlight != _strokeInFlight) {
      _strokeInFlight = strokeInFlight;
      if (!strokeInFlight && _deferredFire) {
        _deferredFire = false;
        _snapshot();
        return;
      }
    }
    if (!pauseEnabled) {
      return;
    }
    _owed = true;
    _pauseCountdown?.cancel();
    _pauseCountdown = _schedule(idleAfter, _pauseElapsed);
  }

  /// Someone else just snapshotted (a lifecycle trigger, a manual save), so
  /// nothing is owed and both counts start over.
  void standDown() {
    _pauseCountdown?.cancel();
    _pauseCountdown = null;
    _owed = false;
    _deferredFire = false;
    _restartCeiling();
  }

  void dispose() {
    _disposed = true;
    _pauseCountdown?.cancel();
    _pauseCountdown = null;
    _ceilingCountdown?.cancel();
    _ceilingCountdown = null;
    _owed = false;
    _deferredFire = false;
  }

  void _restartCeiling() {
    _ceilingCountdown?.cancel();
    _ceilingCountdown = null;
    final limit = ceiling;
    if (_disposed || limit == null) {
      return;
    }
    _ceilingCountdown = _schedule(limit, _ceilingElapsed);
  }

  void _pauseElapsed() {
    _pauseCountdown = null;
    if (!_owed || _disposed || !pauseEnabled) {
      return;
    }
    _snapshot();
  }

  void _ceilingElapsed() {
    _ceilingCountdown = null;
    if (_disposed) {
      return;
    }
    _snapshot();
  }

  /// One write, and it settles EVERY outstanding debt.
  ///
  /// Whichever countdown got here, the bytes on disk are the same bytes —
  /// the overlay is "what changed since the last manual save", and no work
  /// happened between two triggers firing moments apart. So a ceiling
  /// snapshot cancels the pause that was already armed, and vice versa,
  /// instead of letting the second one rewrite what the first just wrote.
  ///
  /// This is where a deferred fire used to leak: the ceiling would defer
  /// past a stroke, the pen would lift, and the pause it never cleared
  /// would fire a byte-identical write seconds later.
  void _snapshot() {
    if (_strokeInFlight) {
      // Held, not dropped: the pen-up in [noteActivity] releases it.
      _deferredFire = true;
      return;
    }
    _owed = false;
    _pauseCountdown?.cancel();
    _pauseCountdown = null;
    _restartCeiling();
    onSnapshot();
  }
}

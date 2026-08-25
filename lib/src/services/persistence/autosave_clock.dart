import 'dart:async';

/// 🚨F-1 (유저 2026-08-26): 「심플하게 **명시적저장 / n분주기 자동저장**만
/// 남김」 — the whole autosave policy, which is one number.
///
/// This was `IdleSnapshotGuard`, and it decided two moments: a PAUSE in the
/// work, and a CEILING on how long work could go unprotected. The pause is
/// gone with the lifecycle trigger beside it, so what is left is the clock —
/// and a class named after idling would be a name for something it no
/// longer does.
///
/// 🔑 **The clock counts from the last SNAPSHOT, not from the last tick.**
/// Every write, whoever asked for it, restarts it: a manual save stands the
/// clock down, so ten minutes means "never more than ten minutes of work at
/// risk" rather than "write every ten minutes whatever just happened".
///
/// ⚠️What it CANNOT cover is a stroke in flight. A snapshot reads the cel
/// store on the caller's isolate before handing bytes off, so landing one
/// mid-stroke is the single cost this repo minds most — a tick that arrives
/// while the pen is down is held until the hand lifts.
class AutosaveClock {
  AutosaveClock({
    required this.onSnapshot,
    Timer Function(Duration, void Function())? scheduler,
  }) : _schedule = scheduler ?? _realTimer;

  static Timer _realTimer(Duration duration, void Function() callback) =>
      Timer(duration, callback);

  /// Take a snapshot now. Must not block and must not throw — a clock that
  /// stutters the canvas is paid for by every session to help a rare one.
  final void Function() onSnapshot;

  final Timer Function(Duration, void Function()) _schedule;

  /// The longest stretch of work allowed without a snapshot, or null for
  /// OFF — autosave switched off entirely.
  Duration? interval;

  Timer? _countdown;
  bool _disposed = false;

  /// True between pointer-down and pointer-up.
  bool _strokeInFlight = false;
  bool _deferredFire = false;

  /// Whether a fire is waiting for the stroke to end.
  bool get isDeferred => _deferredFire;

  /// Whether the clock is running at all — a test's window onto "off means
  /// off", and the reason [interval] alone is not enough to ask.
  bool get isRunning => _countdown != null;

  /// Applies the live policy. Turning it off stops the countdown; turning
  /// it on starts one from NOW, because "how long since the last snapshot"
  /// is the only thing it ever measured.
  void configure({Duration? interval}) {
    if (_disposed) {
      return;
    }
    final changed = this.interval != interval;
    this.interval = interval;
    if (changed) {
      _restart();
    }
  }

  /// The user did something.
  ///
  /// The clock does not restart on activity — it is a ceiling on work, and
  /// work is exactly what winds it. What this tracks is the PEN: a fire
  /// held for a stroke is released the moment the hand lifts.
  void noteActivity({bool strokeInFlight = false}) {
    if (_disposed || strokeInFlight == _strokeInFlight) {
      return;
    }
    _strokeInFlight = strokeInFlight;
    if (!strokeInFlight && _deferredFire) {
      _deferredFire = false;
      _snapshot();
    }
  }

  /// Someone else just snapshotted (a manual save), so the count starts
  /// over — the bytes it would have written are already on disk.
  void standDown() {
    _deferredFire = false;
    _restart();
  }

  void dispose() {
    _disposed = true;
    _countdown?.cancel();
    _countdown = null;
    _deferredFire = false;
  }

  void _restart() {
    _countdown?.cancel();
    _countdown = null;
    final limit = interval;
    if (_disposed || limit == null) {
      return;
    }
    _countdown = _schedule(limit, _elapsed);
  }

  void _elapsed() {
    _countdown = null;
    if (_disposed) {
      return;
    }
    _snapshot();
  }

  void _snapshot() {
    if (_strokeInFlight) {
      // Held, not dropped: the pen-up in [noteActivity] releases it.
      _deferredFire = true;
      return;
    }
    _restart();
    onSnapshot();
  }
}

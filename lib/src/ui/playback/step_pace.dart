import 'dart:math' as math;

/// 🚨★★WHEN A STROKE'S STEP IS ASKED: as late as it still goes in before the
/// next frame (F-512, 유저 2026-10-30 「선이 커서 뒤로 처진다」). A step asked at
/// the paint takes what it takes and is shown a frame on, so what the pen
/// did in that frame's first half waits a frame more — and it goes in behind
/// that frame's raster.
///
/// The hold is what the last steps leave of a frame, less [_marginMicros].
/// Where they leave nothing — the levels written with every step, a machine
/// busy with something else, a slower one — there is none, and a step goes
/// at the paint as it did. 🔬Main PC, 144 Hz, a new project, the pen to the
/// ink on the glass, p50 at 300 and 1200 px/s: at 100% 15.8 and 17.0 → 14.2
/// and 15.6 ms, at the fit 17.6 and 18.1 → 16.5 and 15.4, and no later under
/// the test line's load. The Surface Pro 11, input to raster done, p50 at 300
/// and 1200 px/s and p99: at the fit, every level with every step and so no
/// hold, 14.3 and 19.5 → 13.8 and 14.5 ms, p99 the same; at 100% with no
/// level written, 12.4 and 13.2 → 8.0 and 8.2 ms, p99 22–23 → 18–24.
/// ⛔ONE STEP A FRAME, not as each sample comes: that took
/// 11 ms to 7.5 on the main PC, and on the Surface Pro 11 p99 21–28 → 42–59
/// ms at 100% and 39–46 → 340 ms at the fit, the copies out of the GPU one
/// behind the other (2026-10-31).
///
/// The frame is told by the frames themselves: ⛔not the display's rate, which
/// is not this window's vsync where the engine's clock is another screen's
/// (`playback-pacing-knows-one-display-only`).
final class StepPace {
  StepPace({int Function()? nowMicros}) : _now = nowMicros ?? _stopwatch();

  final int Function() _now;
  final List<int> _frames = [];
  final List<int> _takes = [];
  int? _lastFrame;
  int _due = 0;
  int _from = 0;

  /// How many frames and steps the pace is told by. Fewer say nothing.
  static const int _remembered = 4;

  /// What a step asked late is given over what the last ones took: a timer
  /// came 0.8 ms late at the median, 2.6 at p99. 🔬2 ms gave the gain back
  /// (at the fit 18.8 and 17.5 ms) and no steadier frames.
  static const int _marginMicros = 1000;

  /// Under this a timer is no earlier than the paint's own ask.
  static const int _leastHoldMicros = 500;

  /// The frame at [frame] is painting: a screen with nothing new paints
  /// twice in none, and the gaps a pause leaves are out by the shortest.
  void painted(Duration frame) {
    final at = frame.inMicroseconds;
    final last = _lastFrame;
    _lastFrame = at;
    if (last != null && at > last) {
      _remember(_frames, at - last);
    }
  }

  /// How long the step this paint would ask for is to hold. What it takes
  /// is counted from there ([asked]), so a timer's lateness is in it.
  Duration ask() {
    final hold = _hold;
    _due = _now() + hold.inMicroseconds;
    return hold;
  }

  /// Whether a step asked now would be held: whether the last steps leave
  /// a frame anything.
  bool get holds => _hold != Duration.zero;

  /// A step is to go now.
  void askNow() => _due = _now();

  Duration get _hold {
    if (_frames.length < _remembered || _takes.length < _remembered) {
      return Duration.zero;
    }
    final left =
        _frames.reduce(math.min) - _takes.reduce(math.max) - _marginMicros;
    return left < _leastHoldMicros
        ? Duration.zero
        : Duration(microseconds: left);
  }

  /// A step went: from when it was due, or from now if it went before that.
  void asked() => _from = math.min(_due, _now());

  /// The step that went last is in.
  void landed() => _remember(_takes, _now() - _from);

  void _remember(List<int> list, int micros) {
    list.add(micros);
    if (list.length > _remembered) {
      list.removeAt(0);
    }
  }

  static int Function() _stopwatch() {
    final clock = Stopwatch()..start();
    return () => clock.elapsedMicroseconds;
  }
}

/// A moment on the frame clock — the clock the engine's frame times are on
/// — on the audio device's clock: carried across by the difference between
/// the two clocks, READ SIDE BY SIDE.
///
/// 🚨THE CLOCK IS READ AT THE MOMENT ITS FRAME IS SHOWN (`frameShownAt`),
/// NOT WHEN THE TICK RUNS (the-clock-is-read-when-the-tick-runs). A tick
/// runs a little after its frame begins, and by a different amount each
/// time (🔬profile 10-10, this machine: 2.4–15.7ms after the vsync, 7.5–9.1
/// for most). A film frame whose start fell inside that spread could change
/// on one refresh or the next depending on how late the tick happened to
/// run — a frame five refreshes long beside one seven long, where six were
/// due. Read at the moment its frame is shown, every tick of a frame
/// answers alike, and what the picture shows is what is heard as it is
/// seen.
///
/// 🚨THE GAP IS THE TWO CLOCKS' OWN DIFFERENCE: the device's clock as the
/// tick reads it, and the frame clock read straight after. The second read
/// comes after the first, so a read can only make the difference look
/// smaller than it is — the gap is the LARGEST a recent pair has said, as
/// the device's line is the highest its callbacks lie on
/// ([DeviceClockLine]). It rises at once to a pair that says more, and
/// otherwise sinks a thousandth of the frame-clock time that passes —
/// enough to follow a device clock a hair slower than the engine's.
/// 🔬On Windows the two are one clock (the performance counter): the gap
/// is a microsecond or so.
///
/// ↩️It was the difference between the device's clock as a tick ran and the
/// FRAME'S TIME — two moments, not one: every tick's lateness came into it,
/// at first averaged (a sixteenth of each tick) and then as its lowest
/// edge. That read the picture where the tick ran, which was the sound's
/// match only because the user's ear had matched it there
/// (C-playback-frames-on-their-time ③, 유저 확인 10-09); and on Windows,
/// where the engine's frame times are a grid of its own that jumps, it
/// carried every jump into what the clock said.
final class FrameTimeOnDevice {
  /// How fast the gap sinks while no pair says more: a microsecond for
  /// every millisecond of frame-clock time (1000ppm).
  static const int _sinksPerMicros = 1000;

  /// The gap, device clock minus frame clock, in microseconds — null until
  /// a pair has said one.
  int? _gap;

  /// The frame-clock time the gap was last carried to.
  int? _lastFrameNowMicros;

  /// Where frame-clock moment [frameMicros] stands on the device's clock —
  /// the device's clock reading [deviceNowMicros], and the frame clock
  /// [frameNowMicros] straight after.
  int onDevice({
    required int deviceNowMicros,
    required int frameNowMicros,
    required int frameMicros,
  }) {
    final said = deviceNowMicros - frameNowMicros;
    final gap = _gap;
    final last = _lastFrameNowMicros;
    final int followed;
    if (gap == null || said >= gap) {
      followed = said;
    } else {
      final passed = last == null || frameNowMicros < last
          ? 0
          : frameNowMicros - last;
      final sunk = gap - passed ~/ _sinksPerMicros;
      followed = sunk > said ? sunk : said;
    }
    _gap = followed;
    _lastFrameNowMicros = frameNowMicros;
    return frameMicros + followed;
  }
}

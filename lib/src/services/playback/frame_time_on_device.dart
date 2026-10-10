/// The time a frame is read at, on the audio device's clock: the frame's
/// own time — the engine's, one for every read in that frame — carried onto
/// the device's clock by the gap between the two as the ticks have seen it.
///
/// 🚨THE CLOCK IS READ AT THE FRAME'S TIME, NOT WHEN THE TICK RUNS
/// (the-clock-is-read-when-the-tick-runs). A tick runs a little after its
/// frame begins, and by a different amount each time (🔬profile 10-10, this
/// machine: 2.4–15.7ms after the vsync, 7.5–9.1 for most). A film frame
/// whose start fell inside that spread could change on one refresh or the
/// next depending on how late the tick happened to run — a frame five
/// refreshes long beside one seven long, where six were due. Read at the
/// frame's own time, every tick of a frame answers alike.
///
/// The gap is FOLLOWED, not fixed: it is whatever the two clocks and the
/// ticks' lateness make it, smoothed over the ticks, so on average the
/// clock reads where it read before — what the sound and the picture were
/// matched by (C-playback-frames-on-their-time ③, 유저 확인 10-09) — and a
/// device clock that is not the engine's (another epoch, or a hair another
/// rate) is followed as it goes. 🔬On Windows the two are one clock (QPC):
/// the device's `qa_audio_clock_now_us` and the engine's frame times stood a
/// tick's lateness apart, frame after frame.
final class FrameTimeOnDevice {
  /// How much of each new gap the followed one takes.
  static const int _follows = 16;

  /// The gap, device clock minus frame time, in microseconds — null until a
  /// tick has said one.
  double? _gap;

  /// Where frame time [frameMicros] stands on the device's clock, the device
  /// reading [deviceNowMicros] as the tick runs.
  int onDevice({required int deviceNowMicros, required int frameMicros}) {
    final seen = (deviceNowMicros - frameMicros).toDouble();
    final gap = _gap;
    final followed = gap == null ? seen : gap + (seen - gap) / _follows;
    _gap = followed;
    return frameMicros + followed.round();
  }
}

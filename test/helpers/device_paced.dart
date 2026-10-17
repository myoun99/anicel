import 'package:anicel/src/native/qa_audio_device.dart';

// 🚨★★THE DEVICE KEEPS THE TIME, NOT THE WALL (transport-real-time-pins-fail-
// under-load, 2026-10-17). A null device is a thread, and its callback runs
// when the machine gets round to it: under five and six suites at once a
// starved one went two frames in four seconds and none in 450ms, and a
// one-second wait slept three and a half. Four pins failed so — in two land
// gates and a lane's run, every one in its PREMISE, never in the product. So
// a wait on what a device does lasts as long as the device takes to do it,
// a stretch of a device's run is counted in what the device was handed, and
// the wall bounds only a device that never goes. ↩️Five suites each kept a
// copy of a wait that gave up at three seconds of the wall.

/// The wall's bound: a device that has not got there in this is stopped,
/// not slow — five times the longest starving measured, and inside a
/// test's own thirty seconds.
const deviceStoppedAfter = Duration(seconds: 20);

/// What the device has handed since this was made, off its clock line
/// ([QaAudioDevice.clockPoint]: a callback's samples, and when it was asked).
///
/// 🚨A STEP THE LINE'S OWN TIME COULD NOT HAVE PLAYED IS NOT PLAYING
/// (10-17). A loop's wrap goes back, and a seek or a re-arm jumps: the roll
/// a take starts at track frame 21 jumped 252,000 samples, and counted as
/// handed it ended a 0.6s wait before the anchor was heard. Such a step is
/// dropped — the count is short by what was handed across it, and over by
/// at most a jump inside [_slack]. Read it often.
final class Handed {
  Handed(this._device) : _last = _device.clockPoint;

  /// A callback asked early, or two run back to back after a starved
  /// stretch: two and a half of the device's 10ms blocks (miniaudio's
  /// low-latency period, which nothing here overrides).
  static const _slack = Duration(milliseconds: 25);

  final QaAudioDevice _device;
  ({int positionSamples, int atMicros})? _last;
  int _samples = 0;

  int get samples {
    final now = _device.clockPoint;
    final last = _last;
    _last = now;
    if (now == null || last == null) {
      return _samples;
    }
    final step = now.positionSamples - last.positionSamples;
    final playable =
        (now.atMicros - last.atMicros + _slack.inMicroseconds) *
        _device.sampleRate ~/
        Duration.microsecondsPerSecond;
    if (step >= 0 && step <= playable) {
      _samples += step;
    }
    return _samples;
  }
}

/// Waits until [check] holds, looking every 10ms — until [device] has
/// handed [budget] of its own run without it holding, or has stood for
/// [deviceStoppedAfter] by the wall. A [device] that is not playing hands
/// nothing, so a wait on the microphone has the wall's bound alone.
///
/// Answers whether [check] held: a wait that expects it NOT to — "for this
/// much of the device's run, it never" — reads false.
Future<bool> waitOnTheDevice(
  QaAudioDevice device,
  bool Function() check, {
  Duration budget = const Duration(seconds: 3),
}) async {
  final handed = Handed(device);
  final samples =
      budget.inMicroseconds *
      device.sampleRate ~/
      Duration.microsecondsPerSecond;
  final wall = Stopwatch()..start();
  while (wall.elapsed < deviceStoppedAfter && handed.samples < samples) {
    if (check()) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return check();
}

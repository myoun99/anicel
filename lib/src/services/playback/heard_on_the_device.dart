import 'dart:developer' show Timeline;

import 'device_clock_line.dart';
import 'frame_time_on_device.dart';

/// Where a LISTENER is on a device's run — the sample being heard — at the
/// moment a frame is shown: the line through the device's stair
/// ([DeviceClockLine]) where it stands now, carried on at the device's
/// rate to that moment on the device's clock ([FrameTimeOnDevice]), less
/// what the device still holds to play — its latency — and with the user's
/// own correction on top, folded into the lap last
/// ([DeviceClockLine.foldedIntoTheLap]).
///
/// 🚨ONE READING for everything that puts a picture beside a device's
/// sound — the canvas's transport and the media viewer's sound
/// (viewer-plays-by-the-one-playback-law ④-b). ↩️The viewer read the
/// samples HANDED to the device, the stair, as its tick ran: its picture
/// ran ahead of what was heard by the device's latency, and the user's
/// correction never reached it.
///
/// 🚨THE LINE IS READ NOW AND CARRIED ON TO THE MOMENT. A frame is shown a
/// little after its tick runs (`frameShownAt` — two or three refreshes, on
/// Windows), and the device will have been handed more by then: read AT
/// that moment, the line would be held back by what the device holds now
/// ("never ahead of the sound" — its guard against a device whose
/// callbacks have stopped). Read now, every guard of the line keeps its
/// meaning, and what the device plays in between is its rate.
final class HeardOnTheDevice {
  /// [frameClockNow] reads the frame clock — the clock the engine's frame
  /// times are on (Dart's timeline clock, which the engine takes them
  /// from); a test hands its own.
  HeardOnTheDevice({int Function()? frameClockNow})
    : _frameClockNow = frameClockNow ?? _timelineNow;

  static int _timelineNow() => Timeline.now;

  final int Function() _frameClockNow;
  final DeviceClockLine _line = DeviceClockLine();
  final FrameTimeOnDevice _frameTime = FrameTimeOnDevice();
  int _deviceRate = 0;

  /// The device was started afresh ([DeviceClockLine.arm]).
  void arm({
    required int deviceRate,
    required int carriesFor,
    int lapSamples = 0,
  }) {
    _deviceRate = deviceRate;
    _line.arm(
      deviceRate: deviceRate,
      carriesFor: carriesFor,
      lapSamples: lapSamples,
    );
  }

  /// The sample heard at [frameTime] — the moment the frame the reading is
  /// for is shown, on the frame clock — or at [clock]'s own time without
  /// one. Short of the arm's first sample while the device's latency
  /// drains.
  int heard(
    DeviceClockReading clock, {
    Duration? frameTime,
    required int latencySamples,
    required int userOffsetSamples,
  }) {
    var count = _line.read(clock);
    if (frameTime != null) {
      final onTheDevice = _frameTime.onDevice(
        deviceNowMicros: clock.nowMicros,
        frameNowMicros: _frameClockNow(),
        frameMicros: frameTime.inMicroseconds,
      );
      count +=
          (onTheDevice - clock.nowMicros) *
          _deviceRate ~/
          Duration.microsecondsPerSecond;
    }
    // What is HEARD trails the count by the device's latency (the user's
    // own correction on top) — taken off BEFORE the count is folded into
    // the loop: the lap that is heard is not the lap that is handed.
    return _line.foldedIntoTheLap(count - latencySamples + userOffsetSamples);
  }
}

import 'device_clock_line.dart';
import 'frame_time_on_device.dart';

/// Where a LISTENER is on a device's run — the sample being heard — at the
/// time a frame is shown: the line through the device's stair
/// ([DeviceClockLine]), read where the frame's time stands on the device's
/// clock ([FrameTimeOnDevice]), less what the device still holds to play —
/// its latency — and with the user's own correction on top, folded into the
/// lap last ([DeviceClockLine.foldedIntoTheLap]).
///
/// 🚨ONE READING for everything that puts a picture beside a device's
/// sound — the canvas's transport and the media viewer's sound
/// (viewer-plays-by-the-one-playback-law ④-b). ↩️The viewer read the
/// samples HANDED to the device, the stair, as its tick ran: its picture
/// ran ahead of what was heard by the device's latency, and the user's
/// correction never reached it.
final class HeardOnTheDevice {
  final DeviceClockLine _line = DeviceClockLine();
  final FrameTimeOnDevice _frameTime = FrameTimeOnDevice();

  /// The device was started afresh ([DeviceClockLine.arm]).
  void arm({
    required int deviceRate,
    required int carriesFor,
    int lapSamples = 0,
  }) => _line.arm(
    deviceRate: deviceRate,
    carriesFor: carriesFor,
    lapSamples: lapSamples,
  );

  /// The sample heard at [frameTime] — the frame the reading is for — or
  /// at [clock]'s own time without one. Short of the arm's first sample
  /// while the device's latency drains.
  int heard(
    DeviceClockReading clock, {
    Duration? frameTime,
    required int latencySamples,
    required int userOffsetSamples,
  }) {
    final count = _line.read((
      point: clock.point,
      stairSamples: clock.stairSamples,
      nowMicros: frameTime == null
          ? clock.nowMicros
          : _frameTime.onDevice(
              deviceNowMicros: clock.nowMicros,
              frameMicros: frameTime.inMicroseconds,
            ),
    ));
    // What is HEARD trails the count by the device's latency (the user's
    // own correction on top) — taken off BEFORE the count is folded into
    // the loop: the lap that is heard is not the lap that is handed.
    return _line.foldedIntoTheLap(count - latencySamples + userOffsetSamples);
  }
}

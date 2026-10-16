import 'dart:developer' show Timeline;
import 'dart:math' as math;

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
///
/// 🚨NEVER A STEP BACK — only the fold into the lap goes back (F-364, 유저
/// 2026-10-15: 「재생중에, 아직 초록바가 안된 곳으로, 초록바가 차기
/// 시작하는곳으로 재생헤드가 점프해버려서 거기서 재생되는 버그」). A
/// playhead takes a reading that steps back for the lap wrapping
/// (`playheadWay`): it walks on round the end, and where the clock waits for
/// a picture it stands before the first frame not made yet — on the green
/// bar's last. Every stage of this reading can step back: the line where its
/// highest point grows old ([DeviceClockLine]), and the moment it is
/// carried on to, which is estimated afresh at every look — when a run's
/// scenes turn short after long ones the vblank claims start again on an
/// earlier vblank (`PresentClaims`; 🔬one look in 120,716 on the glass went
/// back a whole film frame, 41.7ms). So what is kept is the furthest sample
/// heard under the arm, counted on through every lap, and the fold is the
/// last thing done to it. ↩️The line kept the furthest count it read, and
/// everything done to that count after was free to go back.
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

  /// The furthest sample heard under this arm, counted on through every
  /// lap — null until the arm's first reading.
  int? _furthest;

  /// The device was started afresh ([DeviceClockLine.arm]): what was heard
  /// before is of another run.
  void arm({
    required int deviceRate,
    required int carriesFor,
    int lapSamples = 0,
  }) {
    _deviceRate = deviceRate;
    _furthest = null;
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
    // Taken off BEFORE the count is folded into the loop: the lap that is
    // heard is not the lap that is handed.
    final heard = _heardOf(count, latencySamples, userOffsetSamples);
    final furthest = _furthest = math.max(_furthest ?? heard, heard);
    return _line.foldedIntoTheLap(furthest);
  }

  /// The sample heard at [clock]'s own time, counted on through every lap —
  /// the reading of one who LISTENS rather than one who shows: a take placed
  /// by the moment its anchor was heard (`AudioRecorder.capturedAt`). Not
  /// held to the furthest a picture's reading got (those are read at the
  /// moments frames are shown, ahead of now) and not folded into the lap.
  int heardNow(
    DeviceClockReading clock, {
    required int latencySamples,
    required int userOffsetSamples,
  }) => _heardOf(_line.read(clock), latencySamples, userOffsetSamples);

  /// What is HEARD of a [count] handed: it trails the count by the device's
  /// latency, and the user's own correction is on top.
  static int _heardOf(int count, int latencySamples, int userOffsetSamples) =>
      count - latencySamples + userOffsetSamples;
}

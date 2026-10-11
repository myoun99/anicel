import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/playback/device_clock_line.dart';
import 'package:anicel/src/services/playback/heard_on_the_device.dart';

/// Where a listener is at the moment a frame is SHOWN: the device's line
/// read now, carried on at the device's rate to that moment on the device's
/// clock — the frame clock's moment moved across by the two clocks' own
/// difference.
void main() {
  const rate = 48000;

  /// A device that handed [handed] samples at device time 1s, read at
  /// [nowMicros] on its own clock.
  DeviceClockReading readAt(int nowMicros, {int handed = 48000}) => (
    point: (positionSamples: handed, atMicros: 1000000),
    stairSamples: handed,
    nowMicros: nowMicros,
  );

  test('🚨a moment after now is the count now, carried on to it at the '
      'device\'s rate', () {
    final heard = HeardOnTheDevice(frameClockNow: () => 1010000)
      ..arm(deviceRate: rate, carriesFor: 4800);
    final now = heard.heard(
      readAt(1010000),
      latencySamples: 0,
      userOffsetSamples: 0,
    );
    final shown = heard.heard(
      readAt(1010000),
      frameTime: const Duration(microseconds: 1030000),
      latencySamples: 0,
      userOffsetSamples: 0,
    );
    expect(shown - now, 960, reason: 'twenty milliseconds on, at 48k');
  });

  test('🚨the moment is moved onto the device\'s clock by the two clocks\' '
      'own difference', () {
    // The device's clock stands 5ms ahead of the frame clock.
    final heard = HeardOnTheDevice(frameClockNow: () => 1005000)
      ..arm(deviceRate: rate, carriesFor: 4800);
    final atNow = heard.heard(
      readAt(1010000),
      frameTime: const Duration(microseconds: 1005000),
      latencySamples: 0,
      userOffsetSamples: 0,
    );
    final read = heard.heard(
      readAt(1010000),
      latencySamples: 0,
      userOffsetSamples: 0,
    );
    expect(atNow, read, reason: 'the frame clock\'s now is the device\'s now');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/playback/frame_time_on_device.dart';

/// THE CLOCK IS READ AT THE FRAME'S TIME (the-clock-is-read-when-the-tick-
/// runs): where a frame's time stands on the device's clock, the gap
/// between the two followed over the ticks.
void main() {
  test('a steady gap is read exactly: the frame\'s time and the gap', () {
    final clock = FrameTimeOnDevice();
    for (var frame = 0; frame < 20; frame += 1) {
      final at = 1000000 + frame * 6944;
      expect(
        clock.onDevice(deviceNowMicros: at + 8000, frameMicros: at),
        at + 8000,
      );
    }
  });

  test('🚨a tick that runs late reads where one on time reads — a sixteenth '
      'of its lateness, not all of it', () {
    final clock = FrameTimeOnDevice();
    var at = 1000000;
    for (var frame = 0; frame < 64; frame += 1) {
      at += 6944;
      clock.onDevice(deviceNowMicros: at + 8000, frameMicros: at);
    }
    at += 6944;
    final late = clock.onDevice(
      deviceNowMicros: at + 8000 + 6400,
      frameMicros: at,
    );
    expect(
      late - (at + 8000),
      lessThanOrEqualTo(6400 ~/ 16 + 1),
      reason: 'read when the tick ran, the frame would read 6.4ms on — '
          'nearly a refresh at 144Hz',
    );
  });

  test('the gap is followed: a device clock that moves away from the '
      'engine\'s is read where it has got to', () {
    final clock = FrameTimeOnDevice();
    var at = 1000000;
    var read = 0;
    for (var frame = 0; frame < 400; frame += 1) {
      at += 6944;
      read = clock.onDevice(
        deviceNowMicros: at + 5000 + frame * 5,
        frameMicros: at,
      );
    }
    expect((read - (at + 5000 + 399 * 5)).abs(), lessThan(100));
  });
}

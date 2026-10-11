import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/playback/frame_time_on_device.dart';

/// THE CLOCK IS READ AT THE MOMENT ITS FRAME IS SHOWN
/// (the-clock-is-read-when-the-tick-runs): a frame-clock moment carried onto
/// the device's clock by the two clocks' own difference, read side by side —
/// never by when a tick happened to run.
void main() {
  const tick = 6944;

  test('a moment is carried across by the clocks\' difference exactly', () {
    final clock = FrameTimeOnDevice();
    for (var frame = 0; frame < 20; frame += 1) {
      final now = 1000000 + frame * tick;
      expect(
        clock.onDevice(
          deviceNowMicros: now + 8000,
          frameNowMicros: now,
          frameMicros: now + 20000,
        ),
        now + 20000 + 8000,
      );
    }
  });

  test('🚨where the tick ran plays no part: a moment read late reads where '
      'it read on time', () {
    final clock = FrameTimeOnDevice();
    const moment = 2000000;
    final onTime = clock.onDevice(
      deviceNowMicros: 1990000 + 5000,
      frameNowMicros: 1990000,
      frameMicros: moment,
    );
    final late = clock.onDevice(
      deviceNowMicros: 1996400 + 5000,
      frameNowMicros: 1996400,
      frameMicros: moment,
    );
    expect(late, onTime);
  });

  test('🚨a pair read with something between its two reads cannot move the '
      'gap down: the largest a recent pair said holds', () {
    final clock = FrameTimeOnDevice();
    var now = 1000000;
    for (var frame = 0; frame < 32; frame += 1) {
      now += tick;
      clock.onDevice(
        deviceNowMicros: now + 8000,
        frameNowMicros: now,
        frameMicros: now,
      );
    }
    now += tick;
    // The frame clock was read 3ms after the device's: the pair says 3ms
    // less than the clocks differ.
    final read = clock.onDevice(
      deviceNowMicros: now + 8000,
      frameNowMicros: now + 3000,
      frameMicros: now,
    );
    expect(
      read - now,
      greaterThanOrEqualTo(8000 - (tick + 3000) ~/ 1000),
      reason: 'only the sink of the frame-clock time that passed',
    );
  });

  test('a pair that says more is taken at once', () {
    final clock = FrameTimeOnDevice();
    var now = 1000000;
    for (var frame = 0; frame < 32; frame += 1) {
      now += tick;
      clock.onDevice(
        deviceNowMicros: now + 8000,
        frameNowMicros: now,
        frameMicros: now,
      );
    }
    now += tick;
    expect(
      clock.onDevice(
        deviceNowMicros: now + 9000,
        frameNowMicros: now,
        frameMicros: now,
      ),
      now + 9000,
    );
  });

  test('the gap is followed: a device clock that falls behind the engine\'s '
      'is read where it has got to', () {
    final clock = FrameTimeOnDevice();
    var now = 1000000;
    var read = 0;
    for (var frame = 0; frame < 400; frame += 1) {
      now += tick;
      read = clock.onDevice(
        deviceNowMicros: now + 5000 - frame * 5,
        frameNowMicros: now,
        frameMicros: now,
      );
    }
    expect((read - (now + 5000 - 399 * 5)).abs(), lessThan(100));
  });
}

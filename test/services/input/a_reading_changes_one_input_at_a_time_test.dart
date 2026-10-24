import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/input/pen_readings.dart';

/// A stroke holds what the pen read as ONE value, and changes one input of
/// it at a time ([PenReadingsChange]). The other three come through as they
/// were — a twist left behind by a change of pressure is the pen's twist
/// lost (F-176-Q9, mutants P20–P23: the four used to be listed wherever
/// they were held, and a twist dropped from one list still compiled).
void main() {
  const read = (
    pressure: 0.25,
    lean: (azimuthDegrees: 30.0, altitude: 0.5),
    twist: 90.0,
    speed: 0.75,
  );

  test('a change of pressure keeps the lean, the twist and the speed', () {
    expect(read.withPressure(1.0), (
      pressure: 1.0,
      lean: read.lean,
      twist: 90.0,
      speed: 0.75,
    ));
  });

  test('a change of lean keeps the pressure, the twist and the speed', () {
    expect(read.withLean(null), (
      pressure: 0.25,
      lean: null,
      twist: 90.0,
      speed: 0.75,
    ));
  });

  test('a change of twist keeps the pressure, the lean and the speed', () {
    expect(read.withTwist(null), (
      pressure: 0.25,
      lean: read.lean,
      twist: null,
      speed: 0.75,
    ));
  });

  test('a change of speed keeps the pressure, the lean and the twist', () {
    expect(read.withSpeed(0.0), (
      pressure: 0.25,
      lean: read.lean,
      twist: 90.0,
      speed: 0.0,
    ));
  });
}

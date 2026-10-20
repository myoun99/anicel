// 「펜을 따라 바뀐다」 — 유저 2026-10-21, F-176-Q7: the brush cursor of a
// tilted pencil stayed round while the pencil laid a wedge.
//
// The outline is the tip a pen held like this lays down where it lands:
// what the pose turns and stretches, through the stroke's own dynamics —
// and nothing the stroke has not measured before it touches.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_input_source.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_shape.dart';
import 'package:anicel/src/models/brush_tip_rotation_mode.dart';
import 'package:anicel/src/services/brush_poised_tip.dart';
import 'package:anicel/src/services/input/pen_pose.dart';

void main() {
  const base = BrushShape(size: 40, roundness: 0.5, angleDegrees: 10);
  const PenPose leaning = (
    lean: (azimuthDegrees: 30.0, altitude: 0.25),
    twist: 90.0,
  );
  const PenPose unposed = (lean: null, twist: null);
  const asSet = (size: 40.0, roundness: 0.5, angleDegrees: 10.0);

  BrushShape turnedBy(BrushTipRotationMode mode) =>
      base.copyWith(rotationMode: mode);

  test('a pen that says nothing of its pose shows the brush as it is', () {
    for (final mode in BrushTipRotationMode.values) {
      expect(poisedTip(turnedBy(mode), unposed), asSet, reason: mode.name);
    }
  });

  test('the base the tip turns from turns the outline — the lean, or the '
      'barrel, against the angle (the dab\'s sign)', () {
    expect(
      poisedTip(turnedBy(BrushTipRotationMode.penTilt), leaning).angleDegrees,
      10.0 - 30.0,
    );
    expect(
      poisedTip(turnedBy(BrushTipRotationMode.penTwist), leaning).angleDegrees,
      10.0 - 90.0,
    );
    expect(
      poisedTip(turnedBy(BrushTipRotationMode.fixed), leaning).angleDegrees,
      10.0,
    );
  });

  test('⛔the stroke\'s direction is not known before it moves — a tip that '
      'follows it shows its own angle', () {
    expect(poisedTip(turnedBy(BrushTipRotationMode.direction), leaning), asSet);
  });

  test('傾き curves stretch the outline — size and roundness, through the '
      'stroke\'s own response', () {
    final shape = base
        .withCurve(
          BrushPressureTarget.size,
          BrushInputSource.tilt,
          BrushPressureCurve.linearFrom(0.0, maximum: 2.0),
        )
        .withCurve(
          BrushPressureTarget.roundness,
          BrushInputSource.tilt,
          BrushPressureCurve.linearFrom(0.0),
        );
    final tip = poisedTip(shape, leaning);
    // A quarter of the way up is three quarters of full lean.
    expect(tip.size, closeTo(40.0 * 0.75 * 2.0, 1e-9));
    expect(tip.roundness, closeTo(0.5 * 0.75, 1e-9));
  });

  test('⛔not pressure, speed or chance — none is measured before the pen '
      'touches', () {
    // Half at any input — the shape laid flat on a 50% floor — so a row
    // that WAS read shows, whatever it would have read.
    final half = BrushPressureCurve(const [
      BrushCurvePoint(0.0, 0.0),
      BrushCurvePoint(1.0, 0.0),
    ], minimum: 0.5);
    var shape = base;
    for (final source in [
      BrushInputSource.pressure,
      BrushInputSource.speed,
      BrushInputSource.random,
    ]) {
      shape = shape
          .withCurve(BrushPressureTarget.size, source, half)
          .withCurve(BrushPressureTarget.roundness, source, half);
    }
    expect(poisedTip(shape, leaning), asSet);
  });
}

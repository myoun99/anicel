import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_input_source.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_shape.dart';
import 'package:anicel/src/models/brush_tip_rotation_mode.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_pressure_dynamics.dart';
import 'package:anicel/src/services/brush_stroke_dynamics.dart';
import 'package:anicel/src/models/brush_edit_canvas_input_settings.dart';

BrushDab _dab({double x = 10, double y = 10, int sequence = 0}) {
  return BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: 0xFF000000,
    size: 10,
    opacity: 0.8,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: sequence,
    angleDegrees: 30,
  );
}

void main() {
  test('inactive settings pass dabs through unchanged', () {
    final dynamics = BrushStrokeDynamics(
      settings: BrushEditCanvasInputSettings(),
      random: math.Random(1),
    );
    final dabs = [_dab(), _dab(x: 12, sequence: 1)];
    expect(identical(dynamics.apply(dabs, firstSequence: 0), dabs), isTrue);
  });

  test('direction mode adds the stroke direction to the tip angle', () {
    final dynamics = BrushStrokeDynamics(
      settings: BrushEditCanvasInputSettings(
        rotationMode: BrushTipRotationMode.direction,
      ),
      random: math.Random(1),
    );
    final emitted = dynamics.apply(
      [_dab()],
      firstSequence: 5,
      directionDegrees: 45,
    );
    expect(emitted.single.angleDegrees, closeTo(75.0, 1e-9)); // 30 + 45
    expect(emitted.single.sequence, 5);

    // Unknown direction (stroke start) keeps the base angle.
    final unknown = dynamics.apply([_dab()], firstSequence: 0);
    expect(unknown.single.angleDegrees, closeTo(30.0, 1e-9));
  });

  test('scatter emits count dabs within the radius', () {
    final settings = BrushEditCanvasInputSettings(
      scatterRadiusRatio: 0.5, // radius = 5 canvas px for size-10 dabs
      scatterCount: 4,
    );
    final dynamics = BrushStrokeDynamics(
      settings: settings,
      random: math.Random(7),
    );
    final emitted = dynamics.apply(
      [_dab(), _dab(x: 20, sequence: 1)],
      firstSequence: 0,
      directionDegrees: 0,
    );

    expect(emitted, hasLength(8));
    expect(
      [for (final dab in emitted) dab.sequence],
      [for (var i = 0; i < 8; i += 1) i],
    );
    for (var i = 0; i < 4; i += 1) {
      final dx = emitted[i].center.x - 10;
      final dy = emitted[i].center.y - 10;
      expect(math.sqrt(dx * dx + dy * dy), lessThanOrEqualTo(5.0 + 1e-9));
    }
  });

  test('the angle\'s random turn stays within its half turn', () {
    final dynamics = BrushStrokeDynamics(
      settings: BrushEditCanvasInputSettings(angleJitter: 0.25),
      random: math.Random(3),
    );
    final emitted = dynamics.apply(
      [for (var i = 0; i < 32; i += 1) _dab(sequence: i)],
      firstSequence: 0,
      directionDegrees: 0,
    );
    for (final dab in emitted) {
      // angle 30 +- 45 degrees, normalized into [0, 360).
      final angle = dab.angleDegrees > 180
          ? dab.angleDegrees - 360
          : dab.angleDegrees;
      expect(angle, greaterThanOrEqualTo(-15.0 - 1e-9));
      expect(angle, lessThanOrEqualTo(75.0 + 1e-9));
    }
  });

  group('🚨the ランダム row (F-176-Q2)', () {
    BrushShape randomRows(double minimum) => BrushShape(
      curves: {
        for (final target in BrushPressureTarget.values)
          (target, BrushInputSource.random): BrushPressureCurve.linearFrom(
            minimum,
          ),
      },
    );

    test('throws every per-dab setting between its floor and its base', () {
      final random = math.Random(3);
      final dabs = [
        for (var i = 0; i < 32; i += 1)
          applyBrushInputDynamics(
            _dab(sequence: i),
            shape: randomRows(0.5),
            random: random,
          ),
      ];
      for (final dab in dabs) {
        expect(dab.size, inInclusiveRange(5.0 - 1e-9, 10.0));
        expect(dab.opacity, inInclusiveRange(0.4 - 1e-9, 0.8));
        expect(dab.flow, inInclusiveRange(0.5 - 1e-9, 1.0));
        expect(dab.hardness, inInclusiveRange(0.5 - 1e-9, 1.0));
        expect(dab.roundness, inInclusiveRange(0.5 - 1e-9, 1.0));
      }
      expect(
        dabs.map((dab) => dab.size).toSet().length,
        greaterThan(1),
        reason: 'thrown per dab',
      );
    });

    test('a 0% floor squashes the tip without degenerating it', () {
      final random = math.Random(7);
      final dabs = [
        for (var i = 0; i < 64; i += 1)
          applyBrushInputDynamics(
            _dab(sequence: i),
            shape: randomRows(0.0),
            random: random,
          ),
      ];
      // A ratio in (0, 1]: even at a 0% floor the tip keeps a hair of
      // width, because a zero-width ellipse has no coverage to rasterize.
      for (final dab in dabs) {
        expect(dab.roundness, inInclusiveRange(0.01, 1.0));
      }
    });

    test('without dice the row is skipped, not guessed at', () {
      // A still thumbnail has no stroke to own a throw: the brush draws at
      // its base, the way a mouse skips 傾き.
      final dab = applyBrushInputDynamics(_dab(), shape: randomRows(0.0));
      expect(dab.size, 10.0);
      expect(dab.opacity, 0.8);
      expect(dab.roundness, 1.0);
    });
  });

  group('🚨ペンの方向 — the tip turns with the pen (F-176-Q4)', () {
    final dynamics = BrushStrokeDynamics(
      settings: BrushEditCanvasInputSettings(
        rotationMode: BrushTipRotationMode.penTilt,
      ),
      random: math.Random(1),
    );
    BrushDab leaning({double? altitude, double azimuth = 0}) => _dab()
        .copyWith(tiltAltitude: altitude, tiltAzimuthDegrees: azimuth);

    test('a leaning pen adds its lean, clockwise turned counterclockwise', () {
      final [dab] = dynamics.apply(
        [leaning(altitude: 0.4, azimuth: 70)],
        firstSequence: 0,
      );
      // base 30, lean 70° clockwise from +x = −70° as a dab angle.
      expect(dab.angleDegrees, closeTo(320.0, 1e-9));
    });

    test('no tilt, or an upright pen, leaves the base angle', () {
      final [mouse] = dynamics.apply([_dab()], firstSequence: 0);
      // An azimuth it would add if it read one: upright, it says nothing.
      final [upright] = dynamics.apply(
        [leaning(altitude: 1.0, azimuth: 70)],
        firstSequence: 0,
      );
      expect(mouse.angleDegrees, 30.0);
      expect(upright.angleDegrees, 30.0);
    });

    test('it does not wait for the stroke\'s direction', () {
      expect(dynamics.readsDirection, isFalse);
    });
  });

  test('same seed reproduces the same emission', () {
    final settings = BrushEditCanvasInputSettings(
      scatterRadiusRatio: 1.0,
      scatterCount: 3,
      angleJitter: 0.3,
    );
    final first = BrushStrokeDynamics(
      settings: settings,
      random: math.Random(42),
    ).apply([_dab()], firstSequence: 0, directionDegrees: 10);
    final second = BrushStrokeDynamics(
      settings: settings,
      random: math.Random(42),
    ).apply([_dab()], firstSequence: 0, directionDegrees: 10);
    expect(first, second);
  });

  test('strokeDirectionDegrees measures visual CCW in y-down space', () {
    expect(
      strokeDirectionDegrees(
        from: CanvasPoint(x: 0, y: 0),
        to: CanvasPoint(x: 10, y: 0),
      ),
      closeTo(0.0, 1e-9),
    );
    // Moving visually up (y decreasing) is +90.
    expect(
      strokeDirectionDegrees(
        from: CanvasPoint(x: 0, y: 10),
        to: CanvasPoint(x: 0, y: 0),
      ),
      closeTo(90.0, 1e-9),
    );
    expect(
      strokeDirectionDegrees(
        from: CanvasPoint(x: 5, y: 5),
        to: CanvasPoint(x: 5, y: 5),
      ),
      isNull,
    );
  });

  test('pressure minimum-size floor keeps light strokes visible', () {
    // BB-3: the floor IS the size curve's left endpoint.
    final shape = const BrushShape().withPressureCurve(
      BrushPressureTarget.size,
      BrushPressureCurve.linearFrom(0.65),
    );
    final light = _dab().copyWith(pressure: 0.0);
    final scaled = applyBrushInputDynamics(light, shape: shape);
    expect(scaled.size, closeTo(6.5, 1e-9));

    final full = applyBrushInputDynamics(
      _dab().copyWith(pressure: 1.0),
      shape: shape,
    );
    expect(full.size, closeTo(10.0, 1e-9));
  });
}

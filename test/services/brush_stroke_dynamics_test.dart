import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_tip_rotation_mode.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_pressure_dynamics.dart';
import 'package:anicel/src/services/brush_stroke_dynamics.dart';
import 'package:anicel/src/ui/canvas/brush_edit_canvas_input_settings.dart';

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

  test('jitters only reduce size and opacity, within bounds', () {
    final settings = BrushEditCanvasInputSettings(
      sizeJitter: 0.5,
      opacityJitter: 0.5,
      angleJitter: 0.25,
    );
    final dynamics = BrushStrokeDynamics(
      settings: settings,
      random: math.Random(3),
    );
    final emitted = dynamics.apply(
      [for (var i = 0; i < 32; i += 1) _dab(sequence: i)],
      firstSequence: 0,
      directionDegrees: 0,
    );
    for (final dab in emitted) {
      expect(dab.size, lessThanOrEqualTo(10.0));
      expect(dab.size, greaterThanOrEqualTo(5.0 - 1e-9));
      expect(dab.opacity, lessThanOrEqualTo(0.8));
      expect(dab.opacity, greaterThanOrEqualTo(0.4 - 1e-9));
      // angle 30 +- 45 degrees, normalized into [0, 360).
      final angle = dab.angleDegrees > 180
          ? dab.angleDegrees - 360
          : dab.angleDegrees;
      expect(angle, greaterThanOrEqualTo(-15.0 - 1e-9));
      expect(angle, lessThanOrEqualTo(75.0 + 1e-9));
    }
  });

  test('roundness jitter squashes the tip without degenerating it', () {
    final dynamics = BrushStrokeDynamics(
      settings: BrushEditCanvasInputSettings(roundnessJitter: 1.0),
      random: math.Random(7),
    );

    final emitted = dynamics.apply(
      [for (var i = 0; i < 32; i += 1) _dab(sequence: i)],
      firstSequence: 0,
      directionDegrees: 0,
    );

    // A ratio in (0, 1]: even at full jitter the tip keeps a hair of width,
    // because a zero-width ellipse has no coverage to rasterize.
    for (final dab in emitted) {
      expect(dab.roundness, greaterThanOrEqualTo(0.01));
      expect(dab.roundness, lessThanOrEqualTo(1.0));
    }
    expect(
      emitted.map((dab) => dab.roundness).toSet().length,
      greaterThan(1),
      reason: 'the squash is rolled per dab',
    );
  });

  test('same seed reproduces the same emission', () {
    final settings = BrushEditCanvasInputSettings(
      scatterRadiusRatio: 1.0,
      scatterCount: 3,
      sizeJitter: 0.4,
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
    final floor = BrushPressureCurve.linearFrom(0.65);
    final light = _dab().copyWith(pressure: 0.0);
    final scaled = applyBrushPressureDynamics(light, sizeCurve: floor);
    expect(scaled.size, closeTo(6.5, 1e-9));

    final full = applyBrushPressureDynamics(
      _dab().copyWith(pressure: 1.0),
      sizeCurve: floor,
    );
    expect(full.size, closeTo(10.0, 1e-9));
  });
}

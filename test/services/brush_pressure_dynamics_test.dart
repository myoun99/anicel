import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_pressure_dynamics.dart';

BrushDab _dab({
  double size = 10,
  double opacity = 0.8,
  double flow = 1,
  double hardness = 1,
  double pressure = 0.5,
}) {
  return BrushDab(
    center: CanvasPoint(x: 1, y: 1),
    color: 0xFF000000,
    size: size,
    opacity: opacity,
    flow: flow,
    hardness: hardness,
    tipShape: BrushTipShape.round,
    pressure: pressure,
    sequence: 0,
  );
}

void main() {
  group('applyBrushPressureDynamics (BB-3 curves)', () {
    test('returns the same instance when no curve is set', () {
      final dab = _dab();
      final result = applyBrushPressureDynamics(dab);
      expect(identical(result, dab), isTrue);
    });

    test('scales size only through the size curve', () {
      final result = applyBrushPressureDynamics(
        _dab(size: 10, opacity: 0.8, pressure: 0.5),
        sizeCurve: BrushPressureCurve.identity(),
      );
      expect(result.size, 5.0);
      expect(result.opacity, 0.8);
    });

    test('scales opacity only through the opacity curve', () {
      final result = applyBrushPressureDynamics(
        _dab(size: 10, opacity: 0.8, pressure: 0.5),
        opacityCurve: BrushPressureCurve.identity(),
      );
      expect(result.size, 10.0);
      expect(result.opacity, closeTo(0.4, 1e-9));
    });

    test('scales flow and hardness through their curves (new in BB-3)', () {
      final result = applyBrushPressureDynamics(
        _dab(flow: 0.8, hardness: 0.6, pressure: 0.5),
        flowCurve: BrushPressureCurve.identity(),
        hardnessCurve: BrushPressureCurve.identity(),
      );
      expect(result.flow, closeTo(0.4, 1e-9));
      expect(result.hardness, closeTo(0.3, 1e-9));
      expect(result.size, 10.0);
      expect(result.opacity, 0.8);
    });

    test('scales every channel when all curves are set', () {
      final result = applyBrushPressureDynamics(
        _dab(size: 20, opacity: 0.6, pressure: 0.25),
        sizeCurve: BrushPressureCurve.identity(),
        opacityCurve: BrushPressureCurve.identity(),
        flowCurve: BrushPressureCurve.identity(),
        hardnessCurve: BrushPressureCurve.identity(),
      );
      expect(result.size, 5.0);
      expect(result.opacity, closeTo(0.15, 1e-9));
      expect(result.flow, 0.25);
      expect(result.hardness, 0.25);
    });

    test('full pressure is a no-op on values', () {
      final result = applyBrushPressureDynamics(
        _dab(size: 12, opacity: 1.0, pressure: 1.0),
        sizeCurve: BrushPressureCurve.identity(),
        opacityCurve: BrushPressureCurve.identity(),
      );
      expect(result.size, 12.0);
      expect(result.opacity, 1.0);
    });

    test('the legacy minimum floor is the curve left endpoint', () {
      // Old formula: size * (min + (1 - min) * pressure) with min = 0.4.
      final result = applyBrushPressureDynamics(
        _dab(size: 10, pressure: 0.5),
        sizeCurve: BrushPressureCurve.linearFrom(0.4),
      );
      expect(result.size, closeTo(10 * (0.4 + 0.6 * 0.5), 1e-9));
    });

    test('preserves the pressure field so downstream interpolation works', () {
      final result = applyBrushPressureDynamics(
        _dab(pressure: 0.3),
        sizeCurve: BrushPressureCurve.identity(),
        opacityCurve: BrushPressureCurve.identity(),
      );
      expect(result.pressure, 0.3);
    });
  });
}

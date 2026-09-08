import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_input_source.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_shape.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_pressure_dynamics.dart';

BrushDab _dab({
  double size = 10,
  double opacity = 0.8,
  double flow = 1,
  double hardness = 1,
  double pressure = 0.5,
  double tiltAltitude = 1.0,
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
    tiltAltitude: tiltAltitude,
    sequence: 0,
  );
}

/// A shape carrying one curve for one (setting, source) pairing.
BrushShape _driving(
  BrushPressureTarget target,
  BrushInputSource source,
  BrushPressureCurve curve,
) => const BrushShape().withCurve(target, source, curve);

void main() {
  group('applyBrushInputDynamics — one source', () {
    test('returns the same instance when the brush carries no curve', () {
      final dab = _dab();
      final result = applyBrushInputDynamics(dab, shape: const BrushShape());
      expect(identical(result, dab), isTrue);
    });

    test('scales size only through the size curve', () {
      final result = applyBrushInputDynamics(
        _dab(size: 10, opacity: 0.8, pressure: 0.5),
        shape: _driving(
          BrushPressureTarget.size,
          BrushInputSource.pressure,
          BrushPressureCurve.identity(),
        ),
      );
      expect(result.size, 5.0);
      expect(result.opacity, 0.8);
    });

    test('scales opacity only through the opacity curve', () {
      final result = applyBrushInputDynamics(
        _dab(size: 10, opacity: 0.8, pressure: 0.5),
        shape: _driving(
          BrushPressureTarget.opacity,
          BrushInputSource.pressure,
          BrushPressureCurve.identity(),
        ),
      );
      expect(result.size, 10.0);
      expect(result.opacity, closeTo(0.4, 1e-9));
    });

    test('scales every channel when all four are driven', () {
      var shape = const BrushShape();
      for (final target in BrushPressureTarget.values) {
        shape = shape.withCurve(
          target,
          BrushInputSource.pressure,
          BrushPressureCurve.identity(),
        );
      }
      final result = applyBrushInputDynamics(
        _dab(size: 20, opacity: 0.6, flow: 1, hardness: 1, pressure: 0.25),
        shape: shape,
      );
      expect(result.size, 5.0);
      expect(result.opacity, closeTo(0.15, 1e-9));
      expect(result.flow, 0.25);
      expect(result.hardness, 0.25);
    });

    test('full pressure is a no-op on values', () {
      final result = applyBrushInputDynamics(
        _dab(size: 12, opacity: 1.0, pressure: 1.0),
        shape: _driving(
          BrushPressureTarget.size,
          BrushInputSource.pressure,
          BrushPressureCurve.identity(),
        ),
      );
      expect(result.size, 12.0);
    });

    test('the legacy minimum floor is the curve left endpoint', () {
      // Old formula: size * (min + (1 - min) * pressure) with min = 0.4.
      final result = applyBrushInputDynamics(
        _dab(size: 10, pressure: 0.5),
        shape: _driving(
          BrushPressureTarget.size,
          BrushInputSource.pressure,
          BrushPressureCurve.linearFrom(0.4),
        ),
      );
      expect(result.size, closeTo(10 * (0.4 + 0.6 * 0.5), 1e-9));
    });

    test('preserves the input fields so downstream interpolation works', () {
      final result = applyBrushInputDynamics(
        _dab(pressure: 0.3, tiltAltitude: 0.6),
        shape: _driving(
          BrushPressureTarget.size,
          BrushInputSource.pressure,
          BrushPressureCurve.identity(),
        ),
      );
      expect(result.pressure, 0.3);
      expect(result.tiltAltitude, 0.6);
    });
  });

  group('applyBrushInputDynamics — several sources', () {
    test('🚨THEY MULTIPLY (유저 확정 2026-09-09)', () {
      // Pressure 0.5 and tilt 0.5 on SIZE, both straight lines: 10 × 0.5 ×
      // 0.5 = 2.5. ⛔Not 5.0 (either source winning), not 0.5+0.5 (addition).
      // The rule and the survey behind it are on `BrushInputSource`.
      final shape = _driving(
        BrushPressureTarget.size,
        BrushInputSource.pressure,
        BrushPressureCurve.identity(),
      ).withCurve(
        BrushPressureTarget.size,
        BrushInputSource.tilt,
        BrushPressureCurve.identity(),
      );
      final result = applyBrushInputDynamics(
        _dab(size: 10, pressure: 0.5, tiltAltitude: 0.5),
        shape: shape,
      );
      expect(result.size, closeTo(2.5, 1e-9));
    });

    test('a source at full contributes exactly 1.0, so adding one is '
        'non-destructive', () {
      // This is WHY multiply was chosen: enabling tilt on an upright pen
      // must not move the stroke at all.
      final pressureOnly = _driving(
        BrushPressureTarget.size,
        BrushInputSource.pressure,
        BrushPressureCurve.identity(),
      );
      final withTilt = pressureOnly.withCurve(
        BrushPressureTarget.size,
        BrushInputSource.tilt,
        BrushPressureCurve.identity(),
      );
      final dab = _dab(size: 10, pressure: 0.5, tiltAltitude: 1.0);
      expect(
        applyBrushInputDynamics(dab, shape: withTilt).size,
        applyBrushInputDynamics(dab, shape: pressureOnly).size,
      );
    });

    test('tilt alone drives a setting — pressure need not be involved', () {
      final result = applyBrushInputDynamics(
        _dab(size: 10, pressure: 1.0, tiltAltitude: 0.25),
        shape: _driving(
          BrushPressureTarget.size,
          BrushInputSource.tilt,
          BrushPressureCurve.identity(),
        ),
      );
      expect(result.size, closeTo(2.5, 1e-9));
    });

    test('⛔a SPEED curve is stored but contributes nothing yet', () {
      // `BrushInputSample` carries no timestamp, so the engine cannot
      // measure px/s. The curve must be inert rather than guessed at — and
      // it must not be silently dropped either, which is why it survives on
      // the shape. When speed starts being fed, this pin is what changes.
      final shape = _driving(
        BrushPressureTarget.size,
        BrushInputSource.speed,
        BrushPressureCurve.linearFrom(0.0),
      );
      expect(shape.curveFor(BrushPressureTarget.size, BrushInputSource.speed),
          isNotNull);
      expect(applyBrushInputDynamics(_dab(size: 10), shape: shape).size, 10.0);
    });

    test('🚨SIZE may exceed its base, the other three may not', () {
      // A tilt curve carries Clip Studio's 最大値 — a flat pen paints a wider
      // wedge than the nominal size. Opacity cannot go past 1.0, because
      // there is no such thing as 300% opacity.
      final tripled = BrushPressureCurve.identity(maximum: 3.0);
      final dab = _dab(size: 10, opacity: 0.5, pressure: 1.0);
      expect(
        applyBrushInputDynamics(
          dab,
          shape: _driving(
            BrushPressureTarget.size,
            BrushInputSource.pressure,
            tripled,
          ),
        ).size,
        closeTo(30.0, 1e-9),
      );
      expect(
        applyBrushInputDynamics(
          dab,
          shape: _driving(
            BrushPressureTarget.opacity,
            BrushInputSource.pressure,
            tripled,
          ),
        ).opacity,
        1.0,
      );
    });
  });
}

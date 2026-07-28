import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';

void main() {
  group('BrushPressureCurve', () {
    test('identity is the exact 1:1 line', () {
      final curve = BrushPressureCurve.identity();
      expect(curve.isIdentity, isTrue);
      expect(curve.evaluate(0.0), 0.0);
      expect(curve.evaluate(0.25), 0.25);
      expect(curve.evaluate(0.5), 0.5);
      expect(curve.evaluate(1.0), 1.0);
      expect(curve.evaluate(0.37), closeTo(0.37, 1e-12));
    });

    test('linearFrom reproduces the legacy minimum-size formula', () {
      final curve = BrushPressureCurve.linearFrom(0.4);
      for (final pressure in [0.0, 0.1, 0.5, 0.9, 1.0]) {
        expect(
          curve.evaluate(pressure),
          closeTo(0.4 + (1 - 0.4) * pressure, 1e-12),
        );
      }
    });

    test('passes through every control point exactly', () {
      final curve = BrushPressureCurve(const [
        BrushCurvePoint(0.0, 0.2),
        BrushCurvePoint(0.3, 0.8),
        BrushCurvePoint(0.7, 0.5),
        BrushCurvePoint(1.0, 1.0),
      ]);
      expect(curve.evaluate(0.0), closeTo(0.2, 1e-12));
      expect(curve.evaluate(0.3), closeTo(0.8, 1e-12));
      expect(curve.evaluate(0.7), closeTo(0.5, 1e-12));
      expect(curve.evaluate(1.0), closeTo(1.0, 1e-12));
    });

    test('never overshoots the unit range (monotone Hermite)', () {
      // A plain Catmull-Rom would overshoot above 1 between the middle
      // points; the Fritsch-Carlson limiter must not.
      final curve = BrushPressureCurve(const [
        BrushCurvePoint(0.0, 0.0),
        BrushCurvePoint(0.4, 1.0),
        BrushCurvePoint(0.6, 1.0),
        BrushCurvePoint(1.0, 0.1),
      ]);
      for (var i = 0; i <= 1000; i += 1) {
        final value = curve.evaluate(i / 1000);
        expect(value, greaterThanOrEqualTo(0.0));
        expect(value, lessThanOrEqualTo(1.0));
      }
    });

    test('is monotone between monotone control points', () {
      final curve = BrushPressureCurve(const [
        BrushCurvePoint(0.0, 0.0),
        BrushCurvePoint(0.2, 0.1),
        BrushCurvePoint(0.5, 0.85),
        BrushCurvePoint(1.0, 1.0),
      ]);
      var previous = -1.0;
      for (var i = 0; i <= 200; i += 1) {
        final value = curve.evaluate(i / 200);
        expect(value, greaterThanOrEqualTo(previous - 1e-12));
        previous = value;
      }
    });

    test('clamps out-of-range and non-finite input pressure', () {
      final curve = BrushPressureCurve.linearFrom(0.5);
      expect(curve.evaluate(-1.0), curve.evaluate(0.0));
      expect(curve.evaluate(2.0), curve.evaluate(1.0));
      expect(curve.evaluate(double.nan), curve.evaluate(1.0));
    });

    test('validates its control points', () {
      expect(
        () => BrushPressureCurve(const [BrushCurvePoint(0, 0)]),
        throwsArgumentError,
      );
      expect(
        () => BrushPressureCurve(const [
          BrushCurvePoint(0.1, 0),
          BrushCurvePoint(1, 1),
        ]),
        throwsArgumentError,
      );
      expect(
        () => BrushPressureCurve(const [
          BrushCurvePoint(0, 0),
          BrushCurvePoint(0.9, 1),
        ]),
        throwsArgumentError,
      );
      expect(
        () => BrushPressureCurve(const [
          BrushCurvePoint(0, 0),
          BrushCurvePoint(0.5, 0.5),
          BrushCurvePoint(0.5, 0.8),
          BrushCurvePoint(1, 1),
        ]),
        throwsArgumentError,
      );
      expect(
        () => BrushPressureCurve(const [
          BrushCurvePoint(0, -0.1),
          BrushCurvePoint(1, 1),
        ]),
        throwsArgumentError,
      );
    });

    test('JSON round-trips', () {
      final curve = BrushPressureCurve(const [
        BrushCurvePoint(0.0, 0.25),
        BrushCurvePoint(0.4, 0.5),
        BrushCurvePoint(1.0, 0.9),
      ]);
      expect(curve.toJson(), [0.0, 0.25, 0.4, 0.5, 1.0, 0.9]);
      expect(BrushPressureCurve.fromJson(curve.toJson()), curve);
    });

    test('equality and hashCode follow the points', () {
      expect(BrushPressureCurve.identity(), BrushPressureCurve.identity());
      expect(
        BrushPressureCurve.identity().hashCode,
        BrushPressureCurve.identity().hashCode,
      );
      expect(
        BrushPressureCurve.identity() == BrushPressureCurve.linearFrom(0.1),
        isFalse,
      );
    });
  });
}

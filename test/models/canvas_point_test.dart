import 'package:flutter_test/flutter_test.dart';
import '../helpers/json_round_trip.dart';
import 'package:anicel/src/models/canvas_point.dart';

void main() {
  group('CanvasPoint', () {


    test('copyWith updates x', () {
      final point = CanvasPoint(x: 1, y: 2);

      expect(point.copyWith(x: 3).x, 3);
      expect(point.x, 1);
    });

    test('copyWith updates y', () {
      final point = CanvasPoint(x: 1, y: 2);

      expect(point.copyWith(y: 4).y, 4);
      expect(point.y, 2);
    });

    test('equality includes x and y', () {
      final point = CanvasPoint(x: 1, y: 2);

      expect(point, CanvasPoint(x: 1, y: 2));
      expect(point.copyWith(x: 9), isNot(point));
      expect(point.copyWith(y: 9), isNot(point));
    });

    test('toJson/fromJson round-trips', () {
      final point = CanvasPoint(x: 1.25, y: 2.5);

      expectJsonRoundTrip(point, CanvasPoint.fromJson);
    });

    test('NaN x throws', () {
      expect(() => CanvasPoint(x: double.nan, y: 2), throwsArgumentError);
    });

    test('NaN y throws', () {
      expect(() => CanvasPoint(x: 1, y: double.nan), throwsArgumentError);
    });

    test('infinite x throws', () {
      expect(() => CanvasPoint(x: double.infinity, y: 2), throwsArgumentError);
    });

    test('infinite y throws', () {
      expect(() => CanvasPoint(x: 1, y: double.infinity), throwsArgumentError);
    });

    // The two vector operations every point type owns (Offset.distance /
    // Offset.lerp): the stabilizer's rope, the stamp drag, the dab
    // interpolator and the transform track each spelled them out (the
    // audit's clone scan, 2026-09-06).
    test('distanceTo is the Euclidean length, both ways round', () {
      final a = CanvasPoint(x: 1, y: 2);
      final b = CanvasPoint(x: 4, y: 6);
      expect(a.distanceTo(b), 5);
      expect(b.distanceTo(a), 5);
      expect(a.distanceTo(a), 0);
    });

    test('lerp walks the segment: 0 is a, 1 is b, the middle is halfway', () {
      final a = CanvasPoint(x: 10, y: -4);
      final b = CanvasPoint(x: 30, y: 6);
      expect(CanvasPoint.lerp(a, b, 0), a);
      expect(CanvasPoint.lerp(a, b, 1), b);
      expect(CanvasPoint.lerp(a, b, 0.5), CanvasPoint(x: 20, y: 1));
      expect(CanvasPoint.lerp(a, b, 0.25), CanvasPoint(x: 15, y: -1.5));
    });

    test('lerp spells a + (b - a) * t, so it lands on b exactly at 1', () {
      // The form matters bit for bit: `a * (1 - t) + b * t` rounds
      // differently and every caller's parity pin was written on this one.
      final a = CanvasPoint(x: 0.1, y: 0.7);
      final b = CanvasPoint(x: 0.3, y: 0.9);
      expect(CanvasPoint.lerp(a, b, 0.3).x, 0.1 + (0.3 - 0.1) * 0.3);
      expect(CanvasPoint.lerp(a, b, 0.3).y, 0.7 + (0.9 - 0.7) * 0.3);
    });
  });
}

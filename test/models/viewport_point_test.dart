import 'package:flutter_test/flutter_test.dart';
import '../helpers/json_round_trip.dart';
import 'package:anicel/src/models/viewport_point.dart';

void main() {
  group('ViewportPoint', () {


    test('copyWith updates x', () {
      final point = ViewportPoint(x: 1, y: 2);

      expect(point.copyWith(x: 3).x, 3);
      expect(point.x, 1);
    });

    test('copyWith updates y', () {
      final point = ViewportPoint(x: 1, y: 2);

      expect(point.copyWith(y: 4).y, 4);
      expect(point.y, 2);
    });

    test('equality includes x and y', () {
      final point = ViewportPoint(x: 1, y: 2);

      expect(point, ViewportPoint(x: 1, y: 2));
      expect(point.copyWith(x: 9), isNot(point));
      expect(point.copyWith(y: 9), isNot(point));
    });

    test('toJson/fromJson round-trips', () {
      final point = ViewportPoint(x: 1.25, y: 2.5);

      expectJsonRoundTrip(point, ViewportPoint.fromJson);
    });

    test('NaN x throws', () {
      expect(() => ViewportPoint(x: double.nan, y: 2), throwsArgumentError);
    });

    test('NaN y throws', () {
      expect(() => ViewportPoint(x: 1, y: double.nan), throwsArgumentError);
    });

    test('infinite x throws', () {
      expect(
        () => ViewportPoint(x: double.infinity, y: 2),
        throwsArgumentError,
      );
    });

    test('infinite y throws', () {
      expect(
        () => ViewportPoint(x: 1, y: double.infinity),
        throwsArgumentError,
      );
    });
  });
}

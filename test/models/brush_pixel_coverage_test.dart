import 'package:flutter_test/flutter_test.dart';
import '../helpers/json_round_trip.dart';
import 'package:anicel/src/models/brush_pixel_coverage.dart';

void main() {
  group('BrushPixelCoverage', () {
    BrushPixelCoverage coverage({int x = 1, int y = 2, double coverage = 0.5}) {
      return BrushPixelCoverage(x: x, y: y, coverage: coverage);
    }



    test('allows coverage 0', () {
      expect(coverage(coverage: 0).coverage, 0);
    });

    test('allows coverage 1', () {
      expect(coverage(coverage: 1).coverage, 1);
    });

    test('accepts negative x/y (pasteboard space)', () {
      expect(coverage(x: -1).x, -1);
      expect(coverage(y: -1).y, -1);
    });

    test('rejects negative coverage', () {
      expect(() => coverage(coverage: -0.1), throwsArgumentError);
    });

    test('rejects coverage above 1', () {
      expect(() => coverage(coverage: 1.1), throwsArgumentError);
    });

    test('rejects non-finite coverage', () {
      expect(() => coverage(coverage: double.nan), throwsArgumentError);
      expect(() => coverage(coverage: double.infinity), throwsArgumentError);
    });

    test('copyWith updates x', () {
      expect(coverage().copyWith(x: 3).x, 3);
    });

    test('copyWith updates y', () {
      expect(coverage().copyWith(y: 4).y, 4);
    });

    test('copyWith updates coverage', () {
      expect(coverage().copyWith(coverage: 0.75).coverage, 0.75);
    });

    test('equality includes all fields', () {
      final base = coverage();
      expect(base, coverage());
      expect(base.copyWith(x: 9), isNot(base));
      expect(base.copyWith(y: 9), isNot(base));
      expect(base.copyWith(coverage: 0.25), isNot(base));
    });

    test('hashCode is value-based', () {
      expect(coverage().hashCode, coverage().hashCode);
    });

    test('toJson/fromJson round-trips', () {
      final value = coverage(x: 3, y: 4, coverage: 0.25);
      expectJsonRoundTrip(value, BrushPixelCoverage.fromJson);
    });


  });
}

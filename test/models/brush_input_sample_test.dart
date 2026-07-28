import 'package:flutter_test/flutter_test.dart';
import '../helpers/json_round_trip.dart';
import 'package:anicel/src/models/brush_input_sample.dart';

void main() {
  group('BrushInputSample', () {
    test('default pressure and sequence are stable', () {
      final sample = BrushInputSample(x: 1, y: 2);

      expect(sample.x, 1);
      expect(sample.y, 2);
      expect(sample.pressure, 1.0);
      expect(sample.sequence, 0);
    });

    test('copyWith updates x', () {
      final sample = BrushInputSample(x: 1, y: 2);

      expect(sample.copyWith(x: 3).x, 3);
      expect(sample.x, 1);
    });

    test('copyWith updates y', () {
      final sample = BrushInputSample(x: 1, y: 2);

      expect(sample.copyWith(y: 4).y, 4);
      expect(sample.y, 2);
    });

    test('copyWith updates pressure', () {
      final sample = BrushInputSample(x: 1, y: 2);

      expect(sample.copyWith(pressure: 0.5).pressure, 0.5);
      expect(sample.pressure, 1.0);
    });

    test('copyWith updates sequence', () {
      final sample = BrushInputSample(x: 1, y: 2);

      expect(sample.copyWith(sequence: 7).sequence, 7);
      expect(sample.sequence, 0);
    });

    test('equality includes x, y, pressure, and sequence', () {
      final sample = BrushInputSample(x: 1, y: 2, pressure: 0.5, sequence: 3);

      expect(sample, BrushInputSample(x: 1, y: 2, pressure: 0.5, sequence: 3));
      expect(sample.copyWith(x: 9), isNot(sample));
      expect(sample.copyWith(y: 9), isNot(sample));
      expect(sample.copyWith(pressure: 0.75), isNot(sample));
      expect(sample.copyWith(sequence: 4), isNot(sample));
    });

    test('toJson/fromJson round-trips', () {
      final sample = BrushInputSample(
        x: 1.25,
        y: 2.5,
        pressure: 0.75,
        sequence: 4,
      );

      expectJsonRoundTrip(sample, BrushInputSample.fromJson);
    });

    test('invalid pressure below 0 throws', () {
      expect(
        () => BrushInputSample(x: 1, y: 2, pressure: -0.1),
        throwsArgumentError,
      );
    });

    test('invalid pressure above 1 throws', () {
      expect(
        () => BrushInputSample(x: 1, y: 2, pressure: 1.1),
        throwsArgumentError,
      );
    });

    test('NaN x throws', () {
      expect(() => BrushInputSample(x: double.nan, y: 2), throwsArgumentError);
    });

    test('NaN y throws', () {
      expect(() => BrushInputSample(x: 1, y: double.nan), throwsArgumentError);
    });

    test('infinite x throws', () {
      expect(
        () => BrushInputSample(x: double.infinity, y: 2),
        throwsArgumentError,
      );
    });

    test('infinite y throws', () {
      expect(
        () => BrushInputSample(x: 1, y: double.infinity),
        throwsArgumentError,
      );
    });

    test('negative sequence throws', () {
      expect(
        () => BrushInputSample(x: 1, y: 2, sequence: -1),
        throwsArgumentError,
      );
    });
  });
}

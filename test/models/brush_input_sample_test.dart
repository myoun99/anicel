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

    test('a pen with no tilt to report rests upright', () {
      final sample = BrushInputSample(x: 1, y: 2);

      expect(sample.tiltAltitude, 1.0);
      expect(sample.tiltAzimuthDegrees, 0.0);
    });

    test('tilt round-trips through json', () {
      final sample = BrushInputSample(
        x: 1,
        y: 2,
        tiltAzimuthDegrees: 217.5,
        tiltAltitude: 0.4,
      );

      final restored = BrushInputSample.fromJson(sample.toJson());
      expect(restored.tiltAzimuthDegrees, 217.5);
      expect(restored.tiltAltitude, 0.4);
      expect(restored, sample);
    });

    test('an upright sample writes no tilt keys at all', () {
      // The point is byte-identity with strokes recorded before tilt
      // existed — not merely that they read back the same.
      expect(BrushInputSample(x: 1, y: 2).toJson().keys, [
        'x',
        'y',
        'pressure',
        'sequence',
      ]);
    });

    test('altitude outside 0..1 throws', () {
      expect(
        () => BrushInputSample(x: 1, y: 2, tiltAltitude: 1.2),
        throwsArgumentError,
      );
      expect(
        () => BrushInputSample(x: 1, y: 2, tiltAltitude: -0.1),
        throwsArgumentError,
      );
    });

    test('tilt takes part in equality', () {
      final upright = BrushInputSample(x: 1, y: 2);

      expect(upright == upright.copyWith(tiltAltitude: 0.5), isFalse);
      expect(upright == upright.copyWith(tiltAzimuthDegrees: 90), isFalse);
    });

    test('a pen that has not moved yet reads no speed', () {
      expect(BrushInputSample(x: 1, y: 2).speed, 0.0);
    });

    test('speed round-trips through json and takes part in equality', () {
      final moving = BrushInputSample(x: 1, y: 2, speed: 0.75);

      expect(BrushInputSample.fromJson(moving.toJson()).speed, 0.75);
      expect(BrushInputSample.fromJson(moving.toJson()), moving);
      expect(moving == moving.copyWith(speed: 0.25), isFalse);
    });

    test('a standing pen writes no speed key at all', () {
      // Same contract as the tilt keys above: byte-identity with strokes
      // recorded before speed existed, not merely equal values back.
      expect(
        BrushInputSample(x: 1, y: 2).toJson().containsKey('speed'),
        isFalse,
      );
    });

    test('speed outside 0..1 throws — the door normalizes, so px/s is a bug', () {
      expect(
        () => BrushInputSample(x: 1, y: 2, speed: 1200),
        throwsArgumentError,
      );
      expect(
        () => BrushInputSample(x: 1, y: 2, speed: -0.1),
        throwsArgumentError,
      );
    });

    test('a NaN pressure throws instead of sailing through the range check', () {
      // Pressure had its own validator that never asked `isFinite`, and NaN
      // loses every comparison — so `value < 0.0 || value > 1.0` was false
      // and NaN was accepted. Folding it into the shared 0..1 check closed it.
      expect(
        () => BrushInputSample(x: 1, y: 2, pressure: double.nan),
        throwsArgumentError,
      );
    });
  });
}

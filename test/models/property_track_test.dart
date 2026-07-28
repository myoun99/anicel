import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/property_track.dart';

double _lerp(double a, double b, double t) => a + (b - a) * t;

double _resolve(PropertyTrack<double> track, int frame) =>
    track.resolveAt(frameIndex: frame, orElse: () => -1, lerp: _lerp);

void main() {
  group('PropertyTrack', () {
    test('empty track resolves to orElse', () {
      expect(_resolve(PropertyTrack<double>(), 5), -1);
    });

    test('holds first before and last after the keyed range', () {
      final track = PropertyTrack<double>().withKey(10, 100).withKey(20, 200);

      expect(_resolve(track, 0), 100);
      expect(_resolve(track, 30), 200);
    });

    test('exact keys win and linear segments interpolate', () {
      final track = PropertyTrack<double>().withKey(10, 100).withKey(20, 200);

      expect(_resolve(track, 10), 100);
      expect(_resolve(track, 15), 150);
      expect(_resolve(track, 20), 200);
    });

    test('a HOLD key freezes its segment (AE hold keyframe)', () {
      final track = PropertyTrack<double>()
          .withKey(10, 100, interpolation: PropertyKeyInterpolation.hold)
          .withKey(20, 200);

      expect(_resolve(track, 15), 100);
      expect(_resolve(track, 19), 100);
      expect(_resolve(track, 20), 200);
    });

    test('hold only affects the outgoing segment of its own key', () {
      final track = PropertyTrack<double>()
          .withKey(0, 0)
          .withKey(10, 100, interpolation: PropertyKeyInterpolation.hold)
          .withKey(20, 200);

      // Before the hold key: linear as usual.
      expect(_resolve(track, 5), 50);
      // After it: frozen.
      expect(_resolve(track, 15), 100);
    });

    test('withoutKey removes a key', () {
      final track = PropertyTrack<double>().withKey(10, 100).withoutKey(10);
      expect(track.isEmpty, isTrue);
    });

    test('negative key indexes are rejected', () {
      expect(
        () => PropertyTrack<double>(keys: {-1: const PropertyKey(1)}),
        throwsArgumentError,
      );
    });

    test('json round-trips values and interpolation', () {
      final track = PropertyTrack<double>()
          .withKey(3, 1.5)
          .withKey(9, 4, interpolation: PropertyKeyInterpolation.hold);

      final restored = PropertyTrack.fromJson<double>(
        track.toJson((value) => value),
        (value) => (value as num).toDouble(),
      );

      expect(restored, track);
      expect(restored.keyAt(9)!.interpolation, PropertyKeyInterpolation.hold);
    });

    test('json rejects duplicate key indexes', () {
      expect(
        () => PropertyTrack.fromJson<double>([
          {'index': 2, 'value': 1},
          {'index': 2, 'value': 2},
        ], (value) => (value as num).toDouble()),
        throwsFormatException,
      );
    });
  });
}

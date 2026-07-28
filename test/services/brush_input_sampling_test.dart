import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_input_sample.dart';
import 'package:anicel/src/models/stroke_point.dart';
import 'package:anicel/src/services/brush_input_sampling.dart';

void main() {
  group('brushInputSamplesToStrokePoints', () {
    test('empty input returns empty list', () {
      final points = brushInputSamplesToStrokePoints(const []);

      expect(points, isEmpty);
      expect(
        () => points.add(const StrokePoint(x: 1, y: 2)),
        throwsUnsupportedError,
      );
    });

    test('single sample converts to one StrokePoint', () {
      final points = brushInputSamplesToStrokePoints([
        BrushInputSample(x: 1, y: 2, pressure: 0.25, sequence: 5),
      ]);

      expect(points, const [StrokePoint(x: 1, y: 2)]);
    });

    test('multiple samples preserve order', () {
      final samples = [
        BrushInputSample(x: 1, y: 2, sequence: 0),
        BrushInputSample(x: 3, y: 4, sequence: 1),
        BrushInputSample(x: 5, y: 6, sequence: 2),
      ];

      expect(brushInputSamplesToStrokePoints(samples), const [
        StrokePoint(x: 1, y: 2),
        StrokePoint(x: 3, y: 4),
        StrokePoint(x: 5, y: 6),
      ]);
    });

    test(
      'source samples remain unchanged after pressure is omitted from points',
      () {
        final sample = BrushInputSample(
          x: 1,
          y: 2,
          pressure: 0.25,
          sequence: 1,
        );
        final samples = [sample];

        brushInputSamplesToStrokePoints(samples);

        expect(samples.single, sample);
        expect(samples.single.pressure, 0.25);
        expect(samples.single.sequence, 1);
      },
    );

    test('output list is unmodifiable', () {
      final points = brushInputSamplesToStrokePoints([
        BrushInputSample(x: 1, y: 2),
      ]);

      expect(
        () => points.add(const StrokePoint(x: 3, y: 4)),
        throwsUnsupportedError,
      );
    });

    test('input list is not mutated', () {
      final samples = [
        BrushInputSample(x: 1, y: 2, pressure: 0.25, sequence: 1),
        BrushInputSample(x: 3, y: 4, pressure: 0.75, sequence: 2),
      ];
      final original = List<BrushInputSample>.of(samples);

      brushInputSamplesToStrokePoints(samples);

      expect(samples, original);
    });
  });
}

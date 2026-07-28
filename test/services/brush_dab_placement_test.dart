import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_input_sample.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/services/brush_dab_placement.dart';

void main() {
  group('brushInputSamplesToBrushDabs', () {
    final settings = BrushSettings(size: 10, spacing: 0.5);

    test('empty samples returns empty sequence', () {
      expect(
        brushInputSamplesToBrushDabs(samples: [], settings: settings).isEmpty,
        isTrue,
      );
    });

    test('one sample returns one dab', () {
      final sequence = brushInputSamplesToBrushDabs(
        samples: [BrushInputSample(x: 1, y: 2)],
        settings: settings,
      );
      expect(sequence.length, 1);
      expect(sequence.dabs.single.center.x, 1);
      expect(sequence.dabs.single.center.y, 2);
    });

    test('two samples shorter than spacing returns first and final dabs', () {
      final sequence = brushInputSamplesToBrushDabs(
        samples: [BrushInputSample(x: 0, y: 0), BrushInputSample(x: 3, y: 0)],
        settings: settings,
      );
      expect(sequence.dabs.map((dab) => dab.center.x), [0, 3]);
    });

    test(
      'two samples exactly one spacing apart returns first and final dabs without duplicate endpoint',
      () {
        final sequence = brushInputSamplesToBrushDabs(
          samples: [BrushInputSample(x: 0, y: 0), BrushInputSample(x: 5, y: 0)],
          settings: settings,
        );
        expect(sequence.dabs.map((dab) => dab.center.x), [0, 5]);
      },
    );

    test(
      'two samples crossing multiple spacing intervals emits interpolated dabs',
      () {
        final sequence = brushInputSamplesToBrushDabs(
          samples: [
            BrushInputSample(x: 0, y: 0),
            BrushInputSample(x: 12, y: 0),
          ],
          settings: settings,
        );
        expect(sequence.dabs.map((dab) => dab.center.x), [0, 5, 10, 12]);
      },
    );

    test('zero-length repeated sample does not emit duplicate dabs', () {
      final sequence = brushInputSamplesToBrushDabs(
        samples: [BrushInputSample(x: 0, y: 0), BrushInputSample(x: 0, y: 0)],
        settings: settings,
      );
      expect(sequence.length, 1);
    });

    test('multiple segments preserve direction', () {
      final sequence = brushInputSamplesToBrushDabs(
        samples: [
          BrushInputSample(x: 0, y: 0),
          BrushInputSample(x: 6, y: 0),
          BrushInputSample(x: 6, y: 6),
        ],
        settings: settings,
      );
      expect(sequence.dabs.map((dab) => [dab.center.x, dab.center.y]), [
        [0, 0],
        [5, 0],
        [6, 4],
        [6, 6],
      ]);
    });

    test('pressure is interpolated between samples', () {
      final sequence = brushInputSamplesToBrushDabs(
        samples: [
          BrushInputSample(x: 0, y: 0, pressure: 0),
          BrushInputSample(x: 10, y: 0, pressure: 1),
        ],
        settings: settings,
      );
      expect(sequence.dabs.map((dab) => dab.pressure), [0, 0.5, 1]);
    });

    test('the size pressure curve affects emitted dab size', () {
      final sequence = brushInputSamplesToBrushDabs(
        samples: [BrushInputSample(x: 0, y: 0, pressure: 0.5)],
        settings: settings.copyWith(
          sizePressureCurve: BrushPressureCurve.identity(),
        ),
      );
      expect(sequence.dabs.single.size, 5);
    });

    test('the opacity pressure curve affects emitted dab opacity', () {
      final sequence = brushInputSamplesToBrushDabs(
        samples: [BrushInputSample(x: 0, y: 0, pressure: 0.5)],
        settings: settings.copyWith(
          opacity: 0.8,
          opacityPressureCurve: BrushPressureCurve.identity(),
        ),
      );
      expect(sequence.dabs.single.opacity, 0.4);
    });

    test('preserves BrushSettings color into every emitted dab', () {
      final sequence = brushInputSamplesToBrushDabs(
        samples: [BrushInputSample(x: 0, y: 0), BrushInputSample(x: 12, y: 0)],
        settings: settings.copyWith(color: 0x80FF3366),
      );
      expect(sequence.dabs.map((dab) => dab.color), everyElement(0x80FF3366));
    });

    test('sequence numbers start at 0 and increase by 1', () {
      final sequence = brushInputSamplesToBrushDabs(
        samples: [BrushInputSample(x: 0, y: 0), BrushInputSample(x: 12, y: 0)],
        settings: settings,
      );
      expect(sequence.dabs.map((dab) => dab.sequence), [0, 1, 2, 3]);
    });

    test('final sample is emitted when not already represented', () {
      final sequence = brushInputSamplesToBrushDabs(
        samples: [BrushInputSample(x: 0, y: 0), BrushInputSample(x: 6, y: 0)],
        settings: settings,
      );
      expect(sequence.dabs.map((dab) => dab.center.x), [0, 5, 6]);
    });

    test('function does not mutate input sample list', () {
      final samples = [
        BrushInputSample(x: 0, y: 0),
        BrushInputSample(x: 12, y: 0),
      ];
      final before = List<BrushInputSample>.from(samples);
      brushInputSamplesToBrushDabs(samples: samples, settings: settings);
      expect(samples, before);
    });
  });
}

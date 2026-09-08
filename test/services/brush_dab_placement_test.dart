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
      // F-12: the curve lands on the dab, the setting on the SEQUENCE.
      expect(sequence.dabs.single.opacity, 0.5);
      expect(sequence.opacity, 0.8);
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

    test('altitude interpolates along the segment', () {
      final sequence = brushInputSamplesToBrushDabs(
        samples: [
          BrushInputSample(x: 0, y: 0, tiltAltitude: 1.0),
          BrushInputSample(x: 20, y: 0, tiltAltitude: 0.0),
        ],
        settings: settings,
      );

      final middle = sequence.dabs.firstWhere((dab) => dab.center.x == 10);
      expect(middle.tiltAltitude, closeTo(0.5, 1e-9));
    });

    test('azimuth crosses 0 the short way, not the long way', () {
      // 350 -> 10 is twenty degrees forward. A plain lerp would walk the pen
      // 340 degrees BACKWARDS and put the midpoint at 180 — pointing the
      // opposite way from either end.
      final sequence = brushInputSamplesToBrushDabs(
        samples: [
          BrushInputSample(x: 0, y: 0, tiltAzimuthDegrees: 350, tiltAltitude: 0.5),
          BrushInputSample(x: 20, y: 0, tiltAzimuthDegrees: 10, tiltAltitude: 0.5),
        ],
        settings: settings,
      );

      final middle = sequence.dabs.firstWhere((dab) => dab.center.x == 10);
      expect(middle.tiltAzimuthDegrees, closeTo(0.0, 1e-9));
    });

    test('the four curves are applied here, not in the dab factory', () {
      // 🚨These four assertions moved out of `brush_dab_test` when the
      // multiplication stopped being a third copy inside
      // `BrushDab.fromInputSample`. The factory now carries base values;
      // the product is this function's job, so the coverage lives here.
      final sequence = brushInputSamplesToBrushDabs(
        samples: [BrushInputSample(x: 0, y: 0, pressure: 0.25)],
        settings: BrushSettings(
          size: 20,
          flow: 0.8,
          hardness: 0.5,
          sizePressureCurve: BrushPressureCurve.identity(),
          opacityPressureCurve: BrushPressureCurve.identity(),
          flowPressureCurve: BrushPressureCurve.identity(),
          hardnessPressureCurve: BrushPressureCurve.identity(),
        ),
      );

      final dab = sequence.dabs.single;
      expect(dab.size, 5);
      expect(dab.flow, closeTo(0.2, 1e-9));
      expect(dab.hardness, closeTo(0.125, 1e-9));
      // F-12: the CURVE alone, because the base is 1.0. The setting is the
      // accumulated stroke's ceiling and rides `BrushDabSequence.opacity`.
      expect(dab.opacity, closeTo(0.25, 1e-9));
      expect(sequence.opacity, 1.0);
    });

    test('no curve leaves the base values alone', () {
      final sequence = brushInputSamplesToBrushDabs(
        samples: [BrushInputSample(x: 0, y: 0, pressure: 0.25)],
        settings: BrushSettings(size: 20, flow: 0.8, hardness: 0.5),
      );

      final dab = sequence.dabs.single;
      expect(dab.size, 20);
      expect(dab.flow, 0.8);
      expect(dab.hardness, 0.5);
      expect(dab.opacity, 1.0);
    });

    test('an upright stroke leaves every dab upright', () {
      final sequence = brushInputSamplesToBrushDabs(
        samples: [BrushInputSample(x: 0, y: 0), BrushInputSample(x: 20, y: 0)],
        settings: settings,
      );

      expect(
        sequence.dabs.every(
          (dab) => dab.tiltAltitude == 1.0 && dab.tiltAzimuthDegrees == 0.0,
        ),
        isTrue,
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_correction.dart';
import 'package:anicel/src/models/brush_settings.dart';

void main() {
  group('the 손떨림 보정 scale (F-418-Q6)', () {
    test('0 steadies nothing', () {
      expect(BrushCorrection.none.lag, isNull);
    });

    test("1 is Clip Studio's 0, and 100 its 100", () {
      expect(BrushCorrection.fromClipStudio(0), 1);
      expect(BrushCorrection.fromClipStudio(100), 100);
      expect(BrushCorrection.fromClipStudio(50), closeTo(50.5, 1e-9));
      expect(BrushCorrection.fromClipStudio(-3), 1, reason: 'clamped');
      expect(BrushCorrection.fromClipStudio(250), 100, reason: 'clamped');
    });

    test("the line lags Clip Studio's own at its ends, evenly between", () {
      Duration? lagAt(double stabilization) =>
          BrushCorrection(stabilization: stabilization).lag;
      expect(lagAt(1), BrushCorrection.lagAtClipStudioZero);
      expect(lagAt(100), BrushCorrection.lagAtClipStudioHundred);
      final halfway = BrushCorrection.fromClipStudio(50);
      final from = BrushCorrection.lagAtClipStudioZero.inMicroseconds;
      final to = BrushCorrection.lagAtClipStudioHundred.inMicroseconds;
      expect(
        lagAt(halfway)!.inMicroseconds,
        ((from + to) / 2).round(),
      );
      expect(
        lagAt(0.5),
        BrushCorrection.lagAtClipStudioZero,
        reason: "below 1 is still Clip Studio's 0",
      );
    });

    test("a brush that says nothing steadies as Clip Studio's 0", () {
      expect(const BrushCorrection().stabilization, 1);
      expect(BrushSettings().correction, const BrushCorrection());
      expect(BrushCorrection.fromJson(null), const BrushCorrection());
      expect(BrushCorrection.fromJson(const {}), const BrushCorrection());
    });
  });

  group("the brush's own, kept in its preset (F-418-Q6)", () {
    test('a preset carries it there and back', () {
      final brush = BrushSettings(
        correction: const BrushCorrection(stabilization: 37),
      );
      final back = BrushSettings.fromJson(brush.toJson());
      expect(back.correction, const BrushCorrection(stabilization: 37));
      expect(back, brush);
    });

    test('at its default it writes nothing, so an older preset reads the '
        'same bytes back', () {
      expect(BrushSettings().toJson().containsKey('correction'), isFalse);
      expect(
        BrushSettings(correction: BrushCorrection.none)
            .toJson()
            .containsKey('correction'),
        isTrue,
      );
    });

    test('a value off the scale is refused', () {
      for (final stabilization in [-1.0, 100.5, double.nan]) {
        expect(
          () => BrushSettings(
            correction: BrushCorrection(stabilization: stabilization),
          ),
          throwsArgumentError,
          reason: '$stabilization',
        );
      }
      expect(
        BrushSettings(correction: BrushCorrection.none).correction,
        BrushCorrection.none,
      );
      expect(
        BrushSettings(
          correction: const BrushCorrection(stabilization: 100),
        ).correction.stabilization,
        100,
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';

/// 速度 is the one input with no hardware ceiling, so the ratio's denominator
/// is a SETTING (유저 확정 2026-09-08). These pin the division and the two
/// ways it can decline to answer.
void main() {
  group('AppInput.normalizedSpeed', () {
    late AppInputSettings saved;

    setUp(() {
      saved = AppInput.settings.value;
    });

    tearDown(() {
      AppInput.settings.value = saved;
    });

    test('the default reference is 2000 canvas px/s', () {
      expect(
        const AppInputSettings().speedReferencePixelsPerSecond,
        AppInputSettings.defaultSpeedReferencePixelsPerSecond,
      );
      expect(AppInputSettings.defaultSpeedReferencePixelsPerSecond, 2000.0);
    });

    test('half the reference speed reads as half input', () {
      expect(
        AppInput.normalizedSpeed(
          canvasPixels: 1000,
          elapsed: const Duration(seconds: 1),
        ),
        closeTo(0.5, 1e-9),
      );
    });

    test('the reference speed itself reads as 1.0, and faster still 1.0', () {
      expect(
        AppInput.normalizedSpeed(
          canvasPixels: 2000,
          elapsed: const Duration(seconds: 1),
        ),
        closeTo(1.0, 1e-9),
      );
      expect(
        AppInput.normalizedSpeed(
          canvasPixels: 20000,
          elapsed: const Duration(seconds: 1),
        ),
        1.0,
      );
    });

    test('the divisor is the LIVE setting, not the default', () {
      // The whole point of making it a setting: moving the slider has to
      // change what a brush measures, or the control is decoration.
      AppInput.settings.value = const AppInputSettings(
        speedReferencePixelsPerSecond: 500,
      );

      expect(
        AppInput.normalizedSpeed(
          canvasPixels: 250,
          elapsed: const Duration(seconds: 1),
        ),
        closeTo(0.5, 1e-9),
      );
    });

    test('milliseconds are seconds, not ticks', () {
      // 20 px in 10 ms is 2000 px/s — the reference exactly.
      expect(
        AppInput.normalizedSpeed(
          canvasPixels: 20,
          elapsed: const Duration(milliseconds: 10),
        ),
        closeTo(1.0, 1e-9),
      );
    });

    test('two readings on one clock tick answer NULL, not zero', () {
      // 🚨The distinction the caller depends on: null means "no measurement
      // here, keep the last one". Zero would drop a fast stroke to a dead
      // stop for one dab every time the platform coalesced two readings.
      expect(
        AppInput.normalizedSpeed(canvasPixels: 40, elapsed: Duration.zero),
        isNull,
      );
      expect(
        AppInput.normalizedSpeed(
          canvasPixels: 40,
          elapsed: const Duration(microseconds: -1),
        ),
        isNull,
      );
    });

    test('a zero reference from a corrupt file answers null, not NaN', () {
      AppInput.settings.value = const AppInputSettings(
        speedReferencePixelsPerSecond: 0,
      );

      // 0 px over 0 px/s is NaN, and NaN survives `clamp` — it would reach
      // `BrushDab`'s 0..1 validator and throw mid-stroke.
      expect(
        AppInput.normalizedSpeed(
          canvasPixels: 0,
          elapsed: const Duration(seconds: 1),
        ),
        isNull,
      );
    });

    test('a non-finite distance answers null', () {
      expect(
        AppInput.normalizedSpeed(
          canvasPixels: double.nan,
          elapsed: const Duration(seconds: 1),
        ),
        isNull,
      );
    });

    test('the reference survives a settings round-trip', () {
      const settings = AppInputSettings(speedReferencePixelsPerSecond: 3500);

      final restored = AppInputSettings.fromJson(settings.toJson());
      expect(restored.speedReferencePixelsPerSecond, 3500);
      expect(restored, settings);
    });

    test('a settings file written before speed existed reads the default', () {
      final old = const AppInputSettings().toJson()
        ..remove('speedReferencePixelsPerSecond');

      expect(
        AppInputSettings.fromJson(old).speedReferencePixelsPerSecond,
        AppInputSettings.defaultSpeedReferencePixelsPerSecond,
      );
    });

    test('the reference takes part in equality', () {
      expect(
        const AppInputSettings() ==
            const AppInputSettings(speedReferencePixelsPerSecond: 1000),
        isFalse,
      );
    });
  });
}

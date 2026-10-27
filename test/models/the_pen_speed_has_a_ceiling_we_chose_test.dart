import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';

/// 速度 is the one input with no hardware ceiling, so the ratio's denominator
/// is one the app fixes: 🗣️F-480-Q1 (유저 2026-10-27) 「없앤다 — 기준은 앱이
/// 고정(2000 px/s)」. ↩️It was a setting (유저 확정 2026-09-08). These pin the
/// division and the two ways it can decline to answer.
void main() {
  group('AppInput.normalizedSpeed', () {
    test('the ceiling is 2000 canvas px/s', () {
      expect(AppInputSettings.speedReferencePixelsPerSecond, 2000.0);
    });

    test('half the ceiling reads as half input', () {
      expect(
        AppInput.normalizedSpeed(
          canvasPixels: 1000,
          elapsed: const Duration(seconds: 1),
        ),
        closeTo(0.5, 1e-9),
      );
    });

    test('the ceiling itself reads as 1.0, and faster still 1.0', () {
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

    test('milliseconds are seconds, not ticks', () {
      // 20 px in 10 ms is 2000 px/s — the ceiling exactly.
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

    test('a non-finite distance answers null', () {
      // NaN survives `clamp` — it would reach `BrushDab`'s 0..1 validator
      // and throw mid-stroke.
      expect(
        AppInput.normalizedSpeed(
          canvasPixels: double.nan,
          elapsed: const Duration(seconds: 1),
        ),
        isNull,
      );
    });
  });

  test('a settings file that still names a speed reads as the settings', () {
    final written = {
      ...const AppInputSettings().toJson(),
      'speedReferencePixelsPerSecond': 500,
    };

    expect(AppInputSettings.fromJson(written), const AppInputSettings());
  });
}

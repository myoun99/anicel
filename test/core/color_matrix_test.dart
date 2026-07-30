import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/color_matrix.dart';

/// The color effects' math core (R6). Pure functions, so the CONTRACT is
/// testable without a canvas: what each slider does at its ends, and that
/// composition means "inner first".
void main() {
  /// Applies a 4×5 matrix the way Skia does: unpremultiplied channels in
  /// 0…255, translation column added, result clamped.
  List<double> applyUnclamped(List<double> matrix, List<double> rgba) {
    final out = <double>[];
    for (var row = 0; row < 4; row += 1) {
      var value = matrix[row * 5 + 4];
      for (var column = 0; column < 4; column += 1) {
        value += matrix[row * 5 + column] * rgba[column];
      }
      out.add(value);
    }
    return out;
  }

  List<double> apply(List<double> matrix, List<double> rgba) => [
    for (final value in applyUnclamped(matrix, rgba)) value.clamp(0.0, 255.0),
  ];

  test('the identity leaves every channel alone', () {
    expect(colorMatrixIsIdentity(identityColorMatrix), isTrue);
    expect(apply(identityColorMatrix, [10, 20, 30, 40]), [10, 20, 30, 40]);
  });

  group('brightness/contrast', () {
    test('zeroes are the identity — an added effect changes nothing', () {
      final matrix = brightnessContrastMatrix(brightness: 0, contrast: 0);
      expect(colorMatrixIsIdentity(matrix), isTrue);
    });

    test('brightness adds a fraction of full scale, alpha untouched', () {
      final matrix = brightnessContrastMatrix(brightness: 20, contrast: 0);
      final out = apply(matrix, [100, 100, 100, 128]);
      expect(out[0], closeTo(100 + 51, 0.001)); // 20 % of 255
      expect(out[3], 128, reason: 'colour effects never touch alpha');
    });

    test('contrast +100 doubles the distance from mid grey', () {
      final matrix = brightnessContrastMatrix(brightness: 0, contrast: 100);
      expect(
        apply(matrix, [127.5, 127.5, 127.5, 255])[0],
        closeTo(127.5, 0.01),
        reason: 'mid grey is the pivot',
      );
      expect(apply(matrix, [160, 160, 160, 255])[0], closeTo(192.5, 0.01));
    });

    test('contrast -100 flattens everything to mid grey', () {
      final matrix = brightnessContrastMatrix(brightness: 0, contrast: -100);
      expect(apply(matrix, [0, 0, 0, 255])[0], closeTo(127.5, 0.01));
      expect(apply(matrix, [255, 255, 255, 255])[0], closeTo(127.5, 0.01));
    });
  });

  group('hue / saturation / lightness', () {
    test('all zero is the identity', () {
      expect(
        colorMatrixIsIdentity(
          hueSaturationMatrix(hueDegrees: 0, saturation: 0, lightness: 0),
        ),
        isTrue,
      );
    });

    test('saturation -100 leaves the Rec.709 luminance in every channel', () {
      final matrix = saturationMatrix(-100);
      final out = apply(matrix, [255, 0, 0, 255]);
      final luminance = 255 * luminanceR;
      expect(out[0], closeTo(luminance, 0.01));
      expect(out[1], closeTo(luminance, 0.01));
      expect(out[2], closeTo(luminance, 0.01));
    });

    test('saturation +100 pushes a colour away from its own grey', () {
      final out = apply(saturationMatrix(100), [200, 100, 100, 255]);
      expect(out[0], greaterThan(200));
      expect(out[1], lessThan(100));
    });

    test('a hue rotation of 360° is a no-op; 120° moves red toward green', () {
      expect(
        colorMatrixIsIdentity(hueRotationMatrix(360), epsilon: 1e-9),
        isTrue,
      );
      final out = apply(hueRotationMatrix(120), [255, 0, 0, 255]);
      expect(
        out[1],
        greaterThan(out[0]),
        reason: 'the dominant channel moved off red',
      );
    });

    test('lightness ±100 washes to white and to black', () {
      expect(
        apply(lightnessMatrix(100), [10, 20, 30, 255]).take(3),
        everyElement(closeTo(255, 0.01)),
      );
      expect(
        apply(lightnessMatrix(-100), [10, 20, 30, 255]).take(3),
        everyElement(closeTo(0, 0.01)),
      );
    });

    test('grey survives a hue rotation (the chroma plane is empty)', () {
      final out = apply(hueRotationMatrix(75), [128, 128, 128, 255]);
      expect(out.take(3), everyElement(closeTo(128, 0.5)));
    });
  });

  group('composition', () {
    test('outer ∘ inner applies inner FIRST', () {
      // Contrast and lightness do NOT commute (one pivots on mid grey, the
      // other scales toward black), so the two orders give different
      // numbers — which is what pins the argument order down.
      final contrast = brightnessContrastMatrix(brightness: 0, contrast: 100);
      final darker = lightnessMatrix(-50);
      final contrastFirst = apply(composeColorMatrices(darker, contrast), [
        200,
        200,
        200,
        255,
      ]);
      final darkerFirst = apply(composeColorMatrices(contrast, darker), [
        200,
        200,
        200,
        255,
      ]);
      // contrast: 2·(200−127.5)+127.5 = 272.5, then ·0.5 → 136.25.
      expect(contrastFirst[0], closeTo(136.25, 0.01));
      // ·0.5 → 100, then contrast: 2·(100−127.5)+127.5 = 72.5.
      expect(darkerFirst[0], closeTo(72.5, 0.01));
    });

    test('composing with the identity changes nothing', () {
      final matrix = hueSaturationMatrix(
        hueDegrees: 30,
        saturation: 12,
        lightness: -5,
      );
      final composed = composeColorMatrices(identityColorMatrix, matrix);
      for (var index = 0; index < 20; index += 1) {
        expect(composed[index], closeTo(matrix[index], 1e-9));
      }
    });

    test('the folded hue/sat/lightness equals the three applied in order', () {
      // Unclamped on purpose: folding into ONE matrix is what SKIPS the
      // intermediate clamp, so the identity holds against the unclamped
      // chain — and a hue rotation of a saturated colour does leave the
      // 0…255 box on the way, which is exactly the channel the fold saves.
      const rgba = [200.0, 90.0, 40.0, 255.0];
      final folded = applyUnclamped(
        hueSaturationMatrix(hueDegrees: 40, saturation: 25, lightness: -20),
        rgba,
      );
      final stepwise = applyUnclamped(
        lightnessMatrix(-20),
        applyUnclamped(
          saturationMatrix(25),
          applyUnclamped(hueRotationMatrix(40), rgba),
        ),
      );
      for (var index = 0; index < 4; index += 1) {
        expect(folded[index], closeTo(stepwise[index], 1e-9));
      }
    });
  });
}

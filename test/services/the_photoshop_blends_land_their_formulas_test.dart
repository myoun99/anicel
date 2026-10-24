import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/separable_blend_mode.dart';
import 'package:anicel/src/services/brush_stroke_blend.dart';

/// brush-fidelity (유저 2026-10-17 Q3: 「13개 + 클튜의 발광 둘」): the
/// thirteen blends Photoshop and Clip Studio share beyond the first twelve,
/// pinned by their FORMULAS — the native parity suite holds C to the Dart
/// reference byte for byte, but two transcriptions of one wrong formula
/// agree with each other perfectly.
///
/// Every expectation was worked by hand and checked against an independent
/// transcription of the W3C pseudo-code (SetSat by ranking max/mid/min, not
/// the kernel's Skia form). Opaque over opaque, the composite is B itself.
void main() {
  List<int> land(BrushBlendMode mode, List<int> src, List<int> dst) =>
      blendStrokeRegionPixels(
        dst: Uint8List.fromList(dst),
        src: Uint8List.fromList(src),
        mode: mode,
        pixelCount: src.length ~/ 4,
      );

  group('the seven that blend channel by channel', () {
    test('linear burn adds the two and takes a whole away — not colour '
        'burn\'s quotient', () {
      // Colour burn would make the red 121.
      const stroke = [200, 100, 30, 255];
      const cel = [150, 100, 255, 255];
      expect(land(BrushBlendMode.linearBurn, stroke, cel), [95, 0, 30, 255]);
    });

    test('subtract takes the stroke from the cel and stops at black — not '
        'difference\'s distance', () {
      // Difference would make the green 150.
      expect(
        land(BrushBlendMode.subtract, [100, 200, 0, 255], [150, 50, 255, 255]),
        [50, 0, 255, 255],
      );
    });

    test('vivid light burns below the middle and dodges above it', () {
      const strokes = [64, 192, 0, 255, 255, 255, 255, 255];
      const cels = [200, 100, 128, 255, 128, 128, 128, 255];
      expect(
        land(BrushBlendMode.vividLight, strokes, cels),
        [145, 202, 0, 255, 255, 255, 255, 255],
      );
    });

    test('linear light moves the cel by twice the stroke\'s distance from '
        'the middle, clamped both ways', () {
      const strokes = [150, 192, 255, 255, 20, 20, 20, 255];
      const cels = [100, 100, 200, 255, 100, 100, 100, 255];
      expect(
        land(BrushBlendMode.linearLight, strokes, cels),
        [145, 229, 255, 255, 0, 0, 0, 255],
      );
    });

    test('pin light keeps the darker of the two below the middle and the '
        'lighter above it', () {
      const strokes = [64, 64, 192, 255, 192, 192, 192, 255];
      const cels = [200, 100, 100, 255, 200, 200, 200, 255];
      expect(
        land(BrushBlendMode.pinLight, strokes, cels),
        [128, 100, 129, 255, 200, 200, 200, 255],
      );
    });

    test('hard mix goes all the way: white where the bytes reach 255 '
        'together, black a byte short', () {
      expect(
        land(BrushBlendMode.hardMix, [100, 100, 200, 255], [155, 154, 55, 255]),
        [255, 0, 255, 255],
      );
    });

    test('divide is the cel over the stroke, nothing over anything is '
        'nothing and anything over nothing is white', () {
      const strokes = [200, 0, 100, 255, 100, 100, 100, 255];
      const cels = [50, 50, 0, 255, 200, 200, 200, 255];
      expect(
        land(BrushBlendMode.divide, strokes, cels),
        [64, 255, 0, 255, 255, 255, 255, 255],
      );
    });

    test('the dual tip combines two coverages through the same rows', () {
      expect(
        blendDualCoverage(SeparableBlendMode.linearBurn, 0.75, 0.5),
        closeTo(0.25, 1e-12),
      );
      expect(blendDualCoverage(SeparableBlendMode.hardMix, 0.5, 0.5), 1.0);
      expect(blendDualCoverage(SeparableBlendMode.hardMix, 0.5, 0.25), 0.0);
      expect(blendDualCoverage(SeparableBlendMode.subtract, 0.25, 0.5), 0.25);
    });
  });

  group('the six that mix the three channels', () {
    const red = [255, 0, 0, 255];
    const slate = [100, 100, 200, 255];

    test('hue takes the stroke\'s hue at the cel\'s saturation and '
        'luminosity', () {
      expect(land(BrushBlendMode.hue, red, slate), [181, 81, 81, 255]);
    });

    test('saturation takes the stroke\'s saturation, the cel\'s hue and '
        'luminosity — clipped back into range', () {
      expect(land(BrushBlendMode.saturation, red, slate), [93, 93, 255, 255]);
    });

    test('colour takes the stroke\'s hue and saturation at the cel\'s '
        'luminosity', () {
      expect(land(BrushBlendMode.chroma, red, slate), [255, 49, 49, 255]);
    });

    test('luminosity takes the stroke\'s luminosity, the cel\'s hue and '
        'saturation', () {
      expect(
        land(BrushBlendMode.luminosity, [255, 255, 0, 255], slate),
        [223, 223, 255, 255],
      );
    });

    test('darker and lighter colour keep one colour whole by its channel '
        'total, and a tie keeps the cel', () {
      const strokes = [200, 0, 0, 255, 10, 20, 30, 255, 1, 2, 3, 255];
      const cels = [50, 50, 50, 255, 100, 0, 0, 255, 2, 2, 2, 255];
      expect(land(BrushBlendMode.darkerColor, strokes, cels), [
        50, 50, 50, 255, 10, 20, 30, 255, 2, 2, 2, 255, //
      ]);
      expect(land(BrushBlendMode.lighterColor, strokes, cels), [
        200, 0, 0, 255, 100, 0, 0, 255, 2, 2, 2, 255, //
      ]);
    });

    test('a half-covering stroke composites like every other blend', () {
      // (1 - αs)·Cd + αs·B over an opaque cel, B the hue above.
      expect(
        land(BrushBlendMode.hue, [255, 0, 0, 128], slate),
        [141, 90, 140, 255],
      );
    });
  });
}

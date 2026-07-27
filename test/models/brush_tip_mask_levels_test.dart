import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/models/brush_tip_mask.dart';

BrushTipMask maskOf(List<int> alpha) =>
    BrushTipMask(id: 't', size: 2, alpha: Uint8List.fromList(alpha));

void main() {
  test('neutral levels return the mask untouched', () {
    final mask = maskOf(const [0, 80, 160, 255]);

    expect(identical(brushTipMaskWithLevels(mask), mask), isTrue);
  });

  test('invert flips coverage', () {
    final out = brushTipMaskWithLevels(
      maskOf(const [0, 80, 160, 255]),
      invert: true,
    );

    expect(out.alpha, [255, 175, 95, 0]);
  });

  test('brightness scales coverage down without annihilating it', () {
    // The trap this guards: read as an offset, ウェット水彩's brightness of
    // 75 subtracts more than any texture holds and flattens the grain to
    // nothing. As a lerp toward white it thins the paper instead.
    final out = brushTipMaskWithLevels(
      maskOf(const [0, 80, 160, 255]),
      brightness: 0.75,
    );

    expect(out.alpha, [0, 20, 40, 64]);
    expect(out.alpha.any((a) => a > 0), isTrue);
  });

  test('negative brightness pushes coverage up, still bounded', () {
    final out = brushTipMaskWithLevels(
      maskOf(const [0, 80, 160, 255]),
      brightness: -0.75,
    );

    expect(out.alpha.first, greaterThan(0));
    expect(out.alpha.last, 255);
    expect(out.alpha, everyElement(lessThanOrEqualTo(255)));
  });

  test('contrast pivots on mid-grey', () {
    // Mid-grey is the fixed point, so contrast means the same thing whether
    // it is applied to the image or to the coverage that image inverts to.
    final out = brushTipMaskWithLevels(
      maskOf(const [0, 128, 255, 128]),
      contrast: -1.0,
    );

    expect(out.alpha, [128, 128, 128, 128]);
  });
}

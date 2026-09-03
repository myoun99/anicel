// TWO COMPOSITE PAINTS ARE THE SAME PAINT WHEN EVERY FILTER MATCHES.
//
// The caches compare these to decide whether a composited picture can be
// reused. The mutation campaign (2026-09-03) turned the image-filter
// comparison in `==` into `!=` and nothing noticed. These pins do.
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/composite_effect_paint.dart';

void main() {
  final blur1 = ui.ImageFilter.blur(sigmaX: 1, sigmaY: 1);
  final blur2 = ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2);

  test('same filters and outset: equal', () {
    expect(
      CompositeEffectPaint(imageFilter: blur1, outsetPixels: 2),
      equals(CompositeEffectPaint(imageFilter: blur1, outsetPixels: 2)),
    );
  });

  test('a different image filter is a different paint', () {
    expect(
      CompositeEffectPaint(imageFilter: blur1),
      isNot(equals(CompositeEffectPaint(imageFilter: blur2))),
    );
  });

  test('a different outset is a different paint', () {
    expect(
      CompositeEffectPaint(imageFilter: blur1, outsetPixels: 1),
      isNot(equals(CompositeEffectPaint(imageFilter: blur1, outsetPixels: 3))),
    );
  });
}

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';

/// The one square padding behind every tip source (the audit's clone scan,
/// 2026-09-03). A "not centred" mutant survived the decoder, cut-piece and
/// ABR tests — each pads a square already — so the padding is measured on
/// its own here.
void main() {
  test('a wide strip lands on the MIDDLE row of its square', () {
    final mask = BrushTipMask.square(
      id: 'strip',
      pixels: Uint8List.fromList([10, 20, 30]),
      width: 3,
      height: 1,
    );
    expect(mask.size, 3);
    expect(mask.alpha, [0, 0, 0, 10, 20, 30, 0, 0, 0]);
  });

  test('a tall strip lands on the MIDDLE column of its square', () {
    final mask = BrushTipMask.square(
      id: 'column',
      pixels: Uint8List.fromList([10, 20, 30]),
      width: 1,
      height: 3,
    );
    expect(mask.size, 3);
    expect(mask.alpha, [0, 10, 0, 0, 20, 0, 0, 30, 0]);
  });

  test('a square is copied as it is', () {
    final mask = BrushTipMask.square(
      id: 'square',
      pixels: Uint8List.fromList([1, 2, 3, 4]),
      width: 2,
      height: 2,
    );
    expect(mask.size, 2);
    expect(mask.alpha, [1, 2, 3, 4]);
  });
}

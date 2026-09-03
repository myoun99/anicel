// EVERY BUNDLED TIP AND TEXTURE MASK IS A FULL 64-SIDED SQUARE.
//
// A survivor of the mutation campaign (2026-09-03): the chalk generator's
// row loop bound `y < size` became `y <= size`, which walks one row past
// the buffer. No test ever touched the generated masks; this one does,
// for all seven.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/brush_tip_mask_defaults.dart';

void main() {
  test('every bundled mask is 64 a side with an alpha per cell', () {
    final masks = [
      chalkBrushTipMask,
      splatterBrushTipMask,
      grainBrushTipMask,
      bristleBrushTipMask,
      spongeBrushTipMask,
      paperGrainTextureMask,
      canvasWeaveTextureMask,
    ];
    for (final mask in masks) {
      expect(mask.size, 64, reason: mask.id);
      expect(mask.alpha.length, 64 * 64, reason: mask.id);
    }
  });
}

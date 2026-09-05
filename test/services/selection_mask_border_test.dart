// THE CANVAS BORDER COUNTS AS OUTSIDE FOR A SELECTION MASK'S POST-PASSES.
//
// A shrink erodes a pixel that sits on the border even when no zero
// neighbour is inside the window, and a feather ramps a border pixel as if
// the pixel beyond the edge were outside — chamfer distance 3, one
// orthogonal step. Neither law had a pin: both kernels could have dropped
// the border rule and every existing test stayed green (they select a
// rect in the middle of the window).
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';

void main() {
  /// A rect from (0, 0) to (4, 4) in an 8×8 window: its left and top
  /// edges ARE the window border.
  final cornerRect = CanvasSelectionRegion.shape(
    CanvasSelectionShape.rect(left: 0, top: 0, right: 4, bottom: 4),
  );

  test('shrinking erodes a pixel on the canvas border', () {
    final mask = buildSelectionMask(
      region: cornerRect,
      options: const SelectionMaskOptions(growPx: -1),
      left: 0,
      top: 0,
      width: 8,
      height: 8,
    );
    int at(int x, int y) => mask[y * 8 + x];

    expect(at(0, 1), 0, reason: 'on the left border: eroded');
    expect(at(1, 0), 0, reason: 'on the top border: eroded');
    expect(at(3, 1), 0, reason: 'the rim next to the outside: eroded');
    expect(at(1, 1), 255, reason: 'the interior keeps');
    expect(at(2, 2), 255, reason: 'the interior keeps');
  });

  test('feathering ramps a border pixel at chamfer distance 3', () {
    const featherPx = 3.0;
    final mask = buildSelectionMask(
      region: cornerRect,
      options: const SelectionMaskOptions(featherPx: featherPx),
      left: 0,
      top: 0,
      width: 8,
      height: 8,
    );
    int at(int x, int y) => mask[y * 8 + x];
    int ramp(int chamfer) => (chamfer / (featherPx * 3) * 255).round();

    expect(
      at(0, 1),
      ramp(3),
      reason: 'left border: one orthogonal step from "outside"',
    );
    expect(at(1, 0), ramp(3), reason: 'top border');
    expect(at(0, 0), ramp(3), reason: 'the corner');
    expect(at(1, 1), ramp(6), reason: 'one step in from the border');
    expect(at(3, 1), ramp(3), reason: 'the rim beside the real outside');
    expect(at(4, 4), 0, reason: 'outside stays out');
  });
}

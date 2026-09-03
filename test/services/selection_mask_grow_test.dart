// GROWING A SELECTION MASK BY ONE PIXEL ADDS EVERY PIXEL THAT TOUCHES IT ON
// A SIDE.
//
// The mutation campaign (2026-09-03) turned the grow pass's `||` into `&&`
// — a pixel then had to touch the mask on all four sides, so growth did
// nothing — and nothing noticed. This pin grows a 2×2 square.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';

void main() {
  test('growPx 1 adds the side neighbours and not the diagonal ones', () {
    final region = CanvasSelectionRegion.shape(
      CanvasSelectionShape.rect(left: 2, top: 2, right: 4, bottom: 4),
    );
    final mask = buildSelectionMask(
      region: region,
      options: const SelectionMaskOptions(growPx: 1),
      left: 0,
      top: 0,
      width: 8,
      height: 8,
    );
    int at(int x, int y) => mask[y * 8 + x];

    expect(at(2, 2), isNot(0), reason: 'the square itself');
    expect(at(3, 3), isNot(0), reason: 'the square itself');
    expect(at(1, 2), isNot(0), reason: 'grown one pixel left');
    expect(at(2, 1), isNot(0), reason: 'grown one pixel up');
    expect(at(4, 3), isNot(0), reason: 'grown one pixel right');
    expect(at(3, 4), isNot(0), reason: 'grown one pixel down');
    expect(at(1, 1), 0, reason: 'a diagonal neighbour stays out');
    expect(at(0, 2), 0, reason: 'two pixels away stays out');
  });
}

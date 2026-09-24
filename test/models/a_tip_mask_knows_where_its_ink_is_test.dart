import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';

/// A tip mask names, per row, the first and the last column holding any
/// ink — the native dab kernel narrows each pixel row to them (ABI 39,
/// board `brush-kernel-next` ②). A bare row is `size` and `-1`.
void main() {
  test('each row names its first and last inked column, a bare row none', () {
    // 4x4:
    //   row 0: bare
    //   row 1: ink at column 2 only
    //   row 2: ink at 0 and 3 (a hole between counts as inside)
    //   row 3: full
    final mask = BrushTipMask(
      id: 'ink-columns',
      size: 4,
      alpha: Uint8List.fromList([
        0, 0, 0, 0, //
        0, 0, 9, 0, //
        1, 0, 0, 255, //
        7, 7, 7, 7, //
      ]),
    );
    expect(mask.inkedColumns, [4, -1, 2, 2, 0, 3, 0, 3]);
  });

  test('the answer is read once and kept', () {
    final mask = BrushTipMask(
      id: 'ink-columns-once',
      size: 2,
      alpha: Uint8List.fromList([0, 5, 0, 0]),
    );
    expect(identical(mask.inkedColumns, mask.inkedColumns), isTrue);
    expect(mask.inkedColumns, [1, 1, 2, -1]);
  });
}

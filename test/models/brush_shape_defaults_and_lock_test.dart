// A BRUSH SHAPE SCATTERS ON BOTH AXES BY DEFAULT, AND ITS BLEND LOCK IS
// CLEARED ONLY WHEN THE CALLER SAYS SO.
//
// Two survivors of the mutation campaign (2026-09-03): the scatter default
// flipped to one axis, and copyWith's `clearBlendLock` default flipped to
// true (every copy then dropped the lock). Nothing noticed; these pins do.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_shape.dart';

void main() {
  test('a fresh shape scatters on both axes', () {
    expect(const BrushShape().scatterBothAxes, isTrue);
    expect(const BrushShape().scatterCount, 1);
  });

  test('copyWith keeps the blend lock unless told to clear it', () {
    final locked = const BrushShape().copyWith(
      lockedBlendMode: BrushBlendMode.multiply,
    );
    expect(locked.lockedBlendMode, BrushBlendMode.multiply);
    expect(locked.copyWith().lockedBlendMode, BrushBlendMode.multiply);
    expect(locked.copyWith(clearBlendLock: true).lockedBlendMode, isNull);
  });
}

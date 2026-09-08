// A BRUSH SHAPE SCATTERS ON BOTH AXES BY DEFAULT, AND A COPY KEEPS THE
// BLEND IT WAS MADE WITH.
//
// Two survivors of the mutation campaign (2026-09-03): the scatter default
// flipped to one axis, and copyWith's `clearBlendLock` default flipped to
// true — every copy then dropped the blend and nothing noticed. That flag
// is gone (the blend is a plain non-null field now, 유저 2026-09-08), but
// the hole it left is the same one: a copyWith that resets the blend to
// 通常 instead of carrying it. These pins cover both.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_shape.dart';

void main() {
  test('a fresh shape scatters on both axes', () {
    expect(const BrushShape().scatterBothAxes, isTrue);
    expect(const BrushShape().scatterCount, 1);
  });

  test('a fresh shape composites as 通常', () {
    expect(const BrushShape().blendMode, BrushBlendMode.color);
  });

  test('copyWith carries the blend through', () {
    final multiply = const BrushShape().copyWith(
      blendMode: BrushBlendMode.multiply,
    );
    expect(multiply.blendMode, BrushBlendMode.multiply);
    expect(multiply.copyWith().blendMode, BrushBlendMode.multiply);
    expect(multiply.copyWith(size: 12).blendMode, BrushBlendMode.multiply);
  });

  test('the blend participates in equality', () {
    expect(
      const BrushShape().copyWith(blendMode: BrushBlendMode.multiply),
      isNot(const BrushShape()),
    );
  });
}

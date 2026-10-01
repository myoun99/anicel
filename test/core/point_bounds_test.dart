import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/point_bounds.dart';

/// The one bounding box of a set of points — what the camera frame's
/// bounds, a selection's warp and coverage, a flood fill's tile and the
/// selection layer's view each spelled out for themselves.
void main() {
  test('the bounds of points are the smallest rect every one of them is in',
      () {
    expect(
      pointsBounds(const [Offset(3, 7), Offset(-2, 4), Offset(5, -1)]),
      const Rect.fromLTRB(-2, -1, 5, 7),
    );
  });

  test('one point bounds itself — a rect of no size at it', () {
    expect(pointsBounds(const [Offset(3, 7)]), const Rect.fromLTRB(3, 7, 3, 7));
  });

  test('no points: the empty rect turned inside out, which holds none', () {
    final none = pointsBounds(const []);
    expect(none.left, double.infinity);
    expect(none.top, double.infinity);
    expect(none.right, double.negativeInfinity);
    expect(none.bottom, double.negativeInfinity);
  });
}

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

/// The axis-aligned bounds of [points]: the smallest rect every one of them
/// is inside or on.
///
/// ⛔ONE loop for it. It was spelled five times — the camera frame's bounds
/// on the canvas, a selection warp's output rect, a selection's coverage,
/// a flood fill's tile preimage and the selection layer's visible canvas —
/// and five copies of a min and a max are five chances to take one for the
/// other (`one_algorithm_one_place_test`). No points gives the empty rect
/// turned inside out — left and top +∞, right and bottom −∞ — which holds
/// no point and grows to the first one.
Rect pointsBounds(Iterable<Offset> points) {
  var left = double.infinity;
  var top = double.infinity;
  var right = double.negativeInfinity;
  var bottom = double.negativeInfinity;
  for (final point in points) {
    left = math.min(left, point.dx);
    top = math.min(top, point.dy);
    right = math.max(right, point.dx);
    bottom = math.max(bottom, point.dy);
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

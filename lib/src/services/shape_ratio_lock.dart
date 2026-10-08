import 'dart:math' as math;

import '../models/canvas_point.dart';
import '../models/canvas_shape_kind.dart';

/// Where a shape dragged from [from] ends while its RATIO is kept, the hand
/// being at [to] — the shape tool's 「비율 고정」 (유저 답 I-69-Q5,
/// 2026-10-08: 정사각형 · 정원 · 45° 직선):
///
/// - a rectangle or an ellipse ends at the corner of the SQUARE whose side
///   is the longer of the two the hand has gone: it comes up to the hand
///   along that side and runs past it along the other, so the shape never
///   stops short of where the hand is;
/// - a line ends on the nearest of the eight ways 45° apart, at the point
///   of that way nearest the hand.
///
/// A shape that IS the hand's path — the lasso, the polygon — has no ratio
/// to keep, and ends where the hand is.
CanvasPoint ratioKeptEnd({
  required CanvasPoint from,
  required CanvasPoint to,
  required CanvasShapeKind shape,
}) {
  final dx = to.x - from.x;
  final dy = to.y - from.y;
  switch (shape) {
    case CanvasShapeKind.rect:
    case CanvasShapeKind.ellipse:
      final side = math.max(dx.abs(), dy.abs());
      return CanvasPoint(
        x: from.x + (dx < 0 ? -side : side),
        y: from.y + (dy < 0 ? -side : side),
      );
    case CanvasShapeKind.line:
      final way = _eightWays[(math.atan2(dy, dx) / (math.pi / 4)).round() & 7];
      final along = dx * way.x + dy * way.y;
      return CanvasPoint(x: from.x + along * way.x, y: from.y + along * way.y);
    case CanvasShapeKind.lasso:
    case CanvasShapeKind.polygon:
      return to;
  }
}

/// The eight ways a line with its ratio kept can go, from +x round through
/// +y — as exact steps, not as the sine and cosine of an angle: a level
/// line has no rise at all, and a diagonal's run and rise are one number.
const List<({double x, double y})> _eightWays = [
  (x: 1, y: 0),
  (x: math.sqrt1_2, y: math.sqrt1_2),
  (x: 0, y: 1),
  (x: -math.sqrt1_2, y: math.sqrt1_2),
  (x: -1, y: 0),
  (x: -math.sqrt1_2, y: -math.sqrt1_2),
  (x: 0, y: -1),
  (x: math.sqrt1_2, y: -math.sqrt1_2),
];

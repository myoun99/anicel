import 'dart:math' as math;

import '../models/canvas_point.dart';
import '../models/shape_tool_options.dart';
import 'canvas_selection_region.dart';
import 'canvas_selection_shape.dart';

/// The AREA a PLAIN line covers along a traced shape — the shape tool's
/// 「일반」 type (I-69).
///
/// 🚨★★★AN AREA, AND NOTHING OF A BRUSH. 🗣️유저 답 I-69-Q8 (2026-10-08):
/// 「일반은 브러시랑 전혀 관계없는 독립적인것임」. So nothing is stamped
/// along the path, whichever way its corners turn: the line is one region,
/// laid as one mask down the road a shape fill is laid by
/// (`buildRegionFillDab`), with that road's edge.
/// ↩️The card first described 「둥글게」 as a hard round brush drawn through
/// the stroke's code. That would have been the brush's engine under a type
/// that is not the brush's, its four-step edge under a switch that has two
/// answers, and a second road to keep beside this one.
///
/// What it covers is the box round every side — [width] across, and no
/// further along the side than its two ends — and what [corners] puts
/// where the sides meet and where the line ends:
///
/// - [ShapeCorners.sharp]: at every corner the piece that carries the two
///   boxes out to where their outer edges meet, and nothing at an end — a
///   rectangle's corners are corners, and a line is cut square AT its two
///   ends, as long as it was traced;
/// - [ShapeCorners.round]: a disc as wide as the line at every point —
///   corners and ends are rounded by half the width.
///
/// ⛔A UNION OF PIECES, not an outer outline minus an inner one. Pushing an
/// outline inwards by half the width turns it inside out wherever the line
/// is wider than the shape is there — the tips of a flat ellipse first —
/// and what is left to subtract is a knot. The pieces just cover the middle
/// between them, with nothing special said about it.
///
/// Null when there is nothing to cover: no width, or a path that goes
/// nowhere.
CanvasSelectionRegion? plainLineRegion({
  required List<CanvasPoint> points,
  required bool closed,
  required double width,
  required ShapeCorners corners,
}) {
  final path = _withoutRepeats(points, closed: closed);
  if (width <= 0 || path.length < 2) {
    return null;
  }
  final half = width / 2;
  final count = path.length;
  final pieces = <CanvasSelectionShape>[
    for (var i = 0; i < (closed ? count : count - 1); i += 1)
      _boxRound(path[i], path[(i + 1) % count], half),
    ...switch (corners) {
      // A corner is where two sides meet: every point of a closed outline,
      // and of an open path every point but its two ends.
      ShapeCorners.sharp => [
        for (var i = closed ? 0 : 1; i < (closed ? count : count - 1); i += 1)
          _sharpCorner(
            path[(i - 1 + count) % count],
            path[i],
            path[(i + 1) % count],
            half,
          ),
      ],
      ShapeCorners.round => [for (final point in path) _disc(point, half)],
    },
  ];
  return CanvasSelectionRegion([
    CanvasSelectionStep.copies(pieces, SelectionCombineMode.replace),
  ]);
}

/// How long a sharp corner may be — from its inside point to its outside
/// one — before it is cut flat instead, as a multiple of the line's width
/// (the miter limit).
///
/// ⚠️A bound, not a look: the outer edges of two sides that nearly double
/// back meet arbitrarily far away, and the mask is allocated out to where
/// they do. A rectangle's corner is 1.41 of the width and never comes near
/// it — but a row posed flat shows one as a sliver whose corners do.
/// 4 is the limit SVG, the HTML canvas and Flutter's own
/// `Paint.strokeMiterLimit` all start from; nothing here tuned it.
const double _sharpCornerLimit = 4;

/// [points] with no point that repeats the one before it — a side of no
/// length has no direction to lay a box along.
List<CanvasPoint> _withoutRepeats(
  List<CanvasPoint> points, {
  required bool closed,
}) {
  final kept = <CanvasPoint>[];
  for (final point in points) {
    if (kept.isEmpty || !_same(kept.last, point)) {
      kept.add(point);
    }
  }
  if (closed && kept.length > 1 && _same(kept.first, kept.last)) {
    kept.removeLast();
  }
  return kept;
}

bool _same(CanvasPoint a, CanvasPoint b) => a.x == b.x && a.y == b.y;

({double x, double y}) _unit(CanvasPoint from, CanvasPoint to) {
  final dx = to.x - from.x;
  final dy = to.y - from.y;
  final length = math.sqrt(dx * dx + dy * dy);
  return (x: dx / length, y: dy / length);
}

CanvasPoint _moved(CanvasPoint point, ({double x, double y}) by, double times) =>
    CanvasPoint(x: point.x + by.x * times, y: point.y + by.y * times);

/// The box round the side from [from] to [to]: [half] to either side of it,
/// and no further along it than its ends.
CanvasSelectionShape _boxRound(CanvasPoint from, CanvasPoint to, double half) {
  final along = _unit(from, to);
  final across = (x: -along.y, y: along.x);
  return CanvasSelectionShape([
    _moved(from, across, half),
    _moved(to, across, half),
    _moved(to, across, -half),
    _moved(from, across, -half),
  ]);
}

/// The disc [half] round [center] — by the one law an ellipse becomes
/// points ([CanvasSelectionShape.ellipse]), the shape tool's own ellipse
/// included.
CanvasSelectionShape _disc(CanvasPoint center, double half) =>
    CanvasSelectionShape.ellipse(
      left: center.x - half,
      top: center.y - half,
      right: center.x + half,
      bottom: center.y + half,
    );

/// What the two boxes that meet at [corner] leave open on the OUTSIDE of
/// the turn: from the corner out to each box's outer edge, and on to where
/// those two edges meet — or, where that makes the corner longer than
/// [_sharpCornerLimit] allows, straight across from one edge to the other.
///
/// Where the path does not turn, and where it doubles straight back, the
/// piece has no area: the two edges it runs between are one line there.
CanvasSelectionShape _sharpCorner(
  CanvasPoint before,
  CanvasPoint corner,
  CanvasPoint after,
  double half,
) {
  final into = _unit(before, corner);
  final outOf = _unit(corner, after);
  final turn = into.x * outOf.y - into.y * outOf.x;
  // The outside of a turn is the side it turns away from.
  final side = turn > 0 ? 1.0 : -1.0;
  final edgeBefore = (x: into.y * side, y: -into.x * side);
  final edgeAfter = (x: outOf.y * side, y: -outOf.x * side);
  // The two edges meet along the sum of their two ways out, and the
  // corner is then `sqrt(2 / spread)` widths long — compared squared.
  final spread = 1 + edgeBefore.x * edgeAfter.x + edgeBefore.y * edgeAfter.y;
  final meets = spread * _sharpCornerLimit * _sharpCornerLimit >= 2;
  return CanvasSelectionShape([
    corner,
    _moved(corner, edgeBefore, half),
    if (meets)
      _moved(
        corner,
        (
          x: (edgeBefore.x + edgeAfter.x) / spread,
          y: (edgeBefore.y + edgeAfter.y) / spread,
        ),
        half,
      ),
    _moved(corner, edgeAfter, half),
  ]);
}

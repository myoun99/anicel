import 'dart:math' as math;

import '../core/neighbour_pairs.dart';
import '../models/canvas_point.dart';
import 'input/pen_readings.dart';
import 'stroke_corners.dart';

/// Clip Studio's 後補正: once the line is drawn, its wobble is taken out
/// and it is laid again along a smooth curve (F-418, 유저 2026-10-20 Q5
/// 「선 다듬기 전부」 · Q7 「뗄 때 다듬은 선으로 바뀐다」 · 「다만 보정은
/// 중요하니까 다 만들자」).
///
/// [drawn] is the line as it was laid, [within] how far in canvas pixels a
/// wobble may stray and still be taken out. What it answers runs from
/// [drawn]'s first point to its last through the points that wobble left
/// standing: on a 2次ベジェ chain when [bezier] (Clip Studio's tips:
/// 「オンにすると、補正された曲線は2次ベジェになります」), otherwise on a
/// spline through them. Each point carries what the pen read at the same
/// share of the way along [drawn].
///
/// With [keepCorners] (角をとがらせる), the line is laid again in sections
/// that meet at its corners ([StrokeCorners]), each smoothed on its own — so
/// the smoothing goes into a corner and out of it, never round it.
///
/// ⚠️How Clip Studio takes the wobble out is not published; this is a
/// Douglas–Peucker pass at [within] — what is left of the line once every
/// bend smaller than that is straightened.
List<PenPoint> postCorrected(
  List<PenPoint> drawn, {
  required double within,
  required bool bezier,
  bool keepCorners = false,
}) {
  if (drawn.length < 3 || within <= 0) {
    return drawn;
  }
  final along = _distancesAlong(drawn);
  final ends = [
    0,
    if (keepCorners) ...StrokeCorners.of(drawn),
    drawn.length - 1,
  ];
  final pieces = <_Piece>[];
  for (final (from, to) in neighbourPairs(ends)) {
    final kept = _standing(drawn, within, from: from, to: to);
    final points = [for (final k in kept) drawn[k].position];
    final places = [for (final k in kept) along[k]];
    pieces.addAll(
      bezier ? _quadraticChain(points, places) : _spline(points, places),
    );
  }
  return [
    drawn.first,
    for (final piece in pieces)
      for (final (:position, :at) in _laid(piece))
        (position: position, readings: _readingsAt(drawn, along, at)),
  ];
}

/// The longest step a piece of the curve is laid in.
const double _stepSpan = 2;

/// How far along [line] each of its points stands.
List<double> _distancesAlong(List<PenPoint> line) {
  final along = [0.0];
  for (final (from, to) in neighbourPairs(line)) {
    along.add(along.last + from.position.distanceTo(to.position));
  }
  return along;
}

/// The indices of [line] from [from] to [to] that bends of [within] or less
/// leave standing — [from] and [to] always.
List<int> _standing(
  List<PenPoint> line,
  double within, {
  required int from,
  required int to,
}) {
  final stands = List<bool>.filled(line.length, false);
  stands[from] = true;
  stands[to] = true;
  final spans = [(from, to)];
  while (spans.isNotEmpty) {
    final (from, to) = spans.removeLast();
    var farthest = -1;
    var farthestBy = within;
    for (var i = from + 1; i < to; i += 1) {
      final by = line[i].position.distanceToSegment(
        line[from].position,
        line[to].position,
      );
      if (by > farthestBy) {
        farthest = i;
        farthestBy = by;
      }
    }
    if (farthest >= 0) {
      stands[farthest] = true;
      spans
        ..add((from, farthest))
        ..add((farthest, to));
    }
  }
  return [
    for (var i = from; i <= to; i += 1)
      if (stands[i]) i,
  ];
}

/// One piece of the curve: a Bézier on [controls], and where along the
/// drawn line its two ends stand — what its readings are read between.
typedef _Piece = ({List<CanvasPoint> controls, double fromAt, double toAt});

typedef _CurvePoint = ({CanvasPoint position, double at});

/// Midpoints of the standing [points] for ends, the points themselves for
/// controls — a quadratic chain that leaves the first point and reaches the
/// last; a straight piece when only those two stand.
List<_Piece> _quadraticChain(List<CanvasPoint> points, List<double> places) {
  final last = points.length - 1;
  if (last == 1) {
    return [(controls: points, fromAt: places[0], toAt: places[1])];
  }
  CanvasPoint endAt(int i) => i == 0
      ? points[0]
      : i == last - 1
      ? points[last]
      : CanvasPoint.lerp(points[i], points[i + 1], 0.5);
  double placeAt(int i) => i == 0
      ? places[0]
      : i == last - 1
      ? places[last]
      : (places[i] + places[i + 1]) / 2;
  return [
    for (var i = 1; i < last; i += 1)
      (
        controls: [endAt(i - 1), points[i], endAt(i)],
        fromAt: placeAt(i - 1),
        toAt: placeAt(i),
      ),
  ];
}

/// A Catmull–Rom spline through the standing [points], its ends mirrored so
/// the first and last pieces leave and arrive along the line — each piece
/// as the cubic Bézier it is, its controls a sixth of its neighbours' span
/// past its ends.
List<_Piece> _spline(List<CanvasPoint> points, List<double> places) {
  final last = points.length - 1;
  CanvasPoint pointAt(int i) => i < 0
      ? _mirrored(points[0], points[1])
      : i > last
      ? _mirrored(points[last], points[last - 1])
      : points[i];
  CanvasPoint past(CanvasPoint end, CanvasPoint from, CanvasPoint to) =>
      CanvasPoint(
        x: end.x + (to.x - from.x) / 6,
        y: end.y + (to.y - from.y) / 6,
      );
  return [
    for (var i = 0; i < last; i += 1)
      (
        controls: [
          points[i],
          past(points[i], pointAt(i - 1), points[i + 1]),
          past(points[i + 1], pointAt(i + 2), points[i]),
          points[i + 1],
        ],
        fromAt: places[i],
        toAt: places[i + 1],
      ),
  ];
}

CanvasPoint _mirrored(CanvasPoint end, CanvasPoint next) =>
    CanvasPoint(x: 2 * end.x - next.x, y: 2 * end.y - next.y);

/// [piece] laid in equal steps of its parameter, each no longer than
/// [_stepSpan]: a Bézier moves no faster than its degree times its longest
/// leg, so that many steps of that speed are short enough.
///
/// ⛔Not counted from the chord between its ends: a curve that bulges past
/// its chord was laid in steps longer than that.
List<_CurvePoint> _laid(_Piece piece) {
  final (:controls, :fromAt, :toAt) = piece;
  var longestLeg = 0.0;
  for (final (from, to) in neighbourPairs(controls)) {
    longestLeg = math.max(longestLeg, from.distanceTo(to));
  }
  final fastest = (controls.length - 1) * longestLeg;
  final steps = (fastest / _stepSpan).ceil().clamp(1, 1 << 16);
  return [
    for (var step = 1; step <= steps; step += 1)
      (
        position: _bezierAt(controls, step / steps),
        at: fromAt + (toAt - fromAt) * step / steps,
      ),
  ];
}

/// The Bézier on [controls] at [t], in its Bernstein form — which lands on
/// the last control exactly at 1, as the line's own end is.
CanvasPoint _bezierAt(List<CanvasPoint> controls, double t) {
  final degree = controls.length - 1;
  var x = 0.0;
  var y = 0.0;
  var ways = 1;
  for (var k = 0; k <= degree; k += 1) {
    final weight =
        (ways * math.pow(1 - t, degree - k) * math.pow(t, k)).toDouble();
    x += weight * controls[k].x;
    y += weight * controls[k].y;
    ways = ways * (degree - k) ~/ (k + 1);
  }
  return CanvasPoint(x: x, y: y);
}

/// What the pen read [at] that far along [line].
PenReadings _readingsAt(List<PenPoint> line, List<double> along, double at) {
  var low = 0;
  var high = line.length - 1;
  if (at >= along[high]) {
    return line[high].readings;
  }
  while (high - low > 1) {
    final middle = (low + high) >> 1;
    if (along[middle] <= at) {
      low = middle;
    } else {
      high = middle;
    }
  }
  final span = along[high] - along[low];
  return readingsBetween(
    line[low].readings,
    line[high].readings,
    span == 0 ? 0 : (at - along[low]) / span,
  );
}

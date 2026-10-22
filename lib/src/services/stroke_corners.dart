import 'dart:math' as math;

import '../models/canvas_point.dart';
import 'input/pen_readings.dart';

/// A corner of a line: where it stands in the line, and the point there.
typedef StrokeCorner = ({int at, PenPoint point});

/// Clip Studio's 角をとがらせる: where a line turns sharply, the turn is
/// kept a corner — the steadied line goes through it rather than across it
/// ([StrokeStabilizer]), and the 後補正 smooths the line either side of it
/// rather than round it ([postCorrected]) (F-418).
///
/// 🗣️유저 2026-10-20 (F-418-Q11): a V drawn at 100, on and off, with a mouse
/// and with a pen — on, it comes to a point; off, its bottom is rounded —
/// and Clip Studio's own 「オンにして角のある線を描画すると、角が鋭角に
/// なります」 over a square whose round corners come out square.
///
/// A point is in a turn where the line [_reach] behind it and [_reach]
/// ahead of it turn by [_sharpest] or more, and the corner of the turn is
/// its point that stands farthest off the line between those two — the
/// point of a V, and of a fold that comes straight back, where the turn
/// alone is the same all along it. A corner is known once the line has
/// gone past its turn.
///
/// ⚠️Both numbers are mine, to be matched by hand against Clip Studio: a
/// square's corner has to count, and a hand's wobble must not.
class StrokeCorners {
  /// How far either side of a point the way the line goes is read, in
  /// canvas pixels.
  static const double _reach = 8;

  /// The least turn that is a corner: 70°.
  static const double _sharpest = 70 * math.pi / 180;

  /// The line since its start or its last corner, and how far along it
  /// each point stands.
  final List<PenPoint> _points = [];
  final List<double> _along = [];

  /// Where [_points]' first stands in the whole line.
  int _first = 0;

  /// The next of [_points] to be read.
  int _next = 1;

  /// The point of the turn being read that stands farthest off, so far.
  ({int at, double off})? _turn;

  /// The corners of [line].
  static List<int> of(List<PenPoint> line) {
    final corners = StrokeCorners();
    return [
      for (final point in line)
        for (final corner in corners.add(point)) corner.at,
      for (final corner in corners.end()) corner.at,
    ];
  }

  /// The line goes on to [point]: answers the corners that this made known,
  /// in the order the line went through them.
  List<StrokeCorner> add(PenPoint point) {
    _along.add(
      _points.isEmpty
          ? 0
          : _along.last + _points.last.position.distanceTo(point.position),
    );
    _points.add(point);
    final found = <StrokeCorner>[];
    while (_next < _points.length - 1 &&
        _along[_next] + _reach <= _along.last) {
      final turn = _turn;
      final (:back, :ahead) = _wayAround(_next);
      final here = _points[_next].position;
      if (_turnAt(here, back, ahead) >= _sharpest) {
        final off = here.distanceToSegment(back, ahead);
        if (turn == null || off > turn.off) {
          _turn = (at: _next, off: off);
        }
        _next += 1;
      } else if (turn != null) {
        found.add(_cornerAt(turn.at));
      } else {
        _next += 1;
      }
    }
    return found;
  }

  /// The line ended: answers the corner of a turn it was still in, if it
  /// was.
  List<StrokeCorner> end() {
    final turn = _turn;
    return turn == null ? const [] : [_cornerAt(turn.at)];
  }

  /// Where the line stands [_reach] behind and ahead of [_points] [i] —
  /// its first point, when it does not reach that far back.
  ({CanvasPoint back, CanvasPoint ahead}) _wayAround(int i) => (
    back: _placeAt(math.max(0, _along[i] - _reach), from: i),
    ahead: _placeAt(_along[i] + _reach, from: i),
  );

  /// The place [along] the line, found from [_points] [from].
  CanvasPoint _placeAt(double along, {required int from}) {
    var i = from;
    while (i > 0 && _along[i] > along) {
      i -= 1;
    }
    while (i < _points.length - 1 && _along[i + 1] < along) {
      i += 1;
    }
    if (i == _points.length - 1) {
      return _points[i].position;
    }
    final span = _along[i + 1] - _along[i];
    return CanvasPoint.lerp(
      _points[i].position,
      _points[i + 1].position,
      span == 0 ? 0 : (along - _along[i]) / span,
    );
  }

  /// The corner at [_points] [i]: the line is read on from it.
  StrokeCorner _cornerAt(int i) {
    final corner = (at: _first + i, point: _points[i]);
    final from = _along[i];
    _points.removeRange(0, i);
    _along.removeRange(0, i);
    for (var k = 0; k < _along.length; k += 1) {
      _along[k] -= from;
    }
    _first += i;
    _next = 1;
    _turn = null;
    return corner;
  }
}

/// How far the way from [back] through [here] to [ahead] turns at [here],
/// in radians — none where either side has no length.
double _turnAt(CanvasPoint here, CanvasPoint back, CanvasPoint ahead) {
  final inX = here.x - back.x;
  final inY = here.y - back.y;
  final outX = ahead.x - here.x;
  final outY = ahead.y - here.y;
  final lengths =
      math.sqrt(inX * inX + inY * inY) * math.sqrt(outX * outX + outY * outY);
  if (lengths == 0) {
    return 0;
  }
  return math.acos(((inX * outX + inY * outY) / lengths).clamp(-1.0, 1.0));
}

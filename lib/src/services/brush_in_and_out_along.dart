import 'dart:math' as math;

import '../core/neighbour_pairs.dart';
import '../models/brush_dab.dart';
import '../models/brush_in_and_out.dart';
import '../models/canvas_point.dart';

/// One line's 入り抜き ([BrushInAndOut]) as it is laid: how far the line
/// has come, and so how thin and faint each dab laid on the way is.
///
/// ★The one place a line is measured for it — the pen's stroke, the stroke
/// a tool lays and the brush's swatch all go through here.
class BrushInAndOutAlong {
  BrushInAndOutAlong(this._inAndOut, {required CanvasPoint from, this.length})
    : _at = from;

  final BrushInAndOut _inAndOut;

  /// The whole line's length, where it is known before it is laid — a
  /// line laid again when the pen lifts, a tool's path, the swatch — and
  /// with it the 抜き. Null for a line still being drawn.
  final double? length;

  CanvasPoint _at;
  double _travelled = 0;

  /// The line goes on to [point].
  void goTo(CanvasPoint point) {
    _travelled += _at.distanceTo(point);
    _at = point;
  }

  /// [dabs], laid on the line on its way to where it is now ([goTo]), each
  /// as thin and as faint as its place along the line leaves it.
  ///
  /// A dab's place is how far the line has come less how far the dab lies
  /// behind where it is: every dab of a step lies on the way to it.
  List<BrushDab> taper(List<BrushDab> dabs) {
    if (!_inAndOut.comesIn && !(_inAndOut.goesOut && length != null)) {
      return dabs;
    }
    return [
      for (final dab in dabs)
        _inAndOut.taper(
          dab,
          _inAndOut.reachAt(
            math.max(0.0, _travelled - _at.distanceTo(dab.center)),
            length: length,
          ),
        ),
    ];
  }
}

/// How long the line through [points] is.
double lengthThrough(List<CanvasPoint> points) => neighbourPairs(
  points,
).fold(0.0, (length, pair) => length + pair.$1.distanceTo(pair.$2));

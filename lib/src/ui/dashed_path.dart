import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// HOW A LINE IS DASHED: [on] of line and then [off] of none, the pattern
/// slid [phase] back along the line.
class DashPattern {
  const DashPattern({required this.on, required this.off, this.phase = 0});

  final double on;
  final double off;

  /// How far the pattern has slid back along the line, for dashes that
  /// march: the first dash starts `-phase` on from a contour's start, taken
  /// into the pattern's own length.
  ///
  /// ⚠️What that leaves of a dash BEFORE the start is not drawn: a marching
  /// line opens each contour on a gap that closes as it marches. The ants
  /// always have, and a walk that drew that piece would change them.
  final double phase;

  /// One dash and the gap after it.
  double get period => on + off;

  /// Where the first dash starts along a contour: [phase] back from its
  /// start, taken into one [period].
  double get firstDashStart => -phase % period;

  /// Whether [distance] along a contour is on one of the dashes
  /// [dashesAlong] draws there, off the same start — what a press on a
  /// dashed line asks (F-262: 「보이는 만큼 존재하도록」).
  bool dashesAt(double distance) {
    final from = distance - firstDashStart;
    return from >= 0 && from % period <= on;
  }

  /// This pattern, slid [phase] back.
  DashPattern marchedBy(double phase) =>
      DashPattern(on: on, off: off, phase: phase);

  /// This pattern with every length [factor] times — the same dashes in
  /// another space's units: the ants' are cut in the canvas's, `1 / zoom`
  /// of the screen's, and moved to the screen whole ([dashedPolygons]).
  DashPattern scaledBy(double factor) =>
      DashPattern(on: on * factor, off: off * factor, phase: phase * factor);

  /// WHERE EACH DASH LIES along a contour [length] long, in order: [span]
  /// is told each one's start and end — from [firstDashStart] a [period]
  /// apart, [on] long, the last cut short where the contour ends.
  ///
  /// 🚨THE ONE ANSWER every walk cuts by ([dashesAlong], [dashedPolygons]):
  /// they differ in how a dash is cut out of a line, never in where it is.
  void spansAlong(
    double length,
    void Function(double start, double end) span,
  ) {
    for (var start = firstDashStart; start < length; start += period) {
      span(start, math.min(start + on, length));
    }
  }
}

/// 🚨★★★THE ANTS ARE BLACK — 유저 (F-65): 「선택툴의 개미행렬 색을 앱
/// 강조색이아니라 **검정색으로. 그러니 흰색바탕에 검정 개미가 지나가도록.
/// 앞으로 개미행렬은 이 공통 ui를 사용**」. The selection's march over the
/// white [paintDashedOutline] lays; a header graph's box (I-3 ⑤) stands
/// still in them.
///
/// ⚠️They read it as the app accent; it was actually
/// `AppColors.selectionSession`'s green (red while a move session holds
/// changes). Either way the instruction is the same, and the white
/// under-stroke this pairs with was already there — 「흰색바탕에 검정
/// 개미」 is that pair, now spelled the way they asked.
///
/// ⛔A constant, not a theme token: it must not follow the accent, and
/// following a THEME colour would be the same mistake one level up. The
/// white beneath it is `Colors.white` for the same reason.
const Color antsColour = Color(0xFF000000);

/// The ants' dashes ([antsColour]): five of line, four of none.
const DashPattern antsDashes = DashPattern(on: 5, off: 4);

/// THE DASHES OF A LINE: [source] walked contour by contour as [dashes]
/// says ([DashPattern.spansAlong]), each dash a path of its own.
///
/// 🚨ONE WALK. Three painters each walked a path this way by hand — the
/// selection's ants, the timeline's repeat span and its drop silhouette —
/// and the text tool's resting boxes would have been the fourth (R9-rest,
/// 2026-10-06; the same algorithm written apart is a copy, whatever its
/// text looks like). They differ in what they do WITH a dash — stroke each,
/// or gather them into one path — and in nothing about where a dash is, so
/// where a dash is, is what is here.
Iterable<Path> dashesAlong(Path source, DashPattern dashes) {
  final pieces = <Path>[];
  for (final metric in source.computeMetrics()) {
    dashes.spansAlong(
      metric.length,
      (start, end) => pieces.add(metric.extractPath(start, end)),
    );
  }
  return pieces;
}

/// THE DASHES OF AN OUTLINE OF STRAIGHT SIDES, laid into ONE path: each
/// closed polygon of [xy] — polygon `c` its points `starts[c]` up to
/// `starts[c + 1]`, a column and a line each — cut where [dashes] says
/// ([DashPattern.spansAlong]), the very dashes [dashesAlong] cuts from the
/// same polygons drawn as a path.
///
/// 🔬WHY A SECOND WAY TO CUT (card pixel-ants-cost-a-frame-while-moving,
/// 2026-11-16): the ants march, so their dashes are cut anew every tick,
/// and a 4K lasso's outline is twenty thousand pixel steps — [dashesAlong]
/// made a native path of each of its 3,155 dashes and copied it into one:
/// 2.65 ms a tick on the Surface (profile), standing or dragged. Walked
/// along the sides here and laid by `moveTo`/`lineTo`: 0.58. ⛔Not a
/// second answer to where a dash is — both read [DashPattern.spansAlong].
/// Only a line of straight sides can be cut this way; a curve (a rounded
/// box) still goes by [dashesAlong].
Path dashedPolygons(Uint32List starts, Int32List xy, DashPattern dashes) {
  final dashed = Path();
  for (var polygon = 0; polygon + 1 < starts.length; polygon += 1) {
    _Sides(xy, starts[polygon], starts[polygon + 1]).cut(dashed, dashes);
  }
  return dashed;
}

/// One closed polygon of [dashedPolygons]' points, walked a side at a time.
final class _Sides {
  _Sides(this._xy, this._first, int end) : _count = end - _first;

  final Int32List _xy;
  final int _first;
  final int _count;

  /// The side the walk is on — from point [_side] to the next —, where
  /// along the polygon it begins, and how long it is.
  int _side = 0;
  double _sideStart = 0;
  double _sideLength = 0;

  double _x(int point) => _xy[2 * (_first + point % _count)].toDouble();
  double _y(int point) => _xy[2 * (_first + point % _count) + 1].toDouble();

  double _lengthOf(int side) {
    final dx = _x(side + 1) - _x(side);
    final dy = _y(side + 1) - _y(side);
    return math.sqrt(dx * dx + dy * dy);
  }

  /// The polygon's dashes, laid into [dashed].
  void cut(Path dashed, DashPattern dashes) {
    if (_count < 2) {
      return;
    }
    var length = 0.0;
    for (var side = 0; side < _count; side += 1) {
      length += _lengthOf(side);
    }
    _sideLength = _lengthOf(0);
    dashes.spansAlong(length, (start, end) {
      _onTo(start);
      dashed.moveTo(_xAt(start), _yAt(start));
      while (_sideStart + _sideLength < end && _side < _count - 1) {
        dashed.lineTo(_x(_side + 1), _y(_side + 1));
        _next();
      }
      dashed.lineTo(_xAt(end), _yAt(end));
    });
  }

  /// Walks on to the side [distance] along the polygon lies on.
  void _onTo(double distance) {
    while (_sideStart + _sideLength < distance && _side < _count - 1) {
      _next();
    }
  }

  void _next() {
    _sideStart += _sideLength;
    _side += 1;
    _sideLength = _lengthOf(_side);
  }

  /// How far along the side the walk is on [distance] lies, 0 to 1.
  double _along(double distance) => _sideLength == 0
      ? 0
      : ((distance - _sideStart) / _sideLength).clamp(0.0, 1.0);

  double _xAt(double distance) =>
      _x(_side) + (_x(_side + 1) - _x(_side)) * _along(distance);

  double _yAt(double distance) =>
      _y(_side) + (_y(_side + 1) - _y(_side)) * _along(distance);
}

/// Draws [outline] as a dashed line that reads on ANY artwork: white along
/// the whole of it, and over that its [dashes] in [color].
///
/// 🗣️유저 (F-65): 「흰색바탕에 검정 개미가 지나가도록. **앞으로 개미행렬은 이
/// 공통 ui를 사용**」 — the white is what keeps the dashes readable on dark
/// artwork and the dashes what keep the white readable on light: the pair
/// is the line, not the dash alone. The selection's ants are this with
/// black dashes that march; a line that stands still has no phase.
void paintDashedOutline(
  Canvas canvas,
  Path outline, {
  required Color color,
  required DashPattern dashes,
}) {
  final dashed = Path();
  for (final dash in dashesAlong(outline, dashes)) {
    dashed.addPath(dash, Offset.zero);
  }
  paintCutOutline(canvas, outline, dashed, color: color);
}

/// [paintDashedOutline] of a line whose dashes are already cut ([dashed]) —
/// the ants' outline of pixels, cut by [dashedPolygons].
void paintCutOutline(
  Canvas canvas,
  Path outline,
  Path dashed, {
  required Color color,
}) {
  Paint stroke(Color color) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = color;
  canvas
    ..drawPath(outline, stroke(const Color(0xFFFFFFFF)))
    ..drawPath(dashed, stroke(color));
}

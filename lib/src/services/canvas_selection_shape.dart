import 'dart:math' as math;
import 'dart:ui' as ui;

import '../core/point_bounds.dart';
import '../models/canvas_point.dart';
import '../models/canvas_size.dart';
import '../models/pasteboard_bounds.dart';

/// A selection region in canvas coordinates (P9): a closed polygon — the
/// rectangle marquee is its 4-corner special case, the lasso is the
/// freehand path as drawn.
class CanvasSelectionShape {
  CanvasSelectionShape(List<CanvasPoint> points)
    : points = List<CanvasPoint>.unmodifiable(points),
      assert(points.length >= 3, 'a selection polygon needs 3+ points');

  factory CanvasSelectionShape.rect({
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) {
    final minX = math.min(left, right);
    final maxX = math.max(left, right);
    final minY = math.min(top, bottom);
    final maxY = math.max(top, bottom);
    return CanvasSelectionShape([
      CanvasPoint(x: minX, y: minY),
      CanvasPoint(x: maxX, y: minY),
      CanvasPoint(x: maxX, y: maxY),
      CanvasPoint(x: minX, y: maxY),
    ]);
  }

  /// 🚨THE WHOLE PICTURE — what a transform takes from a cel when nothing is
  /// selected (R26 #13: 「선택하지 않은 상황이어도 그림 전체를 이동」): the
  /// cel's tight INK bounds [content] (PS-style — the box frames the
  /// picture), the full canvas rect when there are none.
  ///
  /// ★ONE SHAPE PER CEL, AND EVERY CEL ASKS IT OF ITSELF. 🗣️유저 2026-09-24
  /// (H41): 「선택도구 사용했으면 어떤프레임이든 선택도구 안쪽만, 아니면 각자
  /// 그림 전체적용」 — the cel you stand on frames its own ink, and so does
  /// every other cel a range confirm lands on. Written once so the two
  /// cannot disagree about what 「the whole picture」 is.
  ///
  /// "The whole picture" means the whole PICTURE, pasteboard included. This
  /// used to clamp to the canvas rect, which was defended as "the same
  /// coverage the canvas-rect box had" — but the pasteboard is a first-class
  /// part of the drawing here, so a transform with nothing selected left the
  /// off-canvas ink standing still while the rest of the picture moved out
  /// from under it. The clamp stays, widened to the pasteboard: it is what
  /// keeps the box inside the finite wall every stage downstream (lift,
  /// resample, preview, commit) treats as the edge of the world.
  factory CanvasSelectionShape.wholePicture(
    CanvasSize canvasSize,
    ({int left, int top, int rightExclusive, int bottomExclusive})? content,
  ) {
    final width = canvasSize.width.toDouble();
    final height = canvasSize.height.toDouble();
    var left = 0.0;
    var top = 0.0;
    var right = width;
    var bottom = height;
    if (content != null) {
      final wallLeft = canvasSize.pasteboardLeft.toDouble();
      final wallTop = canvasSize.pasteboardTop.toDouble();
      final wallRight = canvasSize.pasteboardRightExclusive.toDouble();
      final wallBottom = canvasSize.pasteboardBottomExclusive.toDouble();
      left = content.left.toDouble().clamp(wallLeft, wallRight);
      top = content.top.toDouble().clamp(wallTop, wallBottom);
      right = content.rightExclusive.toDouble().clamp(wallLeft, wallRight);
      bottom = content.bottomExclusive.toDouble().clamp(wallTop, wallBottom);
      if (right <= left || bottom <= top) {
        left = 0;
        top = 0;
        right = width;
        bottom = height;
      }
    }
    return CanvasSelectionShape([
      CanvasPoint(x: left, y: top),
      CanvasPoint(x: right, y: top),
      CanvasPoint(x: right, y: bottom),
      CanvasPoint(x: left, y: bottom),
    ]);
  }

  /// The ellipse inscribed in the drag's box, as a polygon.
  ///
  /// A polygon because that is the only thing the region model knows how to
  /// be — membership is an even-odd ray cast and the mask is a scanline
  /// fill, and both of those are already exact for a polygon of any size.
  /// So the question is not "curve or polygon" but how many sides, and the
  /// answer comes from the RADIUS: [_ellipseSegments] picks the smallest
  /// count whose chord sags less than half a canvas pixel. A small ellipse
  /// gets a dozen sides and a huge one gets hundreds, and neither pays for
  /// the other.
  ///
  /// Segments are canvas-space, not screen-space, deliberately: the mask is
  /// rasterized in canvas space, so a zoomed-in view shows more of the same
  /// polygon rather than a smoother one. Anything else would make the
  /// committed pixels depend on the zoom they were committed at.
  factory CanvasSelectionShape.ellipse({
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) {
    final centerX = (left + right) / 2;
    final centerY = (top + bottom) / 2;
    final radiusX = (right - left).abs() / 2;
    final radiusY = (bottom - top).abs() / 2;
    final segments = _ellipseSegments(math.max(radiusX, radiusY));
    return CanvasSelectionShape([
      for (var i = 0; i < segments; i += 1)
        () {
          final angle = 2 * math.pi * i / segments;
          return CanvasPoint(
            x: centerX + radiusX * math.cos(angle),
            y: centerY + radiusY * math.sin(angle),
          );
        }(),
    ]);
  }

  /// Sides enough that the chord sags less than [_ellipseSagPx] from the
  /// true arc: for radius r and n sides the sag is `r · (1 − cos(π/n))`,
  /// solved for n. Clamped at both ends — the floor keeps a tiny ellipse
  /// from degenerating into a triangle, and the ceiling keeps a huge one
  /// from turning a selection into a point cloud.
  static int _ellipseSegments(double radius) {
    if (radius <= _ellipseSagPx) {
      return _ellipseMinSegments;
    }
    final exact = math.pi / math.acos(1 - _ellipseSagPx / radius);
    return exact.ceil().clamp(_ellipseMinSegments, _ellipseMaxSegments);
  }

  static const double _ellipseSagPx = 0.5;
  static const int _ellipseMinSegments = 12;
  static const int _ellipseMaxSegments = 512;

  final List<CanvasPoint> points;

  /// Whether the edge a–b crosses the horizontal line at [y].
  ///
  /// Strict `>` on both ends, so the convention is half-open: a vertex ON
  /// the line belongs to exactly one of the two edges that meet there and
  /// toggles the parity once. The ONE rule behind membership (the even-odd
  /// cast in [containsPoint]) and the lift mask's scanline fill — both
  /// walkers spelled it (the audit's clone scan, 2026-09-06). A static leaf
  /// so the per-edge loops keep no callback.
  static bool edgeStraddles(CanvasPoint a, CanvasPoint b, double y) =>
      (a.y > y) != (b.y > y);

  /// The x where the edge a–b meets the horizontal line at [y]. Only
  /// meaningful when [edgeStraddles] — the division is by the edge's rise.
  static double edgeCrossingX(CanvasPoint a, CanvasPoint b, double y) =>
      (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x;

  /// Even-odd ray cast (the polygon closes implicitly).
  bool containsPoint(CanvasPoint point) {
    var inside = false;
    for (var i = 0, j = points.length - 1; i < points.length; j = i, i += 1) {
      final a = points[i];
      final b = points[j];
      if (edgeStraddles(a, b, point.y) &&
          point.x < edgeCrossingX(a, b, point.y)) {
        inside = !inside;
      }
    }
    return inside;
  }

  CanvasSelectionShape translated({required double dx, required double dy}) {
    return CanvasSelectionShape([
      for (final point in points) CanvasPoint(x: point.x + dx, y: point.y + dy),
    ]);
  }

  /// This outline cut at [wall] — the pasteboard's edge, past which no
  /// selection may reach (I-23, 유저 2026-09-30: 「페이스트보드 밖도
  /// 선택가능하네? 해당부분 안으로만 가능하게 구조적으로 변경하면서 작업」).
  ///
  /// Sutherland–Hodgman: the outline is cut by each side of the wall in
  /// turn — ONE half-plane pass ([_cutBy]), asked of four sides. A point ON
  /// the wall is inside, and a crossing lands exactly on the wall line
  /// rather than a rounding error off it, so cutting again finds nothing to
  /// do. What the cut adds along the wall is a run ON the wall line, where
  /// no pixel centre lies, so the even-odd fill of the result is the old
  /// fill inside the wall — a lasso that crosses itself included.
  ///
  /// This shape itself when every point is already inside; null when too
  /// little is left to enclose anything.
  CanvasSelectionShape? clippedTo(ui.Rect wall) {
    final sides = _sidesOf(wall);
    if (points.every((point) => sides.every((side) => _keeps(side, point)))) {
      return this;
    }
    var kept = points;
    for (final side in sides) {
      kept = _cutBy(side, kept);
      if (kept.length < 3) {
        return null;
      }
    }
    final box = pointsBounds([
      for (final point in kept) ui.Offset(point.x, point.y),
    ]);
    if (box.width <= 0 || box.height <= 0) {
      return null;
    }
    return CanvasSelectionShape(kept);
  }

  /// Value equality (R28-S: the composite region compares step by step,
  /// and the ants painter's [CustomPainter.shouldRepaint] rides on it).
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! CanvasSelectionShape ||
        other.points.length != points.length) {
      return false;
    }
    for (var i = 0; i < points.length; i += 1) {
      if (other.points[i] != points[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(points);
}

/// One side of a wall, as a half-plane: a point is kept when
/// `sign · (c − bound) ≤ 0`, where `c` is its x if [bindsX] and its y
/// otherwise — the line itself included.
typedef _WallSide = ({bool bindsX, double bound, double sign});

/// [wall]'s four sides.
List<_WallSide> _sidesOf(ui.Rect wall) => [
  (bindsX: true, bound: wall.left, sign: -1.0),
  (bindsX: true, bound: wall.right, sign: 1.0),
  (bindsX: false, bound: wall.top, sign: -1.0),
  (bindsX: false, bound: wall.bottom, sign: 1.0),
];

/// [point]'s coordinate across [side]'s line.
double _across(_WallSide side, CanvasPoint point) =>
    side.bindsX ? point.x : point.y;

bool _keeps(_WallSide side, CanvasPoint point) =>
    side.sign * (_across(side, point) - side.bound) <= 0;

/// Sutherland–Hodgman's one pass: [points] cut by [side].
List<CanvasPoint> _cutBy(_WallSide side, List<CanvasPoint> points) {
  final kept = <CanvasPoint>[];
  var previous = points.last;
  for (final current in points) {
    final inside = _keeps(side, current);
    if (inside != _keeps(side, previous)) {
      kept.add(_crossing(side, previous, current));
    }
    if (inside) {
      kept.add(current);
    }
    previous = current;
  }
  return kept;
}

/// Where the edge [a]–[b] meets [side]'s line — ON it: the coordinate
/// across the line is the bound itself, never a quotient that lands a
/// rounding error to either side.
CanvasPoint _crossing(_WallSide side, CanvasPoint a, CanvasPoint b) {
  final t =
      (side.bound - _across(side, a)) / (_across(side, b) - _across(side, a));
  return side.bindsX
      ? CanvasPoint(x: side.bound, y: a.y + (b.y - a.y) * t)
      : CanvasPoint(x: a.x + (b.x - a.x) * t, y: side.bound);
}

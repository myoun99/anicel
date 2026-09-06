import 'dart:math' as math;

import '../models/canvas_point.dart';

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

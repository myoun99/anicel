import 'dart:math' as math;
import 'dart:typed_data' show Float64List;
import 'dart:ui' show Offset;

/// One coordinate of a cubic Bézier at [u] (0..1): the Bernstein cubic over
/// [c0], [c1], [c2] and [c3].
///
/// ⛔ONE polynomial for it. A key's ease through time (`segmentProgress`),
/// a TVPaint camera's profile and path (`tvpp_camera_bake.dart`) and a
/// position lane's path in space (I-89 ④) each evaluate it, and it was
/// spelled out twice before the third came.
double cubicAt(double u, double c0, double c1, double c2, double c3) {
  final v = 1 - u;
  return v * v * v * c0 +
      3 * v * v * u * c1 +
      3 * v * u * u * c2 +
      u * u * u * c3;
}

/// The point [s] of the WAY along the cubic Bézier from [from] to [to]
/// through the controls [leaving] and [arriving] ([CubicWalk.at]).
Offset alongCubic(
  Offset from,
  Offset leaving,
  Offset arriving,
  Offset to,
  double s,
) => CubicWalk(from, leaving, arriving, to).at(s);

/// The cubic Bézier from [from] to [to] through the controls [leaving] and
/// [arriving], walked by distance: its length is measured once, and [at]
/// reads it for every point asked along it — a position's trail asks for
/// hundreds along one segment (I-89 ④).
///
/// Progress is a fraction of distance travelled, so a curved segment is
/// walked by arc length; with its controls on its ends the path is a
/// straight line and this is a plain lerp (feeding the fraction in as the
/// curve's parameter would add a phantom ease on top of the one the keys
/// give). ↩️It was the TVPaint camera's own (`_alongPath`), and a position
/// lane walks a path in space the same way (I-89 ④).
final class CubicWalk {
  CubicWalk(this.from, this.leaving, this.arriving, this.to)
    : _lengths = leaving == from && arriving == to
          ? null
          : _lengthsAlong(from, leaving, arriving, to);

  final Offset from;
  final Offset leaving;
  final Offset arriving;
  final Offset to;

  /// How far along the curve each of its [_steps] + 1 even steps of the
  /// curve's parameter stands — null for the straight line, which has no
  /// need of them.
  final Float64List? _lengths;

  static const int _steps = 256;

  static Float64List _lengthsAlong(
    Offset from,
    Offset leaving,
    Offset arriving,
    Offset to,
  ) {
    final lengths = Float64List(_steps + 1);
    var before = from;
    for (var k = 1; k <= _steps; k++) {
      final point = _curve(from, leaving, arriving, to, k / _steps);
      final dx = point.dx - before.dx;
      final dy = point.dy - before.dy;
      lengths[k] = lengths[k - 1] + math.sqrt(dx * dx + dy * dy);
      before = point;
    }
    return lengths;
  }

  static Offset _curve(
    Offset from,
    Offset leaving,
    Offset arriving,
    Offset to,
    double u,
  ) => Offset(
    cubicAt(u, from.dx, leaving.dx, arriving.dx, to.dx),
    cubicAt(u, from.dy, leaving.dy, arriving.dy, to.dy),
  );

  /// The point [s] of the way along it.
  Offset at(double s) {
    final lengths = _lengths;
    if (lengths == null) {
      return Offset(
        from.dx + (to.dx - from.dx) * s,
        from.dy + (to.dy - from.dy) * s,
      );
    }
    final target = s * lengths[_steps];
    var lo = 0;
    var hi = _steps;
    while (lo + 1 < hi) {
      final mid = (lo + hi) ~/ 2;
      if (lengths[mid] < target) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final segment = lengths[hi] - lengths[lo];
    final f = segment <= 0 ? 0.0 : (target - lengths[lo]) / segment;
    final a = _curve(from, leaving, arriving, to, lo / _steps);
    final b = _curve(from, leaving, arriving, to, hi / _steps);
    return Offset(a.dx + (b.dx - a.dx) * f, a.dy + (b.dy - a.dy) * f);
  }
}

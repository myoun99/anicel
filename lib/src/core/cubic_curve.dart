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
  CubicWalk(this.from, this.leaving, this.arriving, this.to);

  final Offset from;
  final Offset leaving;
  final Offset arriving;
  final Offset to;

  /// How far along the curve each of its [_steps] + 1 even steps of the
  /// curve's parameter stands, measured when the first point is asked —
  /// null for the straight line, which has no need of them.
  late final Float64List? _lengths = leaving == from && arriving == to
      ? null
      : _lengthsAlong();

  static const int _steps = 256;

  /// How long the walk is — what a run of several walks shares its way out
  /// by (a roving key's, I-89 ④).
  double get length => _lengths?[_steps] ?? (to - from).distance;

  Float64List _lengthsAlong() {
    final lengths = Float64List(_steps + 1);
    var before = from;
    for (var k = 1; k <= _steps; k++) {
      final point = _curve(k / _steps);
      final dx = point.dx - before.dx;
      final dy = point.dy - before.dy;
      lengths[k] = lengths[k - 1] + math.sqrt(dx * dx + dy * dy);
      before = point;
    }
    return lengths;
  }

  /// The curve at its parameter [u].
  Offset _curve(double u) => Offset(
    cubicAt(u, from.dx, leaving.dx, arriving.dx, to.dx),
    cubicAt(u, from.dy, leaving.dy, arriving.dy, to.dy),
  );

  /// The point [s] of the way along it.
  Offset at(double s) {
    if (_lengths == null) {
      return Offset(
        from.dx + (to.dx - from.dx) * s,
        from.dy + (to.dy - from.dy) * s,
      );
    }
    final (:lo, :f) = _stepAt(s);
    final a = _curve(lo / _steps);
    final b = _curve((lo + 1) / _steps);
    return Offset(a.dx + (b.dx - a.dx) * f, a.dy + (b.dy - a.dy) * f);
  }

  /// The curve's parameter at the point [s] of the way along it ([at]) —
  /// [s] itself for the straight line, whose parameter is its way.
  double parameterAt(double s) {
    if (_lengths == null) {
      return s;
    }
    final (:lo, :f) = _stepAt(s);
    return (lo + f) / _steps;
  }

  /// The even step of the parameter the point [s] of the way falls in, and
  /// how far into it.
  ({int lo, double f}) _stepAt(double s) {
    final lengths = _lengths!;
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
    return (lo: lo, f: segment <= 0 ? 0.0 : (target - lengths[lo]) / segment);
  }
}

/// The cubic Bézier [p0] · [p1] · [p2] · [p3] cut at its parameter [u]
/// (de Casteljau): the controls of the half before the cut — [p0],
/// [before].$1, [before].$2, [at] — and of the half after it — [at],
/// [after].$1, [after].$2, [p3]. Each half is the curve it was there, so a
/// key cut into a way leaves the way's two halves as they were (I-120-Q3).
({(Offset, Offset) before, Offset at, (Offset, Offset) after}) cubicCut(
  Offset p0,
  Offset p1,
  Offset p2,
  Offset p3,
  double u,
) {
  Offset lerp(Offset a, Offset b) => a + (b - a) * u;
  final a1 = lerp(p0, p1);
  final b1 = lerp(p1, p2);
  final c1 = lerp(p2, p3);
  final a2 = lerp(a1, b1);
  final b2 = lerp(b1, c1);
  return (before: (a1, a2), at: lerp(a2, b2), after: (b2, c1));
}

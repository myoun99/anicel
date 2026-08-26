import 'dart:math' as math;

import 'tvp_import_model.dart';
import 'tvpp_parse.dart';

/// Bakes a .tvpp camera's authored keys into per-frame poses — the
/// `positions` array TVPaint's JSON export ships ready-made and the
/// project file does not.
///
/// What the file gives per key (`mpoints-N-…`): position (x, y), spatial
/// bezier handles (`bezierafter` on the outgoing key, `bezierbefore` on
/// the incoming one, as OFFSETS from each point), rotation, zoomfactor,
/// and `instant` (the key's 0-based frame). Each key also carries a
/// `positionprofile` — an easing curve of (x=time, y=progress) points in
/// 0..1.
///
/// Three rules pinned against TVPaint's own bake (SKK 18_58's JSON
/// export, 26 moving-frame samples — see
/// `tvpp_camera_oracle_check.dart`):
///
/// * **The segment's easing lives on its DESTINATION key.** The first
///   key's profile is the editor default; the authored curve sits on
///   `mpoints-1` for the segment 0→1.
/// * **Profile handles are fractions of the segment they ease**: a
///   stored offset multiplies the segment's Δx / Δy (raw offsets were
///   141px wrong on the oracle; per-axis Δ-scaling is the only reading
///   inside ~1% — the ±0.25 the editor writes means "a quarter of the
///   segment").
/// * **A key's pose is reached one frame AFTER its instant** — the
///   instant marks the END of that frame's exposure, so a segment
///   a→b runs t = (frame − a) / (b − a + 1) and the camera rests from
///   frame b+1 on. The oracle sits at 99.7% on the key's own frame.
///
/// TVPaint's evaluator still differs from this piecewise bezier by up to
/// ~1% of the travel mid-segment (residual grows toward each interior
/// profile point, so its true evaluator likely re-spaces the x axis
/// slightly). The oracle check pins the ceiling; a second differential
/// export would be needed to close the last percent.
List<TvpCameraPose> bakeTvppCamera(
  List<TvppCameraPoint> points,
  List<TvppCameraProfile> profiles, {
  required int frameCount,
}) {
  if (points.isEmpty || frameCount <= 0) {
    return const [];
  }
  final poses = <TvpCameraPose>[];
  for (var frame = 0; frame < frameCount; frame++) {
    poses.add(_poseAt(points, profiles, frame));
  }
  return poses;
}

/// One key's easing curve, from `mpoints-N-positionprofile-*`. Applies
/// to the segment ARRIVING at that key.
class TvppCameraProfile {
  const TvppCameraProfile({required this.points});

  /// (x=time, y=progress) control points in 0..1 with bezier handle
  /// offsets, sorted by x. Empty or degenerate = linear. The file pads
  /// the list with copies of (1, 1); they form zero-width segments the
  /// evaluation never enters.
  final List<TvppCameraProfilePoint> points;

  /// Progress at normalized time [t] (0..1): piecewise cubic bezier
  /// through the control points, handle offsets scaled by the segment's
  /// Δx/Δy. Solved for x by bisection — monotone x in every file
  /// measured.
  double progressAt(double t) {
    if (points.length < 2) {
      return t;
    }
    if (t <= 0) {
      return points.first.y;
    }
    if (t >= 1) {
      return points.last.y;
    }
    var i = 0;
    while (i + 2 < points.length && points[i + 1].x <= t) {
      i++;
    }
    final a = points[i];
    final b = points[i + 1];
    if (b.x <= a.x) {
      return b.y;
    }
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final p0x = a.x, p0y = a.y;
    final p1x = a.x + a.bezierAfterX * dx, p1y = a.y + a.bezierAfterY * dy;
    final p2x = b.x + b.bezierBeforeX * dx, p2y = b.y + b.bezierBeforeY * dy;
    final p3x = b.x, p3y = b.y;

    var lo = 0.0, hi = 1.0;
    for (var step = 0; step < 32; step++) {
      final mid = (lo + hi) / 2;
      if (_bez(mid, p0x, p1x, p2x, p3x) < t) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final u = (lo + hi) / 2;
    return _bez(u, p0y, p1y, p2y, p3y);
  }
}

double _bez(double u, double c0, double c1, double c2, double c3) {
  final v = 1 - u;
  return v * v * v * c0 + 3 * v * v * u * c1 + 3 * v * u * u * c2 + u * u * u * c3;
}

class TvppCameraProfilePoint {
  const TvppCameraProfilePoint({
    required this.x,
    required this.y,
    required this.bezierBeforeX,
    required this.bezierBeforeY,
    required this.bezierAfterX,
    required this.bezierAfterY,
  });

  final double x;
  final double y;
  final double bezierBeforeX;
  final double bezierBeforeY;
  final double bezierAfterX;
  final double bezierAfterY;
}

/// Parses every key's `positionprofile` from the raw `[cameradata]` text
/// (kept on [TvppClip.cameraDataText]); index N pairs with camera point N.
List<TvppCameraProfile> parseTvppCameraProfiles(String cameraDataText) {
  if (cameraDataText.isEmpty) {
    return const [];
  }
  final values = <String, String>{};
  for (final line in cameraDataText.split('\n')) {
    final eq = line.indexOf('=');
    if (eq > 0) {
      values[line.substring(0, eq).trim()] = line.substring(eq + 1).trim();
    }
  }
  double num(String key) => double.tryParse(values[key] ?? '') ?? 0;
  final profiles = <TvppCameraProfile>[];
  for (var n = 0; values.containsKey('mpoints-$n-x'); n++) {
    final pts = <TvppCameraProfilePoint>[];
    for (var m = 0;
        values.containsKey('mpoints-$n-positionprofile-point-$m-x');
        m++) {
      pts.add(
        TvppCameraProfilePoint(
          x: num('mpoints-$n-positionprofile-point-$m-x'),
          y: num('mpoints-$n-positionprofile-point-$m-y'),
          bezierBeforeX: num('mpoints-$n-positionprofile-point-$m-bezierbeforex'),
          bezierBeforeY: num('mpoints-$n-positionprofile-point-$m-bezierbeforey'),
          bezierAfterX: num('mpoints-$n-positionprofile-point-$m-bezierafterx'),
          bezierAfterY: num('mpoints-$n-positionprofile-point-$m-bezieraftery'),
        ),
      );
    }
    pts.sort((a, b) => a.x.compareTo(b.x));
    profiles.add(TvppCameraProfile(points: pts));
  }
  return profiles;
}

TvpCameraPose _poseAt(
  List<TvppCameraPoint> points,
  List<TvppCameraProfile> profiles,
  int frame,
) {
  TvpCameraPose pose(TvppCameraPoint p) => TvpCameraPose(
        frame: frame + 1,
        x: p.x,
        y: p.y,
        angleDegrees: p.rotationDegrees,
        scale: p.zoomFactor,
        sizeX: p.sizeX,
        sizeY: p.sizeY,
      );

  if (frame <= points.first.instant) {
    return pose(points.first);
  }
  // The last key's pose is reached one frame past its instant.
  if (frame > points.last.instant) {
    return pose(points.last);
  }
  // Segment a→b claims frames a.instant < f <= b.instant.
  var i = 0;
  while (i + 2 < points.length && points[i + 1].instant < frame) {
    i++;
  }
  final a = points[i];
  final b = points[i + 1];
  final span = b.instant - a.instant + 1;
  final t = (frame - a.instant) / span;
  final eased = i + 1 < profiles.length ? profiles[i + 1].progressAt(t) : t;

  final (x, y) = _alongPath(a, b, eased);
  double lerp(double p, double q) => p + (q - p) * eased;
  return TvpCameraPose(
    frame: frame + 1,
    x: x,
    y: y,
    angleDegrees: lerp(a.rotationDegrees, b.rotationDegrees),
    scale: lerp(a.zoomFactor, b.zoomFactor),
    sizeX: lerp(a.sizeX, b.sizeX),
    sizeY: lerp(a.sizeY, b.sizeY),
  );
}

/// The point [eased] of the WAY along the spatial curve from [a] to [b].
///
/// Progress is a fraction of distance travelled, so the spatial bezier is
/// walked by arc length — feeding the eased fraction straight in as the
/// bezier parameter would add a phantom ease-in/out on top of the
/// profile (with zero handles the curve is a straight line, but the
/// parameter still crawls at the ends; the oracle shows plain lerp).
(double, double) _alongPath(TvppCameraPoint a, TvppCameraPoint b, double s) {
  final straight = a.bezierAfterX == 0 &&
      a.bezierAfterY == 0 &&
      b.bezierBeforeX == 0 &&
      b.bezierBeforeY == 0;
  if (straight) {
    return (a.x + (b.x - a.x) * s, a.y + (b.y - a.y) * s);
  }
  const steps = 256;
  final xs = List<double>.filled(steps + 1, 0);
  final ys = List<double>.filled(steps + 1, 0);
  final lens = List<double>.filled(steps + 1, 0);
  for (var k = 0; k <= steps; k++) {
    final u = k / steps;
    xs[k] = _bez(u, a.x, a.x + a.bezierAfterX, b.x + b.bezierBeforeX, b.x);
    ys[k] = _bez(u, a.y, a.y + a.bezierAfterY, b.y + b.bezierBeforeY, b.y);
    if (k > 0) {
      final dx = xs[k] - xs[k - 1];
      final dy = ys[k] - ys[k - 1];
      lens[k] = lens[k - 1] + _hypot(dx, dy);
    }
  }
  final target = s * lens[steps];
  var lo = 0, hi = steps;
  while (lo + 1 < hi) {
    final mid = (lo + hi) ~/ 2;
    if (lens[mid] < target) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  final segment = lens[hi] - lens[lo];
  final f = segment <= 0 ? 0.0 : (target - lens[lo]) / segment;
  return (xs[lo] + (xs[hi] - xs[lo]) * f, ys[lo] + (ys[hi] - ys[lo]) * f);
}

double _hypot(double dx, double dy) => math.sqrt(dx * dx + dy * dy);

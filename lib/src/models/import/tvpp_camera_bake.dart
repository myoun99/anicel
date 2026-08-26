import 'tvp_import_model.dart';
import 'tvpp_parse.dart';

/// Bakes a .tvpp camera's authored keys into per-frame poses — the
/// `positions` array TVPaint's JSON export ships ready-made and the
/// project file does not.
///
/// What the file gives per key (`mpoints-N-…`): position (x, y), spatial
/// bezier handles (`bezierafter` on the outgoing key, `bezierbefore` on
/// the incoming one, as OFFSETS from each point), rotation, zoomfactor,
/// and `instant` (the key's frame). Each key also carries a
/// `positionprofile` — an easing curve of (x=time, y=progress) points in
/// 0..1 with their own handles — applied to the segment it opens.
///
/// ⚠️Verified only structurally so far: KLM's single-key camera matches
/// its JSON bake exactly (a constant pose), and SKK's two-key pan parses,
/// but no moving-camera bake oracle exists yet. The evaluation below is
/// the straight reading of the fields; hands-on comparison against
/// TVPaint's own playback is the outstanding check.
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

/// One segment's easing curve, from `mpoints-N-positionprofile-*`.
class TvppCameraProfile {
  const TvppCameraProfile({required this.points});

  /// (x=time, y=progress) control points in 0..1 with bezier handle
  /// offsets, sorted by x. Empty or degenerate = linear.
  final List<TvppCameraProfilePoint> points;

  /// Progress at normalized time [t] (0..1): piecewise cubic bezier
  /// through the control points, monotone x assumed. Solved for x by
  /// bisection — the handles are small and well-behaved in every file
  /// measured, and 20 steps land within 1e-6.
  double progressAt(double t) {
    if (points.length < 2) {
      return t;
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
    // Cubic bezier in (x, y): P0=a, P1=a+after, P2=b+before, P3=b.
    final p0x = a.x, p0y = a.y;
    final p1x = a.x + a.bezierAfterX, p1y = a.y + a.bezierAfterY;
    final p2x = b.x + b.bezierBeforeX, p2y = b.y + b.bezierBeforeY;
    final p3x = b.x, p3y = b.y;
    double bez(double u, double c0, double c1, double c2, double c3) {
      final v = 1 - u;
      return v * v * v * c0 + 3 * v * v * u * c1 + 3 * v * u * u * c2 + u * u * u * c3;
    }

    var lo = 0.0, hi = 1.0;
    for (var step = 0; step < 24; step++) {
      final mid = (lo + hi) / 2;
      if (bez(mid, p0x, p1x, p2x, p3x) < t) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final u = (lo + hi) / 2;
    return bez(u, p0y, p1y, p2y, p3y);
  }
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
  if (frame >= points.last.instant) {
    return pose(points.last);
  }
  var i = 0;
  while (i + 2 < points.length && points[i + 1].instant <= frame) {
    i++;
  }
  final a = points[i];
  final b = points[i + 1];
  final span = b.instant - a.instant;
  if (span <= 0) {
    return pose(b);
  }
  final t = (frame - a.instant) / span;
  final eased =
      i < profiles.length ? profiles[i].progressAt(t) : t;

  // Spatial cubic bezier between the two keys; handles are offsets.
  double bez(double u, double c0, double c1, double c2, double c3) {
    final v = 1 - u;
    return v * v * v * c0 + 3 * v * v * u * c1 + 3 * v * u * u * c2 + u * u * u * c3;
  }

  final x = bez(eased, a.x, a.x + a.bezierAfterX, b.x + b.bezierBeforeX, b.x);
  final y = bez(eased, a.y, a.y + a.bezierAfterY, b.y + b.bezierBeforeY, b.y);
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

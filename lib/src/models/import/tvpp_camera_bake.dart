import 'dart:ui' show Offset;

import '../../core/cubic_curve.dart';
import 'tvp_import_model.dart';
import 'tvpp_key_value_lines.dart';
import 'tvpp_parse.dart';

/// Bakes a .tvpp camera's authored keys into per-frame poses — the
/// `positions` array TVPaint's JSON export ships ready-made and the
/// project file does not.
///
/// The model was solved against EIGHT of TVPaint's own bakes (SKK plus
/// the seven PROFILE_CAL differential exports of 2026-08-26; oracle
/// runner: `tvpp_camera_oracle_check.dart`):
///
/// * **One global time warp for the whole path.** With L = the span from
///   the first key's instant to the last key's, frame k maps to path
///   time p = k·L/(L+1); keys sit at their nominal instants on the p
///   axis. The +1 belongs to the PATH, not to each segment — proven by
///   the 3-key files, where the mid-key pose is passed BETWEEN frames
///   and the last frame of the clip never quite reaches the end key
///   (untouched file: frame 49 sits at 48/49 of the pan).
/// * **Channels are independent tracks.** Position, rotation, zoom and
///   size each interpolate between THEIR OWN keys — the mpoints whose
///   `flags` carry that channel's bit (observed: 1 = position-only,
///   15 = all channels; bit order position/rotation/zoom/size is the
///   listing order, extrapolated beyond those two observed values). In
///   the calibration file a rotation keyed only at frame 41 animates
///   straight through the position keys from the path start.
/// * **A segment eases by its DESTINATION key's per-channel profile**,
///   cubic bezier through the stored points with handle offsets applied
///   RAW (a zero handle keeps the control at its anchor), solved for x
///   by bisection and the resulting progress CLAMPED to [0, 1] — the
///   calibration curve overshoots 1 mid-segment and TVPaint's own bake
///   flatlines there. Control-point recovery from the bake returned the
///   stored handle (+0.250, +0.250) to three decimals.
///
/// A profile's `mode` is the graph's カーブタイプ — see
/// [TvppCameraProfile.mode] for the 線形/スプライン split and the one
/// remaining outlier (SKK). Everything else lands at TVPaint's own
/// solver noise.
List<TvpCameraPose> bakeTvppCamera(
  List<TvppCameraPoint> points,
  TvppCameraChannels channels, {
  required int frameCount,
}) {
  if (points.isEmpty || frameCount <= 0) {
    return const [];
  }
  final first = points.first.instant;
  final nominal = points.last.instant - first;
  final poses = <TvpCameraPose>[];
  for (var frame = 0; frame < frameCount; frame++) {
    final p = nominal <= 0 ? 0.0 : (frame - first) * nominal / (nominal + 1);
    final (x, y) = _positionAt(points, channels, p);
    poses.add(
      TvpCameraPose(
        frame: frame + 1,
        x: x,
        y: y,
        angleDegrees: _scalarAt(
          points,
          channels,
          p,
          _rotationBit,
          channels.rotation,
          (pt) => pt.rotationDegrees,
        ),
        scale: _scalarAt(
          points,
          channels,
          p,
          _zoomBit,
          channels.zoom,
          (pt) => pt.zoomFactor,
        ),
        sizeX: _scalarAt(
          points,
          channels,
          p,
          _sizeBit,
          channels.size,
          (pt) => pt.sizeX,
        ),
        sizeY: _scalarAt(
          points,
          channels,
          p,
          _sizeBit,
          channels.size,
          (pt) => pt.sizeY,
        ),
      ),
    );
  }
  return poses;
}

/// Which channels a key authors, from `mpoints-N-flags` (observed 1 and
/// 15; the per-channel bits beyond "position" follow the file's channel
/// listing order — a decision, not a measurement).
const int _positionBit = 1;
const int _rotationBit = 2;
const int _zoomBit = 4;
const int _sizeBit = 8;

/// The per-key easing curves of all four channels, parsed from the raw
/// `[cameradata]` text; index N pairs with camera point N.
class TvppCameraChannels {
  const TvppCameraChannels({
    required this.position,
    required this.rotation,
    required this.zoom,
    required this.size,
  });

  final List<TvppCameraProfile> position;
  final List<TvppCameraProfile> rotation;
  final List<TvppCameraProfile> zoom;
  final List<TvppCameraProfile> size;

  static const TvppCameraChannels none = TvppCameraChannels(
    position: [],
    rotation: [],
    zoom: [],
    size: [],
  );
}

/// One key's easing curve. Applies to the segment ARRIVING at that key.
class TvppCameraProfile {
  const TvppCameraProfile({required this.points, this.mode = 4});

  /// The stored `…profile-mode` — the graph's カーブタイプ: 1 = 線形
  /// (a polyline through the points; the stored handles are ignored),
  /// 4 = スプライン (the raw-handle bezier). Both types materialize the
  /// auto-smooth handles into the file, so only this flag separates the
  /// two — pinned by the 6/7 calibration pair, which share their points
  /// AND handles verbatim and bake differently.
  ///
  /// ⚠️One outlier remains: SKK's 2026-05 file stores mode=1 yet bakes
  /// SMOOTH (locally exceeding an interior point — impossible for a
  /// polyline). The polyline reading lands within ~1% of that pan; its
  /// oracle pins the ceiling.
  final int mode;

  /// (x=time, y=progress) control points in 0..1 with bezier handle
  /// offsets, sorted by x. Empty or degenerate = linear. Files pad the
  /// list with copies of (1, 1); they form zero-width segments the
  /// evaluation never enters.
  final List<TvppCameraProfilePoint> points;

  /// Progress at normalized time [t] (0..1): piecewise cubic bezier
  /// through the control points, handle offsets RAW (zero handle =
  /// control at its anchor), solved for x by bisection, progress clamped
  /// to [0, 1].
  double progressAt(double t) {
    if (points.length < 2) {
      return t.clamp(0.0, 1.0);
    }
    if (t <= 0) {
      return points.first.y.clamp(0.0, 1.0);
    }
    if (t >= 1) {
      return points.last.y.clamp(0.0, 1.0);
    }
    var i = 0;
    while (i + 2 < points.length && points[i + 1].x <= t) {
      i++;
    }
    final a = points[i];
    final b = points[i + 1];
    if (b.x <= a.x) {
      return b.y.clamp(0.0, 1.0);
    }
    if (mode == 1) {
      // 線形: a polyline through the points, stored handles ignored —
      // both curve types materialize the auto-smooth handles into the
      // file, and the type alone picks the evaluator (6_multipoint_line
      // vs 7_multipoint_spline share their handles verbatim).
      final f = (t - a.x) / (b.x - a.x);
      return (a.y + (b.y - a.y) * f).clamp(0.0, 1.0);
    }
    final p1x = a.x + a.bezierAfterX;
    final p1y = a.y + a.bezierAfterY;
    final p2x = b.x + b.bezierBeforeX;
    final p2y = b.y + b.bezierBeforeY;

    var lo = 0.0;
    var hi = 1.0;
    for (var step = 0; step < 32; step++) {
      final mid = (lo + hi) / 2;
      if (cubicAt(mid, a.x, p1x, p2x, b.x) < t) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final u = (lo + hi) / 2;
    return cubicAt(u, a.y, p1y, p2y, b.y).clamp(0.0, 1.0);
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

/// Parses every key's four channel profiles from the raw `[cameradata]`
/// text (kept on [TvppClip.cameraDataText]).
TvppCameraChannels parseTvppCameraProfiles(String cameraDataText) {
  if (cameraDataText.isEmpty) {
    return TvppCameraChannels.none;
  }
  final values = tvppKeyValueLines(cameraDataText);
  double num(String key) => double.tryParse(values[key] ?? '') ?? 0;
  List<TvppCameraProfile> channel(String name) {
    final profiles = <TvppCameraProfile>[];
    for (var n = 0; values.containsKey('mpoints-$n-x'); n++) {
      final pts = <TvppCameraProfilePoint>[];
      for (
        var m = 0;
        values.containsKey('mpoints-$n-${name}profile-point-$m-x');
        m++
      ) {
        final k = 'mpoints-$n-${name}profile-point-$m';
        pts.add(
          TvppCameraProfilePoint(
            x: num('$k-x'),
            y: num('$k-y'),
            bezierBeforeX: num('$k-bezierbeforex'),
            bezierBeforeY: num('$k-bezierbeforey'),
            bezierAfterX: num('$k-bezierafterx'),
            bezierAfterY: num('$k-bezieraftery'),
          ),
        );
      }
      pts.sort((a, b) => a.x.compareTo(b.x));
      profiles.add(
        TvppCameraProfile(
          points: pts,
          mode: num('mpoints-$n-${name}profile-mode').round(),
        ),
      );
    }
    return profiles;
  }

  return TvppCameraChannels(
    position: channel('position'),
    rotation: channel('rotation'),
    zoom: channel('zoom'),
    size: channel('size'),
  );
}

/// The indices of [points] that key [bit]'s channel. A channel nobody
/// keys falls back to the first point, which every file authors fully
/// (flags 15).
List<int> _keyedIndices(List<TvppCameraPoint> points, int bit) {
  final keyed = <int>[
    for (var i = 0; i < points.length; i++)
      if (points[i].flags & bit != 0) i,
  ];
  return keyed.isEmpty ? const [0] : keyed;
}

/// Finds the segment of [keyed] covering path time [p] and returns the
/// eased fraction plus the two point indices. Null when [p] sits before
/// the first key or past the last (caller holds the edge value).
(int, int, double)? _segmentAt(
  List<TvppCameraPoint> points,
  List<int> keyed,
  List<TvppCameraProfile> profiles,
  double p,
) {
  final first = points.first.instant;
  if (keyed.length < 2) {
    return null;
  }
  final start = points[keyed.first].instant - first;
  final end = points[keyed.last].instant - first;
  if (p <= start || p >= end) {
    return null;
  }
  var s = 0;
  while (s + 2 < keyed.length && points[keyed[s + 1]].instant - first <= p) {
    s++;
  }
  final ai = keyed[s];
  final bi = keyed[s + 1];
  final a = points[ai].instant - first;
  final b = points[bi].instant - first;
  if (b <= a) {
    return null;
  }
  final t = (p - a) / (b - a);
  final eased = bi < profiles.length
      ? profiles[bi].progressAt(t)
      : t.clamp(0.0, 1.0);
  return (ai, bi, eased);
}

(double, double) _positionAt(
  List<TvppCameraPoint> points,
  TvppCameraChannels channels,
  double p,
) {
  final keyed = _keyedIndices(points, _positionBit);
  final segment = _segmentAt(points, keyed, channels.position, p);
  if (segment == null) {
    final at = _edgeHoldAt(points, keyed, p);
    return (at.x, at.y);
  }
  final (ai, bi, eased) = segment;
  return _alongPath(points[ai], points[bi], eased);
}

/// The keyed point that holds outside the keyed span: before the first key
/// the first keyed point holds, past the last the last holds.
TvppCameraPoint _edgeHoldAt(
  List<TvppCameraPoint> points,
  List<int> keyed,
  double p,
) => p <= points[keyed.first].instant - points.first.instant
    ? points[keyed.first]
    : points[keyed.last];

double _scalarAt(
  List<TvppCameraPoint> points,
  TvppCameraChannels channels,
  double p,
  int bit,
  List<TvppCameraProfile> profiles,
  double Function(TvppCameraPoint) read,
) {
  final keyed = _keyedIndices(points, bit);
  final segment = _segmentAt(points, keyed, profiles, p);
  if (segment == null) {
    return read(_edgeHoldAt(points, keyed, p));
  }
  final (ai, bi, eased) = segment;
  final a = read(points[ai]);
  return a + (read(points[bi]) - a) * eased;
}

/// The point [s] of the WAY along the spatial curve from [a] to [b], each
/// key's handle reaching out of it ([CubicWalk]).
(double, double) _alongPath(TvppCameraPoint a, TvppCameraPoint b, double s) {
  final at = CubicWalk(
    Offset(a.x, a.y),
    Offset(a.x + a.bezierAfterX, a.y + a.bezierAfterY),
    Offset(b.x + b.bezierBeforeX, b.y + b.bezierBeforeY),
    Offset(b.x, b.y),
  ).at(s);
  return (at.dx, at.dy);
}

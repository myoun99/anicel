import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../../core/cubic_curve.dart';
import '../../models/camera_pose.dart';
import '../../models/canvas_point.dart';
import '../../models/cut_camera.dart';
import '../../models/property_track.dart';
import '../../models/transform_track.dart';
import '../layer_pose_matrix.dart' show LayerPoseSample;

/// How far a way between two keys may play from the pose the file shows on
/// a frame before another key stands between them — a canvas pixel (유저
/// 10-13, `camera-import-keeps-the-files-eases-Q3`: 「1px 까지 허용」), on
/// a 2000px-ish canvas: position and an anchor are already in canvas
/// pixels; a 4e-4 zoom error moves a 2000px span by 0.8px, and 0.04° swings
/// a 1000px radius by 0.7px. ↩️A quarter pixel (1e-4, 0.01°) until then:
/// a key or two more on a curved TVPaint profile.
const double _pointTolerance = 1;
const double _scaleTolerance = 4e-4;
const double _rotationTolerance = 0.04;

/// How much nearer the file than a straight way an ease must play a way
/// that both play, in the lane's tolerance, to be the way: a hundredth — a
/// hundredth of a pixel, about as near as the import knows a file's look
/// (TVPaint's own bake against the decode's: 0.003 to 0.006px on the
/// calibration files' straight ramps, `tvpp_camera_oracle_check`). Any
/// nearer brought a straight bake in eased: a calibration file's straight
/// ramp with a point added on it, straight 0.00013px off and the ease
/// 0.00002px.
const double _nearerBy = 1 / 100;

/// The frames a transform's lanes are keyed on, each its own — as After
/// Effects keys them apart and as the files an import reads key them
/// (I-89 ⑦).
typedef TransformKeyFrames = ({
  Iterable<int> anchorPoint,
  Iterable<int> position,
  Iterable<int> scale,
  Iterable<int> rotation,
});

/// The camera that plays [byFrame] — a pose on every frame, the move as the
/// file shows it — in keys the way the app keys a camera (I-89 ⑦, 유저
/// 10-10: 「TVPaint 의 채널별 속도 곡선 · 경로 베지어, 클튜의 좌우 기울기를
/// 새 모델로 옮긴다 — 매 프레임 굽기 대신」): each lane its own keys, on the
/// frames the file keys that lane on ([keyedOn]) and where its move starts
/// and stops, and each way between two of them held, straight or one AE
/// ease ([EaseSide] on both of its ends) — the ease where it plays the
/// file's nearer than a straight way does, by more than the import knows
/// the file ([_nearerBy]). Where one way does not play the file's move
/// within a pixel, a key stands where it stops doing so, and the way goes
/// on from there.
///
/// ⚠️What the file SHOWS is the truth, not its keys' values (measured on
/// TVPaint's own bakes — `planTvpCamera`): a key carries the pose on its
/// frame, and the keys a way needs beside the file's are the price of
/// looking as it looked — the save law 「겉모습이 먼저다」(유저 10-07:
/// 「최대한 보기 같은걸 원한다」). 🗣️A file's ease that one AE ease does not
/// carry within the pixel above comes in as more keys, each way between
/// them eased — not as the one nearest ease (유저 10-13,
/// `camera-import-keeps-the-files-eases-Q3`: 「1px 까지 허용」 over 「원본
/// 키만」).
///
/// A hold at either end needs no key of its own — the app holds the first
/// key before it and the last after it — so a move is keyed where it starts
/// and stops, and a lane that never moves and that the file keys nowhere is
/// ONE key, where it starts (288, hands-on: one key on frame 1 arrived as
/// keys on 1 and 96; s6's pan, keyed on frames 0 and 108, arrived with a
/// third on its last frame). The TVPaint import makes its cut's camera
/// here; the CLIP STUDIO import each 2D camera folder's transform
/// ([transformTrackOfFramePoses]) — one fit.
CutCamera cutCameraOfFramePoses(
  SplayTreeMap<int, CameraPose> byFrame, {
  required CameraKeyFrames keyedOn,
}) => CutCamera.fromTrack(
  transformTrackOfFramePoses(
    {
      // The one zoom on both of the scale's numbers (`CutCamera`).
      for (final MapEntry(key: frame, value: pose) in byFrame.entries)
        frame: (pose: TransformPose.ofCamera(pose), anchorPoint: null),
    },
    keyedOn: (
      anchorPoint: const [],
      position: keyedOn.position,
      scale: keyedOn.zoom,
      rotation: keyedOn.rotation,
    ),
  ),
);

/// The transform that plays [byFrame] — a pose and its anchor on every
/// frame given, the move as the file shows it — in keys, each lane its own
/// as [cutCameraOfFramePoses] lays a camera's; empty for no frame. A frame
/// with no anchor stands its pose on the canvas's centre
/// (`layerPoseMatrix`) — the lane keyed nowhere — so none of them has one,
/// or every one does. A frame not given is one the file shows nothing on
/// (a 2D camera folder between its clips): no way is fitted to it, and the
/// keys either side join over it.
TransformTrack transformTrackOfFramePoses(
  Map<int, LayerPoseSample> byFrame, {
  required TransformKeyFrames keyedOn,
}) {
  if (byFrame.isEmpty) {
    return TransformTrack.empty();
  }
  final frames = (byFrame.keys.toList()..sort());
  final samples = [for (final frame in frames) byFrame[frame]!];
  final anchors = [for (final sample in samples) sample.anchorPoint];
  assert(
    anchors.every((anchor) => anchor == null) ||
        anchors.every((anchor) => anchor != null),
    'Some frames of a transform have an anchor and some do not.',
  );
  return TransformTrack.properties(
    anchorPoint: anchors.first == null
        ? PropertyTrack.empty()
        : _LaneKeys(
            frames,
            anchors.nonNulls.toList(),
            _anchorLane,
          ).keyedOn(keyedOn.anchorPoint),
    position: _LaneKeys(
      frames,
      [for (final sample in samples) sample.pose.center],
      _positionLane,
    ).keyedOn(keyedOn.position),
    scale: _LaneKeys(
      frames,
      [for (final sample in samples) sample.pose.scale],
      _scaleLane,
    ).keyedOn(keyedOn.scale),
    rotation: _LaneKeys(
      frames,
      [for (final sample in samples) sample.pose.rotationDegrees],
      _rotationLane,
    ).keyedOn(keyedOn.rotation),
    opacity: PropertyTrack.empty(),
  );
}

/// What fitting one of a transform's lanes takes: the space the app plays
/// its values in, how far a played value is from the file's, how far it
/// may be on a frame before another key stands, and — for a lane whose
/// keys walk a path — the ways that bend as the file's path does
/// ([bentWays]).
final class _TransformLane<T> {
  const _TransformLane(
    this.space,
    this.miss,
    this.tolerance, {
    this.bentWays,
  });

  final KeyValueSpace<T> space;
  final double Function(T played, T shown) miss;
  final double tolerance;

  /// The ways from the value at one index of the file's values to the
  /// value at another that bend nearest the ones between, on their frames
  /// ([_bentWays]) — null on a lane whose keys walk no path.
  final List<_Way> Function(
    List<T> values,
    List<int> frames,
    int from,
    int to,
  )?
  bentWays;

  /// Whether a way whose farthest frame misses the file by [worst] plays
  /// it — the tolerance is as far as it may be.
  bool plays(double worst) => worst <= tolerance;
}

/// How far [played] is from [shown] on the axis it is the farther on.
double _pointMiss(CanvasPoint played, CanvasPoint shown) => math.max(
  (played.x - shown.x).abs(),
  (played.y - shown.y).abs(),
);

const _anchorLane = _TransformLane<CanvasPoint>(
  pathKeySpace,
  _pointMiss,
  _pointTolerance,
  bentWays: _bentWays,
);

const _positionLane = _TransformLane<CanvasPoint>(
  pathKeySpace,
  _pointMiss,
  _pointTolerance,
  bentWays: _bentWays,
);

const _scaleLane = _TransformLane<CanvasPoint>(
  pointKeySpace,
  _pointMiss,
  _scaleTolerance,
);

final _rotationLane = _TransformLane<double>(
  doubleKeySpace,
  (played, shown) => (played - shown).abs(),
  _rotationTolerance,
);

/// How a way between two keys goes: the side it leaves the one by and the
/// side it reaches the other by ([PropertyKey.outgoing] · `incoming`), and
/// the path it bends along between them — none where it runs straight.
typedef _Way = ({KeyExit leaving, KeySide arriving, _Bend? bend});

const _Way _straight = (
  leaving: KeySide.linear,
  arriving: KeySide.linear,
  bend: null,
);

/// The value held from the key on, AE's Hold — what CLIP STUDIO's
/// `Constant` plays.
const _Way _held = (leaving: KeyExit.hold, arriving: KeySide.linear, bend: null);

/// A handle that reaches nowhere: the side of a key a bent way does not
/// leave or reach it by.
final _noReach = CanvasPoint(x: 0, y: 0);

/// One lane's keys, fitted to [values] — the file's value on each of
/// [frames], in order.
final class _LaneKeys<T> {
  _LaneKeys(this.frames, this.values, this.lane);

  final List<int> frames;
  final List<T> values;
  final _TransformLane<T> lane;

  /// The index of each key, the sides the ways either side give it, and
  /// the handles a bent way leaves it by ([_ahead]) or reaches it by.
  final _stops = SplayTreeSet<int>();
  final _leaving = <int, KeyExit>{};
  final _arriving = <int, KeySide>{};
  final _ahead = <int, CanvasPoint>{};
  final _behind = <int, CanvasPoint>{};

  /// The lane keyed on those of [keyed] that are [frames], and on the ends
  /// of its move where none of them comes before it starts or after it
  /// stops, with every key more its ways need between them. A key of the
  /// file's before the move holds until it ([_held] — the fit finds where
  /// it starts), so the move's start is a key only where nothing of the
  /// file's is: a hold the file keys stays the one key it keyed.
  PropertyTrack<T> keyedOn(Iterable<int> keyed) {
    final indexOf = {
      for (final (index, frame) in frames.indexed) frame: index,
    };
    final kept = SplayTreeSet<int>.of([
      for (final frame in keyed) ?indexOf[frame],
    ]);
    if (_moveEnds() case (final start, final end)) {
      if (kept.isEmpty || kept.first > start) {
        kept.add(start);
      }
      if (kept.last < end) {
        kept.add(end);
      }
    }
    if (kept.isEmpty) {
      kept.add(0);
    }
    _stops.add(kept.first);
    var from = kept.first;
    for (final to in kept.skip(1)) {
      _fill(from, to);
      from = to;
    }
    return PropertyTrack(
      keys: {
        for (final index in _stops)
          frames[index]: PropertyKey(
            values[index],
            incoming: _arriving[index] ?? KeySide.linear,
            outgoing: _leaving[index] ?? KeySide.linear,
            path: _pathOf(index),
          ),
      },
    );
  }

  /// The path through the key at [index]: the handles its bent ways leave
  /// and reach it by, each side its own ([SplitPath]) — a corner where
  /// neither way bends.
  KeyPath _pathOf(int index) {
    final ahead = _ahead[index];
    final behind = _behind[index];
    if (ahead == null && behind == null) {
      return KeyPath.straight;
    }
    return SplitPath(ahead: ahead ?? _noReach, behind: behind ?? _noReach);
  }

  /// The last index of the hold the lane opens with and the first of the
  /// one it closes with — null when it never moves.
  (int, int)? _moveEnds() {
    var start = 0;
    while (start + 1 < values.length && values[start + 1] == values.first) {
      start += 1;
    }
    if (start == values.length - 1) {
      return null;
    }
    var end = values.length - 1;
    while (values[end - 1] == values.last) {
      end -= 1;
    }
    return (start, end);
  }

  /// Lays the ways from index [from] to [to]: one, where one plays it;
  /// else the longest one from [from] that plays as far as it goes, and on
  /// from there. A way to the next index always plays — there is no frame
  /// between to miss.
  void _fill(int from, int to) {
    var at = from;
    while (at < to) {
      final whole = _wayBetween(at, to);
      if (whole != null) {
        _lay(at, to, whole);
        return;
      }
      var reach = at + 1;
      var carried = _straight;
      var short = to;
      while (short - reach > 1) {
        final middle = (reach + short) ~/ 2;
        final way = _wayBetween(at, middle);
        if (way == null) {
          short = middle;
        } else {
          reach = middle;
          carried = way;
        }
      }
      _lay(at, reach, carried);
      at = reach;
    }
  }

  void _lay(int from, int to, _Way way) {
    _stops
      ..add(from)
      ..add(to);
    _leaving[from] = way.leaving;
    _arriving[to] = way.arriving;
    if (way.bend case final bend?) {
      _ahead[from] = bend.ahead;
      _behind[to] = bend.behind;
    }
  }

  /// The one way from index [from] to [to] that plays every frame between
  /// as the file shows it — held, or straight or eased along a straight
  /// path or a bent one — or null when none does. The plainest of those
  /// that play, unless one less plain plays the file nearer by more than
  /// [_nearerBy] of the lane's tolerance: the tolerance says where another
  /// key must stand, not how the way between two keys bends.
  /// ↩️Until 10-13 straight was taken wherever it played — a rule no one
  /// gave: at a pixel, CLIP STUDIO's own slow-out slow-in came in straight
  /// up to ten pixels long (the user's zoom-and-turn sample: 3px of it,
  /// 0.29px off where one ease plays it exactly).
  ///
  /// 🗣️A WAY BENDS AS THE FILE'S PATH DOES (card
  /// `tvp-camera-keys-only-where-needed`, 유저 2026-11-17: 「원본tvp에비해서
  /// 카메라키가 너무 많은데 … 필요한 키만으로 구현할수있지않나」). ↩️Till
  /// then every way ran straight between its keys, so a path TVPaint's
  /// handles bend came in as a key wherever the line left it by a pixel —
  /// blu's pan, keyed on five frames, came in on forty-nine.
  _Way? _wayBetween(int from, int to) {
    if (to - from < 2) {
      return _straight;
    }
    final start = values[from];
    if (start != values[to] &&
        values.getRange(from + 1, to).every((value) => value == start)) {
      return _held;
    }
    final ways = [
      _straight,
      ?_easedWay(from, to),
      ...?lane.bentWays?.call(values, frames, from, to),
    ];
    final misses = [for (final way in ways) _worstMiss(from, to, way)];
    final nearest = misses.reduce(math.min);
    for (final (index, way) in ways.indexed) {
      if (lane.plays(misses[index]) &&
          misses[index] - nearest <= lane.tolerance * _nearerBy) {
        return way;
      }
    }
    return null;
  }

  /// How far [way] from index [from] to [to] plays from the file on the
  /// frame between where it is the farthest — read the way the app plays a
  /// lane ([PropertyTrack.resolveAt]), so what is measured is what is seen.
  double _worstMiss(int from, int to, _Way way) {
    final bend = way.bend;
    final track = PropertyTrack<T>(
      keys: {
        frames[from]: PropertyKey(
          values[from],
          outgoing: way.leaving,
          path: bend == null
              ? KeyPath.straight
              : SplitPath(ahead: bend.ahead, behind: _noReach),
        ),
        frames[to]: PropertyKey(
          values[to],
          incoming: way.arriving,
          path: bend == null
              ? KeyPath.straight
              : SplitPath(ahead: _noReach, behind: bend.behind),
        ),
      },
    );
    var worst = 0.0;
    for (var index = from + 1; index < to; index += 1) {
      final played = track.resolveAt(
        frameIndex: frames[index],
        orElse: () => values[index],
        space: lane.space,
      );
      worst = math.max(worst, lane.miss(played, values[index]));
    }
    return worst;
  }

  /// The AE ease nearest the way the file takes from index [from] to [to]
  /// ([_NearestEase]): how far along from the one key's value to the
  /// other's each frame between stands ([KeyValueSpace.inverseLerp]),
  /// against the share of the time gone. Null when the way goes nowhere —
  /// two keys of one value, which no ease bends.
  _Way? _easedWay(int from, int to) {
    final start = values[from];
    final end = values[to];
    if (start == end) {
      return null;
    }
    final span = frames[to] - frames[from];
    final (leaving, arriving) = _NearestEase(
      times: [
        for (var index = from + 1; index < to; index += 1)
          (frames[index] - frames[from]) / span,
      ],
      shares: [
        for (var index = from + 1; index < to; index += 1)
          lane.space.inverseLerp(start, end, values[index]),
      ],
    ).sides();
    return (leaving: leaving, arriving: arriving, bend: null);
  }
}
/// A bent way's handles: how far, and which way, the one ahead of the key
/// it leaves and the one behind the key it reaches reach out of them
/// ([SplitPath]).
typedef _Bend = ({CanvasPoint ahead, CanvasPoint behind});

/// How many times [_nearestCurve] reads each value's parameter on the
/// curve again and fits the curve to them — only where [_bentWays]' own
/// fit starts from.
const int _bendRounds = 8;

/// The ways a path may bend from [values]' [from] to its [to] — at an even
/// pace, and eased — each the handles, and the pace, whose play comes
/// nearest the values between on their [frames], by least squares
/// ([_LeastSquares]): played as the app plays a lane that walks a path,
/// [segmentProgress] along a [CubicWalk], from the curve nearest the values
/// in space ([_nearestCurve]). None where no curve is read.
List<_Way> _bentWays(
  List<CanvasPoint> values,
  List<int> frames,
  int from,
  int to,
) {
  final curve = _nearestCurve(values, from, to);
  if (curve == null) {
    return const [];
  }
  final start = _offsetOf(values[from]);
  final end = _offsetOf(values[to]);
  final span = frames[to] - frames[from];
  final times = [
    for (var index = from + 1; index < to; index += 1)
      (frames[index] - frames[from]) / span,
  ];
  List<double> missesOf(List<double> numbers) {
    final walk = CubicWalk(
      start,
      start + Offset(numbers[0], numbers[1]),
      end + Offset(numbers[2], numbers[3]),
      end,
    );
    final misses = <double>[];
    for (final (index, time) in times.indexed) {
      final progress = numbers.length == 4
          ? time
          : segmentProgress(
              time,
              leaving: (influence: numbers[4], speed: numbers[5]),
              arriving: (influence: numbers[6], speed: numbers[7]),
            );
      final miss = walk.at(progress) - _offsetOf(values[from + 1 + index]);
      misses
        ..add(miss.dx)
        ..add(miss.dy);
    }
    return misses;
  }

  final handles = [
    curve.leaving.dx - start.dx,
    curve.leaving.dy - start.dy,
    curve.arriving.dx - end.dx,
    curve.arriving.dy - end.dy,
  ];
  final even = _LeastSquares(
    missesOf,
    _finiteNumbers,
  ).nearestFrom(handles).numbers;
  final (leaving, arriving) = _NearestEase(
    times: times,
    shares: curve.shares,
  ).sides();
  final eased = _LeastSquares(missesOf, _handlesAndPaceWithinReach)
      .nearestFrom([
        ...handles,
        leaving.influence,
        leaving.speed,
        arriving.influence,
        arriving.speed,
      ])
      .numbers;
  return [
    (leaving: KeySide.linear, arriving: KeySide.linear, bend: _bendOf(even)),
    (
      leaving: EaseSide(influence: eased[4], speed: eased[5]),
      arriving: EaseSide(influence: eased[6], speed: eased[7]),
      bend: _bendOf(eased),
    ),
  ];
}

/// The handles the first four of [numbers] say ([_bentWays]).
_Bend _bendOf(List<double> numbers) => (
  ahead: CanvasPoint(x: numbers[0], y: numbers[1]),
  behind: CanvasPoint(x: numbers[2], y: numbers[3]),
);

/// [numbers], where every one of them is a number.
List<double>? _finiteNumbers(List<double> numbers) =>
    numbers.every((value) => value.isFinite) ? numbers : null;

/// A bent way's four handle numbers and its pace, the pace's influences
/// kept within what a side may take ([_withinReach]).
List<double>? _handlesAndPaceWithinReach(List<double> numbers) {
  final handles = _finiteNumbers(numbers.sublist(0, 4));
  final pace = _withinReach(numbers.sublist(4));
  return handles == null || pace == null ? null : [...handles, ...pace];
}

/// The cubic from [values]' [from] to its [to] — the way's two keys — that
/// passes nearest the values between in space, by least squares: its two
/// inner controls fitted to each value's parameter on it, read first as
/// how far along the line through them the value stands and then, again,
/// as the parameter of the curve's point nearest it (Newton) — Schneider's
/// fit of a digitized curve — and how far along it, as a share of its
/// length, each value stands. Null where fewer than two values stand
/// between, which two controls cannot be read from, or where every value
/// stands at one point.
({Offset leaving, Offset arriving, List<double> shares})? _nearestCurve(
  List<CanvasPoint> values,
  int from,
  int to,
) {
  if (to - from < 3) {
    return null;
  }
  final start = _offsetOf(values[from]);
  final end = _offsetOf(values[to]);
  final between = [
    for (var index = from + 1; index < to; index += 1)
      _offsetOf(values[index]),
  ];
  final along = [0.0];
  var last = start;
  for (final point in [...between, end]) {
    along.add(along.last + (point - last).distance);
    last = point;
  }
  if (along.last <= 0) {
    return null;
  }
  var parameters = [
    for (var index = 1; index <= between.length; index += 1)
      along[index] / along.last,
  ];
  late (Offset, Offset) controls;
  for (var round = 0; round < _bendRounds; round += 1) {
    final fitted = _controlsNearest(start, end, between, parameters);
    if (fitted == null) {
      return null;
    }
    controls = fitted;
    final curve = (start, controls.$1, controls.$2, end);
    parameters = [
      for (final (index, point) in between.indexed)
        _nearerParameter(curve, point, parameters[index]),
    ];
  }
  final (leaving, arriving) = controls;
  final walk = CubicWalk(start, leaving, arriving, end);
  return (
    leaving: leaving,
    arriving: arriving,
    shares: [for (final u in parameters) walk.wayAtParameter(u)],
  );
}

/// The two inner controls of the cubic from [start] to [end] that comes
/// nearest [points] at [parameters], by least squares — each axis the same
/// two-by-two normal equations ([_solved]); null where they have no one
/// answer.
(Offset, Offset)? _controlsNearest(
  Offset start,
  Offset end,
  List<Offset> points,
  List<double> parameters,
) {
  var a11 = 0.0;
  var a12 = 0.0;
  var a22 = 0.0;
  var rest1 = Offset.zero;
  var rest2 = Offset.zero;
  for (final (index, point) in points.indexed) {
    final u = parameters[index];
    final v = 1 - u;
    final b1 = 3 * v * v * u;
    final b2 = 3 * v * u * u;
    final rest = point - start * (v * v * v) - end * (u * u * u);
    a11 += b1 * b1;
    a12 += b1 * b2;
    a22 += b2 * b2;
    rest1 += rest * b1;
    rest2 += rest * b2;
  }
  final normal = [
    [a11, a12],
    [a12, a22],
  ];
  final xs = _solved(normal, [rest1.dx, rest2.dx]);
  final ys = _solved(normal, [rest1.dy, rest2.dy]);
  if (![...xs, ...ys].every((value) => value.isFinite)) {
    return null;
  }
  return (Offset(xs[0], ys[0]), Offset(xs[1], ys[1]));
}

/// [u] moved one Newton step towards the parameter of [curve]'s point
/// nearest [point], kept on the curve.
double _nearerParameter(
  (Offset, Offset, Offset, Offset) curve,
  Offset point,
  double u,
) {
  final (p0, p1, p2, p3) = curve;
  final v = 1 - u;
  final off =
      p0 * (v * v * v) +
      p1 * (3 * v * v * u) +
      p2 * (3 * v * u * u) +
      p3 * (u * u * u) -
      point;
  final slope =
      (p1 - p0) * (3 * v * v) +
      (p2 - p1) * (6 * v * u) +
      (p3 - p2) * (3 * u * u);
  final turn = (p2 - p1 * 2 + p0) * (6 * v) + (p3 - p2 * 2 + p1) * (6 * u);
  final rate = _dotOf(slope, slope) + _dotOf(off, turn);
  if (rate == 0) {
    return u;
  }
  return (u - _dotOf(off, slope) / rate).clamp(0.0, 1.0);
}

double _dotOf(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

Offset _offsetOf(CanvasPoint point) => Offset(point.x, point.y);

/// Where a least-squares fit stands: its numbers, how far they miss what
/// they are fitted to, and the damping its next step starts from.
typedef _Fitting = ({
  List<double> numbers,
  List<double> missed,
  double damping,
});

/// The numbers nearest what [missesOf] measures them against, by least
/// squares — Levenberg–Marquardt, each step's numbers kept to what they may
/// take by [withinReach] (null where they ran off to no number).
///
/// 🚨ONE FIT (card `tvp-camera-keys-only-where-needed`, 2026-11-17).
/// ↩️It was the ease's own ([_NearestEase]); a bent way's handles and pace
/// are fitted by the same steps ([_bentWays]).
final class _LeastSquares {
  const _LeastSquares(this.missesOf, this.withinReach);

  final List<double> Function(List<double> numbers) missesOf;
  final List<double>? Function(List<double> numbers) withinReach;

  /// The fit from [start], stepped while a step misses less.
  _Fitting nearestFrom(List<double> start) {
    var at = (numbers: start, missed: missesOf(start), damping: 1e-3);
    for (var round = 0; round < 100; round += 1) {
      if (_squared(at.missed) <= 1e-24) {
        break;
      }
      final next = _stepFrom(at);
      if (next == null) {
        break;
      }
      at = next;
    }
    return at;
  }

  /// One step from [at] to numbers that miss less — damped ten times more
  /// until one does, and the next step starting ten times less damped —
  /// or null where no damping finds one.
  _Fitting? _stepFrom(_Fitting at) {
    final size = at.numbers.length;
    final cost = _squared(at.missed);
    final slopes = [for (var k = 0; k < size; k += 1) _slopeOf(at, k)];
    final normal = [
      for (final a in slopes) [for (final b in slopes) _dot(a, b)],
    ];
    final pull = [for (final a in slopes) -_dot(a, at.missed)];
    for (var damping = at.damping; damping < 1e12; damping *= 10) {
      final change = _solved([
        for (var m = 0; m < size; m += 1)
          [
            for (var n = 0; n < size; n += 1)
              normal[m][n] + (m == n ? damping * (normal[m][m] + 1e-12) : 0.0),
          ],
      ], pull);
      final numbers = withinReach([
        for (var k = 0; k < size; k += 1) at.numbers[k] + change[k],
      ]);
      if (numbers != null) {
        final missed = missesOf(numbers);
        if (_squared(missed) < cost) {
          return (numbers: numbers, missed: missed, damping: damping / 10);
        }
      }
    }
    return null;
  }

  /// How the misses change as the [k]th number of [at] does, by a small
  /// step forward.
  ///
  /// ⛔Forward for an influence too, though one at all of its segment is
  /// then asked a millionth past it: [segmentProgress] answers as near, and
  /// a step back measured a fit that keyed a reference cut once more
  /// (2026-10-13).
  List<double> _slopeOf(_Fitting at, int k) {
    final step = 1e-6 * math.max(1, at.numbers[k].abs());
    final moved = [...at.numbers];
    moved[k] += step;
    final missedThere = missesOf(moved);
    return [
      for (var index = 0; index < at.missed.length; index += 1)
        (missedThere[index] - at.missed[index]) / step,
    ];
  }
}

/// The ease — a leaving side and an arriving side — whose curve
/// ([segmentProgress]) comes nearest [shares] at [times], by least squares
/// ([_LeastSquares]) over the two influences and the two speeds.
final class _NearestEase {
  _NearestEase({required this.times, required this.shares});

  final List<double> times;
  final List<double> shares;

  /// The ease, fitted from a straight ramp.
  ///
  /// ⛔Not from a second start as well — the speeds the first and the last
  /// step take, the nearer of the two fits kept: on every calibration file
  /// and reference cut the second start changed no key, and alone it keyed
  /// a cut once more (measured 2026-10-13).
  (EaseSide, EaseSide) sides() {
    final sides = _LeastSquares(_missesOf, _withinReach).nearestFrom([
      EaseSide.easeInfluence,
      1,
      EaseSide.easeInfluence,
      1,
    ]).numbers;
    return (
      EaseSide(influence: sides[0], speed: sides[1]),
      EaseSide(influence: sides[2], speed: sides[3]),
    );
  }

  /// How far the ease of [sides] misses each share.
  List<double> _missesOf(List<double> sides) => [
    for (var index = 0; index < times.length; index += 1)
      segmentProgress(
            times[index],
            leaving: (influence: sides[0], speed: sides[1]),
            arriving: (influence: sides[2], speed: sides[3]),
          ) -
          shares[index],
  ];
}

double _squared(List<double> misses) =>
    misses.fold(0.0, (sum, miss) => sum + miss * miss);

/// [sides] with each influence within what a side may take
/// ([EaseSide.leastInfluence] to all of the segment) — null where any of
/// them ran off to no number.
List<double>? _withinReach(List<double> sides) {
  if (!sides.every((value) => value.isFinite)) {
    return null;
  }
  double reach(double influence) =>
      influence.clamp(EaseSide.leastInfluence, 1.0).toDouble();
  return [reach(sides[0]), sides[1], reach(sides[2]), sides[3]];
}

double _dot(List<double> a, List<double> b) {
  var sum = 0.0;
  for (var index = 0; index < a.length; index += 1) {
    sum += a[index] * b[index];
  }
  return sum;
}

/// [matrix] · x = [right] solved for x by elimination, the diagonal the
/// pivot all the way: the damped normal equations a fit's step solves are
/// positive definite, so no row need trade places. A matrix too near
/// singular comes out as numbers that are not finite, which the step
/// refuses ([_withinReach]).
///
/// ⛔`solveHomography` eliminates inside its own system too, and the two
/// are not merged: this is the SECOND, and the rule of three holds. Theirs
/// is a general system — rows trade places for the largest pivot, and a
/// pivot under 1e-9, a quad folded flat in canvas units, is refused — and
/// two do not yet show which of those is the law. 🔜The third linear solve
/// merges all three.
List<double> _solved(List<List<double>> matrix, List<double> right) {
  final size = right.length;
  final rows = [
    for (var m = 0; m < size; m += 1) [...matrix[m], right[m]],
  ];
  for (var column = 0; column < size; column += 1) {
    for (var row = 0; row < size; row += 1) {
      if (row == column) {
        continue;
      }
      final factor = rows[row][column] / rows[column][column];
      for (var k = column; k <= size; k += 1) {
        rows[row][k] -= factor * rows[column][k];
      }
    }
  }
  return [for (var m = 0; m < size; m += 1) rows[m][size] / rows[m][m]];
}

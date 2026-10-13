import 'dart:collection';
import 'dart:math' as math;

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
/// ease ([EaseSide] on both of its ends). Where one way does not play the
/// file's move within a pixel, a key stands where it stops doing so, and
/// the way goes on from there.
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
/// its values in, and how near a played value must come to the file's.
final class _TransformLane<T> {
  const _TransformLane(this.space, this.near);

  final KeyValueSpace<T> space;
  final bool Function(T played, T shown) near;
}

bool _pointsNear(CanvasPoint played, CanvasPoint shown, double tolerance) =>
    (played.x - shown.x).abs() <= tolerance &&
    (played.y - shown.y).abs() <= tolerance;

final _anchorLane = _TransformLane<CanvasPoint>(
  pointKeySpace,
  (played, shown) => _pointsNear(played, shown, _pointTolerance),
);

final _positionLane = _TransformLane<CanvasPoint>(
  positionKeySpace,
  (played, shown) => _pointsNear(played, shown, _pointTolerance),
);

final _scaleLane = _TransformLane<CanvasPoint>(
  pointKeySpace,
  (played, shown) => _pointsNear(played, shown, _scaleTolerance),
);

final _rotationLane = _TransformLane<double>(
  doubleKeySpace,
  (played, shown) => (played - shown).abs() <= _rotationTolerance,
);

/// How a way between two keys goes: the side it leaves the one by and the
/// side it reaches the other by ([PropertyKey.outgoing] · `incoming`).
typedef _Way = ({KeyExit leaving, KeySide arriving});

const _Way _straight = (leaving: KeySide.linear, arriving: KeySide.linear);

/// The value held from the key on, AE's Hold — what CLIP STUDIO's
/// `Constant` plays.
const _Way _held = (leaving: KeyExit.hold, arriving: KeySide.linear);

/// One lane's keys, fitted to [values] — the file's value on each of
/// [frames], in order.
final class _LaneKeys<T> {
  _LaneKeys(this.frames, this.values, this.lane);

  final List<int> frames;
  final List<T> values;
  final _TransformLane<T> lane;

  /// The index of each key, and the sides the ways either side give it.
  final _stops = SplayTreeSet<int>();
  final _leaving = <int, KeyExit>{};
  final _arriving = <int, KeySide>{};

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
          ),
      },
    );
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
  }

  /// The one way from index [from] to [to] that plays every frame between
  /// as the file shows it — held, straight or eased — or null when none
  /// does.
  _Way? _wayBetween(int from, int to) {
    if (to - from < 2) {
      return _straight;
    }
    final start = values[from];
    if (start != values[to] &&
        values.getRange(from + 1, to).every((value) => value == start)) {
      return _held;
    }
    if (_plays(from, to, _straight)) {
      return _straight;
    }
    final eased = _easedWay(from, to);
    return eased != null && _plays(from, to, eased) ? eased : null;
  }

  /// Whether [way] from index [from] to [to] plays every frame between as
  /// the file shows it — read the way the app plays a lane
  /// ([PropertyTrack.resolveAt]), so what is checked is what is seen.
  bool _plays(int from, int to, _Way way) {
    final track = PropertyTrack<T>(
      keys: {
        frames[from]: PropertyKey(values[from], outgoing: way.leaving),
        frames[to]: PropertyKey(values[to], incoming: way.arriving),
      },
    );
    for (var index = from + 1; index < to; index += 1) {
      final played = track.resolveAt(
        frameIndex: frames[index],
        orElse: () => values[index],
        space: lane.space,
      );
      if (!lane.near(played, values[index])) {
        return false;
      }
    }
    return true;
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
    return (leaving: leaving, arriving: arriving);
  }
}

/// Where a fit of the ease stands: its four numbers — the leaving side's
/// influence and speed, the arriving side's — how far they miss each
/// share, and the damping its next step starts from.
typedef _Fitting = ({List<double> sides, List<double> missed, double damping});

/// The ease — a leaving side and an arriving side — whose curve
/// ([segmentProgress]) comes nearest [shares] at [times], by least squares:
/// Levenberg–Marquardt over the two influences and the two speeds.
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
    final sides = _nearestFrom([
      EaseSide.easeInfluence,
      1,
      EaseSide.easeInfluence,
      1,
    ]).sides;
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

  /// The fit from [start], stepped while a step misses less.
  _Fitting _nearestFrom(List<double> start) {
    var at = (sides: start, missed: _missesOf(start), damping: 1e-3);
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
    final cost = _squared(at.missed);
    final slopes = [for (var k = 0; k < 4; k += 1) _slopeOf(at, k)];
    final normal = [
      for (final a in slopes) [for (final b in slopes) _dot(a, b)],
    ];
    final pull = [for (final a in slopes) -_dot(a, at.missed)];
    for (var damping = at.damping; damping < 1e12; damping *= 10) {
      final change = _solved([
        for (var m = 0; m < 4; m += 1)
          [
            for (var n = 0; n < 4; n += 1)
              normal[m][n] + (m == n ? damping * (normal[m][m] + 1e-12) : 0.0),
          ],
      ], pull);
      final sides = _withinReach([
        for (var k = 0; k < 4; k += 1) at.sides[k] + change[k],
      ]);
      if (sides != null) {
        final missed = _missesOf(sides);
        if (_squared(missed) < cost) {
          return (sides: sides, missed: missed, damping: damping / 10);
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
    final step = 1e-6 * math.max(1, at.sides[k].abs());
    final moved = [...at.sides];
    moved[k] += step;
    final missedThere = _missesOf(moved);
    return [
      for (var index = 0; index < at.missed.length; index += 1)
        (missedThere[index] - at.missed[index]) / step,
    ];
  }
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

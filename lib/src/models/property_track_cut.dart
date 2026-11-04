import 'dart:collection';
import 'dart:ui' show Offset;

import '../core/cubic_curve.dart';
import 'canvas_point.dart';
import 'key_path_walk.dart' show keyPathHandle;
import 'property_track.dart';

/// [track] cleared over the frames from [range]'s start to its end
/// (exclusive) of the ones its [lane] is drawn over — a bake's (I-120):
/// [rest] at each of them, and every other frame showing what it showed.
///
/// 🗣️I-120-Q3 (유저 2026-11-04) 「범위 안만 굽고, 범위 밖은 보이던 그대로」 —
/// a key on the frame before the range and on the frame after it, at the
/// value it showed there; a way the range cuts keeps its half outside as
/// it was, its curve cut in two ([cubicCut]) and the half's handles set to
/// the curve's — the time's and, on a lane that walks a path, the path's.
/// A side whose frames a cut cannot keep so — a value rounded on its way
/// (a colour's channels), a run of roving keys (I-89 ④), a curve that
/// comes back to where it was cut — takes a key on each of its frames from
/// the last key before the cut, the value it showed. A range over every
/// frame clears every key.
PropertyTrack<T> trackClearedOver<T>(
  PropertyTrack<T> track, {
  required ({int start, int end}) range,
  required T rest,
  required DrawnLane<T> lane,
}) {
  final (:start, :end) = range;
  final frames = lane.frames;
  assert(0 <= start && start < end && end <= frames, 'a range of frames');
  final sides = [
    if (start > 0) (before: true, at: start - 1),
    if (end < frames) (before: false, at: end),
  ];
  if (sides.isEmpty || (track.isEmpty && lane.same(lane.unkeyed(), rest))) {
    return PropertyTrack.empty();
  }
  return _Cut(track, lane).cleared(sides, {
    if (start > 0) start: PropertyKey(rest),
    if (end < frames) end - 1: PropertyKey(rest),
  });
}

/// A lane as a cut draws it ([trackClearedOver]): the [frames] it is drawn
/// over, how its values walk between keys ([space]), its value with no key
/// ([unkeyed]), and whether two of its values show as one ([same]).
typedef DrawnLane<T> = ({
  int frames,
  KeyValueSpace<T> space,
  T Function() unkeyed,
  bool Function(T a, T b) same,
});

/// One side of a cut: the frames [before] the cleared range, up to [at] —
/// the frame before it — or the frames after it, from [at] on.
typedef _Side = ({bool before, int at});

/// The cut of one track ([trackClearedOver]).
final class _Cut<T> {
  _Cut(this.track, this.lane);

  final PropertyTrack<T> track;
  final DrawnLane<T> lane;

  int get frames => lane.frames;

  KeyValueSpace<T> get space => lane.space;

  /// The roving keys of [track] (I-89 ④), whose frame is not their time.
  late final Set<int> _roving = track.rovingTimes(space).keys.toSet();

  /// What [track] shows at [frame].
  T was(int frame) => _shownBy(track, frame);

  T _shownBy(PropertyTrack<T> keys, int frame) =>
      keys.resolveAt(frameIndex: frame, orElse: lane.unkeyed, space: space);

  /// [track] with [range]'s keys and each of [sides] keeping its frames
  /// as they showed: the way across its edge cut where that keeps them,
  /// else a key on each of its frames from the last key before the edge.
  PropertyTrack<T> cleared(List<_Side> sides, Map<int, PropertyKey<T>> range) {
    final ways = {
      for (final side in sides) side: _cutAcross(side) ?? _framewise(side),
    };
    PropertyTrack<T> laid() => _frozen(
      PropertyTrack(keys: {...range, for (final way in ways.values) ...way}),
    );
    var cleared = laid();
    final missed = [
      for (final side in sides)
        if (!_showsAsItWas(side, cleared)) side,
    ];
    if (missed.isNotEmpty) {
      for (final side in missed) {
        ways[side] = _framewise(side);
      }
      cleared = laid();
      assert(
        sides.every((side) => _showsAsItWas(side, cleared)),
        'a key on every frame of a side shows what it showed',
      );
    }
    return _unnamedWhereChanged(cleared);
  }

  /// Whether [cleared] shows each frame of [side] as [track] did.
  bool _showsAsItWas(_Side side, PropertyTrack<T> cleared) {
    final (:before, :at) = side;
    for (var frame = before ? 0 : at;
        frame <= (before ? at : frames - 1);
        frame += 1) {
      if (!lane.same(was(frame), _shownBy(cleared, frame))) {
        return false;
      }
    }
    return true;
  }

  /// [side]'s keys, and a key on its edge showing what [track] showed there
  /// — the way across the edge cut where one crosses it. Null where it
  /// crosses a run of roving keys, or where a half cannot be paced
  /// ([_halfPace]).
  Map<int, PropertyKey<T>>? _cutAcross(_Side side) {
    final (:before, :at) = side;
    final kept = _keysOf(side);
    if (track.keys.containsKey(at)) {
      return kept;
    }
    final from = track.keys.lastKeyBefore(at);
    final to = track.keys.firstKeyAfter(at);
    final stand = PropertyKey(was(at));
    if (from == null || to == null) {
      return {...kept, at: stand};
    }
    if (_roving.contains(from) || _roving.contains(to)) {
      return null;
    }
    final leaving = track.keys[from]!.outgoing;
    if (leaving is! KeySide) {
      // A hold: the value stands still across the edge.
      return {
        ...kept,
        at: before ? stand : stand.copyWith(outgoing: KeyExit.hold),
      };
    }
    final half = _halfOf((from: from, to: to), side);
    if (half == null) {
      return null;
    }
    final cut = {
      ...kept,
      if (before)
        from: kept[from]!.copyWith(
          outgoing: _sideOf(leaving, half.pace.leaving),
        )
      else
        to: kept[to]!.copyWith(
          incoming: _sideOf(kept[to]!.incoming, half.pace.arriving),
        ),
      at: before
          ? stand.copyWith(
              incoming: _sideOf(KeySide.linear, half.pace.arriving),
            )
          : stand.copyWith(
              outgoing: _sideOf(KeySide.linear, half.pace.leaving),
            ),
    };
    if (space.walk == null) {
      return cut;
    }
    return _pathCut(
          track.keys as SplayTreeMap<int, PropertyKey<CanvasPoint>>,
          cut as Map<int, PropertyKey<CanvasPoint>>,
          (way: (from: from, to: to), side: side, progress: half.progress),
        )
        as Map<int, PropertyKey<T>>;
  }

  /// The half of [way]'s curve on [side] of its edge, paced as a way of its
  /// own ([_halfPace]), and how far the value had come along the way at the
  /// edge — null where the half cannot be paced.
  ({KeyPace pace, double progress})? _halfOf(_Way way, _Side side) {
    final (:from, :to) = way;
    final pace = track.paceFrom(from, space)!.pace;
    final time = segmentCurveParameter(
      (side.at - from) / (to - from),
      leaving: pace.leaving,
      arriving: pace.arriving,
    );
    final curve = cubicCut((
      Offset.zero,
      _pointOf(keyHandlePoint(pace.leaving, leaving: true)),
      _pointOf(keyHandlePoint(pace.arriving, leaving: false)),
      const Offset(1, 1),
    ), time);
    final half = side.before
        ? _halfPace(Offset.zero, curve.before.$1, curve.before.$2, curve.at)
        : _halfPace(
            curve.at,
            curve.after.$1,
            curve.after.$2,
            const Offset(1, 1),
          );
    return half == null ? null : (pace: half, progress: curve.at.dy);
  }

  /// [track]'s keys on [side]'s frames.
  Map<int, PropertyKey<T>> _keysOf(_Side side) => {
    for (final MapEntry(key: frame, :value) in track.keys.entries)
      if (side.before ? frame <= side.at : frame >= side.at) frame: value,
  };

  /// [side]'s keys as far as the last of its own that keeps its time
  /// before its edge, and a key on each frame from there to the edge
  /// showing what [track] showed.
  Map<int, PropertyKey<T>> _framewise(_Side side) {
    final (:before, :at) = side;
    int? inward(int frame) => before
        ? track.keys.lastKeyBefore(frame)
        : track.keys.firstKeyAfter(frame);
    var edge = before ? inward(at + 1) : inward(at - 1);
    while (edge != null && _roving.contains(edge)) {
      edge = inward(edge);
    }
    final kept = {
      for (final MapEntry(key: frame, :value) in track.keys.entries)
        if (edge != null && (before ? frame <= edge : frame >= edge))
          frame: value,
    };
    for (var frame = at;
        before ? frame > (edge ?? -1) : frame < (edge ?? at + 1);
        frame += before ? -1 : 1) {
      kept[frame] = PropertyKey(was(frame));
    }
    return kept;
  }

  /// [cleared] with each side of a key of [track]'s an auto handle reads
  /// across the cut — whose neighbour the cut moved — set to the handle it
  /// was read as, and each path bending through a key by the keys either
  /// side of it set to the way it bent: so the ways [track] kept stay as
  /// they were.
  PropertyTrack<T> _frozen(PropertyTrack<T> cleared) {
    final next = SplayTreeMap<int, PropertyKey<T>>.from(cleared.keys);
    for (final from in cleared.keys.keys) {
      if (track.keys[from] == null) {
        continue;
      }
      final was = track.paceFrom(from, space);
      final now = cleared.paceFrom(from, space);
      if (was == null ||
          now == null ||
          was.to != now.to ||
          track.keys[was.to] == null) {
        continue;
      }
      final leaving = next[from]!;
      if (leaving.outgoing case final KeySide side
          when !_sameHandle(was.pace.leaving, now.pace.leaving)) {
        next[from] = leaving.copyWith(
          outgoing: _sideOf(side, was.pace.leaving),
        );
      }
      final arriving = next[was.to]!;
      if (!_sameHandle(was.pace.arriving, now.pace.arriving)) {
        next[was.to] = arriving.copyWith(
          incoming: _sideOf(arriving.incoming, was.pace.arriving),
        );
      }
    }
    if (space.walk == null) {
      return PropertyTrack(keys: next);
    }
    return PropertyTrack(
      keys:
          _pathsFrozen(
                track.keys as SplayTreeMap<int, PropertyKey<CanvasPoint>>,
                next as SplayTreeMap<int, PropertyKey<CanvasPoint>>,
              )
              as Map<int, PropertyKey<T>>,
    );
  }

  /// [cleared] with each key of [track]'s whose sides it changed out of
  /// the name it shared — 🗣️I-120-Q15, its recommendation while it is
  /// asked: a name is one key seen in several places, sides and all (유저
  /// 09-12 「싹다 링크해야하는데」), so a key the cut set apart leaves the
  /// link and its namesakes stay as they were.
  PropertyTrack<T> _unnamedWhereChanged(PropertyTrack<T> cleared) =>
      PropertyTrack(
        keys: {
          for (final MapEntry(key: frame, value: key) in cleared.keys.entries)
            frame: switch (track.keys[frame]) {
              final own? when own.name != null && own.held != key.held =>
                key.copyWith(name: () => null),
              _ => key,
            },
        },
      );
}

/// A way across an edge: the keys either side of it.
typedef _Way = ({int from, int to});

/// The half of a way's curve from [from] to [to] through [leaving] and
/// [arriving], each a point of the way's unit square, paced as a way of
/// its own — null where it cannot be: where the value does not move along
/// it, or a handle would reach out of it.
KeyPace? _halfPace(Offset from, Offset leaving, Offset arriving, Offset to) {
  final span = to - from;
  if (span.dx.abs() < 1e-12 || span.dy.abs() < 1e-12) {
    return null;
  }
  Offset unit(Offset point) =>
      Offset((point.dx - from.dx) / span.dx, (point.dy - from.dy) / span.dy);
  final lead = unit(leaving);
  final into = 1 - unit(arriving).dx;
  if (lead.dx <= 0 || lead.dx > 1 + 1e-9 || into <= 0 || into > 1 + 1e-9) {
    return null;
  }
  return (
    leaving: (
      influence: lead.dx.clamp(0.0, 1.0).toDouble(),
      speed: lead.dy / lead.dx,
    ),
    arriving: (
      influence: into.clamp(0.0, 1.0).toDouble(),
      speed: (1 - unit(arriving).dy) / into,
    ),
  );
}

/// The side that puts [handle] in its way: [side] where it already does —
/// a straight ramp, or an ease of that very handle — an ease of it
/// otherwise.
KeySide _sideOf(KeySide side, KeyHandle handle) => switch (side) {
  LinearSide() when _sameHandle(handle, linearKeyHandle) => side,
  EaseSide(:final influence, :final speed)
      when _sameHandle(handle, (influence: influence, speed: speed)) =>
    side,
  _ => EaseSide(influence: handle.influence, speed: handle.speed),
};

bool _sameHandle(KeyHandle a, KeyHandle b) =>
    (a.influence - b.influence).abs() < 1e-9 &&
    (a.speed - b.speed).abs() < 1e-9;

Offset _pointOf(({double x, double y}) point) => Offset(point.x, point.y);

Offset _offsetOf(CanvasPoint point) => Offset(point.x, point.y);

/// A cut of a lane that walks a path: [cut] with the path through the key
/// its [way] has outside the edge — its handle into the way shortened to
/// the half's — and the key on the edge bending as the path did there,
/// both read off the path's two halves at the [progress] its walk had come
/// ([cubicCut]).
Map<int, PropertyKey<CanvasPoint>> _pathCut(
  SplayTreeMap<int, PropertyKey<CanvasPoint>> keys,
  Map<int, PropertyKey<CanvasPoint>> cut,
  ({_Way way, _Side side, double progress}) at,
) {
  final (way: (:from, :to), side: (:before, at: edge), :progress) = at;
  final start = _offsetOf(keys[from]!.value);
  final end = _offsetOf(keys[to]!.value);
  final ahead = keyPathHandle(keys, from, ahead: true);
  final behind = keyPathHandle(keys, to, ahead: false);
  if (ahead == Offset.zero && behind == Offset.zero) {
    return cut; // A straight way: the key on the edge a corner on it.
  }
  final controls = (start, start + ahead, end + behind, end);
  final u = CubicWalk(
    controls.$1,
    controls.$2,
    controls.$3,
    controls.$4,
  ).parameterAt(progress);
  final halves = cubicCut(controls, u);
  final outside = before ? from : to;
  final handle = before
      ? halves.before.$2 - halves.at
      : halves.after.$1 - halves.at;
  return {
    ...cut,
    outside: cut[outside]!.copyWith(
      path: _reaching(
        _bentAsItWas(keys, outside),
        ahead: before,
        by: before ? u : 1 - u,
      ),
    ),
    edge: cut[edge]!.copyWith(
      path: handle == Offset.zero
          ? KeyPath.straight
          : JoinedPath(
              degrees: handleDegrees(before ? -handle : handle),
              ahead: before ? 0 : handle.distance,
              behind: before ? handle.distance : 0,
            ),
    ),
  };
}

/// [path] with its handle [ahead] of its key — or the one behind it —
/// reaching [by] of how far it reached.
KeyPath _reaching(KeyPath path, {required bool ahead, required double by}) =>
    switch (path) {
      JoinedPath(:final degrees, ahead: final front, :final behind) =>
        JoinedPath(
          degrees: degrees,
          ahead: ahead ? front * by : front,
          behind: ahead ? behind : behind * by,
        ),
      SplitPath(ahead: final front, :final behind) => SplitPath(
        ahead: ahead ? CanvasPoint(x: front.x * by, y: front.y * by) : front,
        behind: ahead
            ? behind
            : CanvasPoint(x: behind.x * by, y: behind.y * by),
      ),
      _ => path,
    };

/// The path through the key at [frame] of [keys] as it bends there: one
/// the keys either side of it lay ([KeyPath.auto]) set to the way they lay
/// it ([KeyPath.turned]) — AE's continuous bezier, which an auto key
/// becomes once its handle is set — where it reaches out at all; any other
/// as it is.
KeyPath _bentAsItWas(
  SplayTreeMap<int, PropertyKey<CanvasPoint>> keys,
  int frame,
) {
  final path = keys[frame]!.path;
  if (path is! AutoPath ||
      (keyPathHandle(keys, frame, ahead: true) == Offset.zero &&
          keyPathHandle(keys, frame, ahead: false) == Offset.zero)) {
    return path;
  }
  final (:at, :before, :after) = keyStanding(keys, frame);
  return path.turned(
    KeyPathKind.continuousBezier,
    at: at,
    before: before,
    after: after,
  );
}

/// [cleared] with each auto key ([KeyPath.auto]) of [keys]'s whose
/// neighbours the cut moved set to the way it bent through [keys]
/// ([_bentAsItWas]), so the path either side of it stays as it was.
SplayTreeMap<int, PropertyKey<CanvasPoint>> _pathsFrozen(
  SplayTreeMap<int, PropertyKey<CanvasPoint>> keys,
  SplayTreeMap<int, PropertyKey<CanvasPoint>> cleared,
) {
  final next = SplayTreeMap<int, PropertyKey<CanvasPoint>>.from(cleared);
  for (final MapEntry(key: frame, value: key) in cleared.entries) {
    if (key.path is! AutoPath || keys[frame] == null) {
      continue;
    }
    final was = keyStanding(keys, frame);
    final now = keyStanding(cleared, frame);
    if (was.before != now.before || was.after != now.after) {
      next[frame] = key.copyWith(path: _bentAsItWas(keys, frame));
    }
  }
  return next;
}

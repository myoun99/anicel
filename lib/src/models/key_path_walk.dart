import 'dart:collection';
import 'dart:ui' show Offset;

import '../core/cubic_curve.dart';
import 'canvas_point.dart';
import 'property_track.dart';

/// The walk along the segment from the key at frame [from] to the key at
/// frame [to] of the [keys] of a lane that walks a path (`walksAPath`):
/// along the path the two keys'
/// handles bend ([keyPathHandle]), by distance ([CubicWalk]) — the line
/// between them where neither bends (I-89 ④).
SegmentWalk<CanvasPoint> keyPathBetween(
  SplayTreeMap<int, PropertyKey<CanvasPoint>> keys,
  int from,
  int to,
) {
  final a = keys[from]!.value;
  final b = keys[to]!.value;
  final start = Offset(a.x, a.y);
  final end = Offset(b.x, b.y);
  final walk = CubicWalk(
    start,
    start + keyPathHandle(keys, from, ahead: true),
    end + keyPathHandle(keys, to, ahead: false),
    end,
  );
  return (
    at: (progress) {
      final at = walk.at(progress);
      return CanvasPoint(x: at.dx, y: at.dy);
    },
    length: walk.length,
  );
}

/// How far, and which way, the path's handle at the key at [frame] of
/// [keys] reaches out of it ([KeyPath.reach]) — [ahead], towards the key
/// after it, or behind, towards the key before.
Offset keyPathHandle(
  SplayTreeMap<int, PropertyKey<CanvasPoint>> keys,
  int frame, {
  required bool ahead,
}) {
  final (:at, :before, :after) = keyStanding(keys, frame);
  return keys[frame]!.path.reach(
    ahead: ahead,
    at: at,
    before: before,
    after: after,
  );
}

/// The path the key at [frame] of [keys] walks once the hand has carried
/// its handle [ahead] of it, or behind, to reach [reach] out of it
/// (I-89 ②): a split pair's other handle stays as it was; any other key's
/// turns to keep the two in one line, its own length kept — AE's
/// continuous bezier, which an auto key becomes the moment its handle is
/// pulled. Carried onto the key itself, the handle keeps the way the pair
/// lay.
///
/// ⚠️That the other handle keeps its length is this round's reading of
/// AE's model (a key's two tangents are kept apart — [JoinedPath]); what
/// AE's own drag does to it the Adobe pages do not say
/// (anchor-walks-a-path-Q3).
KeyPath keyPathPulled(
  SplayTreeMap<int, PropertyKey<CanvasPoint>> keys,
  int frame, {
  required bool ahead,
  required Offset reach,
}) {
  if (keys[frame]!.path case SplitPath(ahead: final front, :final behind)) {
    final carried = CanvasPoint(x: reach.dx, y: reach.dy);
    return SplitPath(
      ahead: ahead ? carried : front,
      behind: ahead ? behind : carried,
    );
  }
  final other = keyPathHandle(keys, frame, ahead: !ahead).distance;
  final front = ahead ? reach : -reach;
  final (:at, :before, :after) = keyStanding(keys, frame);
  return JoinedPath(
    degrees: front == Offset.zero
        ? keys[frame]!.path.wayAhead(at: at, before: before, after: after)
        : handleDegrees(front),
    ahead: ahead ? reach.distance : other,
    behind: ahead ? other : reach.distance,
  );
}

/// A curved key's handles as the canvas draws them (I-89 ④, the mock's
/// 5판 · ②): the key at [frame], standing [at], where its handle [ahead]
/// of it ends and where the one [behind] it does — each a knob the hand
/// takes, and none on a side no segment leaves by: a first key's behind,
/// a last key's ahead.
///
/// ⚠️That an end key offers its one live handle alone is this round's
/// choice: with both on it, a last key's knob of no length would pull the
/// handle ahead, which bends nothing. ↩️One knob, ahead, its mirror
/// bending the segment behind.
typedef KeyPathKnob = ({
  int frame,
  CanvasPoint at,
  CanvasPoint? ahead,
  CanvasPoint? behind,
});

/// The handles [keys]' curved keys reach out with ([keyPathHandle]), from
/// frame [from] to frame [to] where the canvas keeps to some — a corner
/// has none, nor a key no segment reaches. One of no length stands on its
/// key: a smooth end key's, which the hand pulls out from there.
List<KeyPathKnob> keyPathKnobs(
  SplayTreeMap<int, PropertyKey<CanvasPoint>> keys, {
  int? from,
  int? to,
}) {
  CanvasPoint? reached(int frame, {required bool ahead}) {
    final neighbour = ahead
        ? keys.firstKeyAfter(frame)
        : keys.lastKeyBefore(frame);
    if (neighbour == null) {
      return null;
    }
    final at = keys[frame]!.value;
    final handle = keyPathHandle(keys, frame, ahead: ahead);
    return CanvasPoint(x: at.x + handle.dx, y: at.y + handle.dy);
  }

  return [
    for (final MapEntry(key: frame, :value) in keys.entries)
      if (value.path.curved &&
          keys.length > 1 &&
          frame >= (from ?? frame) &&
          frame <= (to ?? frame))
        (
          frame: frame,
          at: value.value,
          ahead: reached(frame, ahead: true),
          behind: reached(frame, ahead: false),
        ),
  ];
}

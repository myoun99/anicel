import 'dart:collection';
import 'dart:ui' show Offset;

import '../core/cubic_curve.dart';
import 'canvas_point.dart';
import 'property_track.dart';

/// The walk along the segment from the key at frame [from] to the key at
/// frame [to] of a position lane's [keys]: along the path the two keys'
/// handles bend ([keyPathHandle]), by distance ([CubicWalk]) — the line
/// between them where neither bends (I-89 ④).
SegmentWalk<CanvasPoint> positionPathBetween(
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
  return (progress) {
    final at = walk.at(progress);
    return CanvasPoint(x: at.dx, y: at.dy);
  };
}

/// How far, and which way, the path's handle at the key at [frame] of
/// [keys] reaches out of it — [ahead], towards the key after it, or behind,
/// towards the key before:
///
/// - a corner ([KeyPath.straight]) has none;
/// - a handle the hand placed ([HandledPath]) reaches its tangent ahead and
///   its mirror behind (④-Q4 A: 「반대쪽 핸들은 거울처럼 따라옵니다」);
/// - an auto key ([KeyPath.auto]) lies along the line from the key before
///   it to the key after it, reaching a third of the way to the neighbour
///   on that side — none at the first and the last key, which have no
///   line to lie along, nor where the two neighbours stand at one point.
///   ⚠️The third is this round's choice — the reach at which a straight
///   run's controls sit evenly on it; how far After Effects' own auto
///   bezier reaches was not read.
Offset keyPathHandle(
  SplayTreeMap<int, PropertyKey<CanvasPoint>> keys,
  int frame, {
  required bool ahead,
}) {
  final key = keys[frame]!;
  switch (key.path) {
    case StraightPath():
      return Offset.zero;
    case HandledPath(:final tangent):
      final reach = Offset(tangent.x, tangent.y);
      return ahead ? reach : -reach;
    case AutoPath():
      final before = keys.lastKeyBefore(frame);
      final after = keys.firstKeyAfter(frame);
      if (before == null || after == null) {
        return Offset.zero;
      }
      final previous = keys[before]!.value;
      final next = keys[after]!.value;
      final through = Offset(next.x - previous.x, next.y - previous.y);
      if (through == Offset.zero) {
        return Offset.zero;
      }
      final reach = (ahead ? next : previous).distanceTo(key.value) / 3;
      return through / through.distance * (ahead ? reach : -reach);
  }
}

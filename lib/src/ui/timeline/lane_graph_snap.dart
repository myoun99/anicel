import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import '../../core/one_way.dart';
import '../theme/app_theme.dart' show AppColors;
import 'axis_turn.dart'
    show extentAcross, extentAlong, offsetAlong, partAcross, partAlong;
import 'timeline_exposure_comma_drag_policy.dart' show commaDragFrameDelta;
import 'timeline_frame_geometry.dart';

/// How near a target the hand carries a key before the key SNAPS to it
/// (graph-key-drag-snaps), in logical pixels: along the frames to a time,
/// across the graph to a value.
///
/// ⚠️Mine: AE names no number for its snap; eight.
const double laneGraphSnapReach = 8;

/// How wide the line a snap draws is.
///
/// ⚠️Mine: a pixel, as thin as AE's.
const double _laneGraphSnapLineStroke = 1;

/// Where [time] — a frame, or a time between two — stands along a graph
/// laid by [frames] (`laneGraphAlong`, handed in: it lives with the graph
/// that draws by it).
typedef LaneGraphAlong =
    double Function(double time, TimelineFrameGeometry frames);

/// A key as a carry snaps by it: its time on the graph's frames, and how
/// far across the graph its mark stands.
typedef LaneGraphSnapKey = ({int time, double across});

/// Where a key carried has SNAPPED (graph-key-drag-snaps): the frame of
/// the graph's frames it stands on, and how far across the graph its mark
/// stands — each null where it has not snapped that way.
typedef LaneGraphSnap = ({int? time, double? across});

/// A key carried that has snapped neither way.
const LaneGraphSnap laneGraphUnsnapped = (time: null, across: null);

/// How far a key carried goes: [frames] whole frames along the graph's
/// frames and [rise] pixels across it — and where it has [snap]ped.
typedef LaneGraphCarried = ({int frames, double rise, LaneGraphSnap snap});

/// A KEY CARRIED across a header graph (I-3), step by step: as far along
/// the frames as the hand, by whole frames — the band's own step
/// ([commaDragFrameDelta]) — and as far across the graph; with Shift held,
/// the one way it went further alone (I-3 ③, AE's Shift-drag in its graph
/// editor). And SNAPPED where snapping is on (graph-key-drag-snaps, AE's
/// snap): along the frames to the time of a key about it, of the playhead
/// or of either end of the frames, and across the graph to where a key
/// about it is marked — each way on its own, to the nearest within
/// [laneGraphSnapReach] of the hand.
///
/// What it snaps to is read when the carry begins, as the keys the hand
/// lifts are: the lines draw the move in flight. The playhead is read at
/// every step, and every time stands where the frames lie at that step —
/// a carry pans them where the hand reaches the view's edge.
class LaneGraphCarry {
  LaneGraphCarry({
    required this.axis,
    required this.frames,
    required this.alongOf,
    required this.key,
    required this.keys,
    required this.playhead,
    required this.frameCount,
  });

  /// Which way the graph's frames run.
  final Axis axis;

  /// The frames the graph is drawn over, as they lie now.
  final ValueListenable<TimelineFrameGeometry> frames;

  /// Where a time stands along them.
  final LaneGraphAlong alongOf;

  /// The key in hand, as it stood when the carry began.
  final LaneGraphSnapKey key;

  /// The keys it snaps to: the graph's others, as they stood.
  final List<LaneGraphSnapKey> keys;

  /// The frame the playhead stands on — null where there is none.
  final ValueListenable<int?>? playhead;

  /// Where the frames end, that many on from frame 0 — 0 where they have
  /// no end to snap to.
  final int frameCount;

  /// How far a hand gone [moved] carries the key — with Shift held
  /// ([oneWay]) the one way it went further alone — and where it snaps,
  /// where [snapping] says it does: a time snapped to puts the key on that
  /// frame ([_timeNear]), a place across snapped to puts its mark there
  /// ([_acrossNear]).
  ///
  /// ⚠️Mine: Shift is asked before the snap, and held, the way it keeps the
  /// hand off is not snapped either — a snap that way would carry the key
  /// off the one way Shift keeps it to.
  LaneGraphCarried carriedBy(
    Offset moved, {
    required bool oneWay,
    required bool snapping,
  }) {
    final free = (partAlong(axis, moved), partAcross(axis, moved));
    final (along, across) = oneWay ? keptToOneWay(free.$1, free.$2) : free;
    final alongFirst = wentFurtherAlongFirst(along, across);
    final snap = snapping
        ? (
            time: !oneWay || alongFirst ? _timeNear(along) : null,
            across: !oneWay || !alongFirst ? _acrossNear(across) : null,
          )
        : laneGraphUnsnapped;
    return (
      frames: switch (snap.time) {
        final time? => time - key.time,
        null => commaDragFrameDelta(
          accumulatedDelta: along,
          frameCellExtent: frames.value.frameCellExtent,
        ),
      },
      rise: switch (snap.across) {
        final at? => at - key.across,
        null => across,
      },
      snap: snap,
    );
  }

  /// The time the hand gone [moved] along the frames snaps to: of [_times],
  /// the nearest within [laneGraphSnapReach] of it, where the frames lie
  /// now — null where none is so near.
  int? _timeNear(double moved) {
    final frames = this.frames.value;
    double at(int time) => alongOf(time.toDouble(), frames);
    final hand = at(key.time) + moved;
    return _nearest(_times, (time) => at(time) - hand);
  }

  /// Where across the graph the hand gone [rose] across it snaps to: of
  /// the [keys]' marks, the nearest within [laneGraphSnapReach] of it —
  /// null where none is so near.
  double? _acrossNear(double rose) {
    final hand = key.across + rose;
    return _nearest([for (final key in keys) key.across], (at) => at - hand);
  }

  /// The times a key carried snaps to: the keys about it, the playhead, and
  /// the frames' two ends.
  List<int> get _times => [
    for (final key in keys) key.time,
    ?playhead?.value,
    0,
    if (frameCount > 0) frameCount,
  ];
}

/// Of [targets], the one nearest the hand by how far [away] it says each
/// stands — the first of the nearest, and only within [laneGraphSnapReach]
/// either way; null where none is so near.
T? _nearest<T extends Object>(
  Iterable<T> targets,
  double Function(T target) away,
) {
  T? nearest;
  var least = double.infinity;
  for (final target in targets) {
    final distance = away(target).abs();
    if (distance <= laneGraphSnapReach && distance < least) {
      nearest = target;
      least = distance;
    }
  }
  return nearest;
}

/// The LINE a key carried draws where it snaps (graph-key-drag-snaps, AE's
/// snap line): across the whole graph at the time it snapped to, along the
/// whole graph where across it snapped to — nothing where it snapped
/// neither way. Over the picture, as AE's is over its graph; in
/// [AppColors.snapLine].
class LaneGraphSnapLine extends CustomPainter {
  LaneGraphSnapLine(this.carry, this.snap) : super(repaint: carry.frames);

  final LaneGraphCarry carry;
  final LaneGraphSnap snap;

  @override
  void paint(Canvas canvas, Size size) {
    final axis = carry.axis;
    final ink = Paint()
      ..strokeWidth = _laneGraphSnapLineStroke
      ..color = AppColors.snapLine;
    if (snap.time case final time?) {
      final along = carry.alongOf(time.toDouble(), carry.frames.value);
      canvas.drawLine(
        offsetAlong(axis, along: along, across: 0),
        offsetAlong(axis, along: along, across: extentAcross(axis, size)),
        ink,
      );
    }
    if (snap.across case final across?) {
      canvas.drawLine(
        offsetAlong(axis, along: 0, across: across),
        offsetAlong(axis, along: extentAlong(axis, size), across: across),
        ink,
      );
    }
  }

  @override
  bool shouldRepaint(LaneGraphSnapLine oldDelegate) =>
      oldDelegate.carry != carry || oldDelegate.snap != snap;
}

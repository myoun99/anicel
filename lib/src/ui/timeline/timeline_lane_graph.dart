import 'package:flutter/widgets.dart';

import 'axis_turn.dart' show acrossBox, sizedAlong;
import 'lane_graph.dart';
import 'property_lane_model.dart';
import 'timeline_row_edges.dart';

/// What either grid lays on the frame side for [rows] — row [first] of
/// [edges] onward: each row's own [cells], and an open graph's lanes as ONE
/// [TimelineLaneGraph] across their whole unit (I-89 ③).
List<Widget> timelineFrameSide(
  List<TimelineDisplayRow> rows, {
  required TimelineRowEdges edges,
  int first = 0,
  required double frameExtent,
  required String keyPrefix,
  Axis axis = Axis.horizontal,
  required Widget Function(TimelineDisplayRow row) cells,
}) => [
  for (final unit in edges.unitsIn(first, first + rows.length))
    if (rows[unit.first - first].graph case final seat?)
      TimelineLaneGraph(
        key: ValueKey<String>('$keyPrefix-lane-graph-${seat.groupKey}'),
        seat: seat,
        lanes: rows.sublist(unit.first - first, unit.last - first + 1),
        frameExtent: frameExtent,
        crossExtent: edges.unitSpanOf(unit.first).extent,
        axis: axis,
      )
    else ...[
      cells(rows[unit.first - first]),
      if (edges.roomOf(unit.last) > 0)
        acrossBox(axis, edges.roomOf(unit.last)),
    ],
];

/// An open graph on the frame side: ONE picture over its group's [lanes]
/// and the room after them, where their rows of cells would be (I-89 ③) —
/// the same widget on the timeline and, turned on its side, the sheet.
class TimelineLaneGraph extends StatelessWidget {
  const TimelineLaneGraph({
    super.key,
    required this.seat,
    required this.lanes,
    required this.frameExtent,
    required this.crossExtent,
    this.axis = Axis.horizontal,
  });

  final TimelineGraphSeat seat;

  /// The group's lanes as the rail draws them, in its order.
  final List<TimelineDisplayRow> lanes;

  /// How far the picture runs along the frames.
  final double frameExtent;

  /// How far it reaches across them — its lanes and the room after them.
  final double crossExtent;
  final Axis axis;

  @override
  Widget build(BuildContext context) =>
      sizedAlong(axis, along: frameExtent, across: crossExtent);
}

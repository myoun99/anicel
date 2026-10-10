import 'package:flutter/widgets.dart';

import 'axis_turn.dart' show acrossBox, sizedAlong;
import 'lane_graph.dart';
import 'property_lane_model.dart';
import 'timeline_cells_row_facts.dart' show TimelineCellsRowGrid;
import 'timeline_row_edges.dart';

/// Rows as a grid lays them: [rows] are its rows from [first] on, and
/// [edges] where every one of its rows sits.
typedef TimelineLaidRows = ({
  List<TimelineDisplayRow> rows,
  int first,
  TimelineRowEdges edges,
});

/// What [grid] lays on the frame side for [laid], [frameExtent] along the
/// frames: each row's own [cells], and an open graph's lanes as ONE
/// [TimelineLaneGraph] across their whole unit (I-89 ③).
List<Widget> timelineFrameSide(
  TimelineLaidRows laid,
  TimelineCellsRowGrid grid, {
  required double frameExtent,
  required Widget Function(TimelineDisplayRow row) cells,
}) {
  final (:rows, :first, :edges) = laid;
  return [
    for (final unit in edges.unitsIn(first, first + rows.length))
      if (rows[unit.first - first].graph case final seat?)
        TimelineLaneGraph(
          key: ValueKey<String>(
            '${grid.keyPrefix}-lane-graph-${seat.groupKey}',
          ),
          seat: seat,
          lanes: rows.sublist(unit.first - first, unit.last - first + 1),
          grid: grid,
          frameExtent: frameExtent,
          crossExtent: edges.unitSpanOf(unit.first).extent,
        )
      else ...[
        cells(rows[unit.first - first]),
        if (edges.roomOf(unit.last) > 0)
          acrossBox(grid.axis, edges.roomOf(unit.last)),
      ],
  ];
}

/// An open graph on the frame side: ONE picture over its group's [lanes]
/// and the room after them, where their rows of cells would be (I-89 ③) —
/// the same widget on the timeline and, turned on its side, the sheet.
class TimelineLaneGraph extends StatelessWidget {
  const TimelineLaneGraph({
    super.key,
    required this.seat,
    required this.lanes,
    required this.grid,
    required this.frameExtent,
    required this.crossExtent,
  });

  final TimelineGraphSeat seat;

  /// The group's lanes as the rail draws them, in its order.
  final List<TimelineDisplayRow> lanes;

  /// The grid it is drawn in, read as its rows of cells read it.
  final TimelineCellsRowGrid grid;

  /// How far the picture runs along the frames.
  final double frameExtent;

  /// How far it reaches across them — its lanes and the room after them.
  final double crossExtent;

  @override
  Widget build(BuildContext context) =>
      sizedAlong(grid.axis, along: frameExtent, across: crossExtent);
}

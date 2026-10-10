import '../../models/layer.dart';
import '../../models/layer_kind.dart';
import 'lane_graph.dart';
import 'property_lane_model.dart';
import 'timeline_current_row.dart' show laneGroupOf;
import 'transform_lane_policy.dart' show transformGroupHeaderLane;

/// The key of the header graph a row HEADS (I-89 ③) — a Transform or
/// effect header's own ([PropertyLaneRow.headsAGraph]), or the camera
/// row's, the row being its own Transform group (㉙) — or null for a row
/// that heads none. [lane] is the row's lane; null asks of [layer]'s own
/// row. What a graph button turns, pressed or swept.
String? laneGraphHeadedBy(Layer layer, PropertyLaneRow? lane) {
  if (lane != null) {
    return lane.headsAGraph ? laneGroupKey(layer.id, lane.laneId) : null;
  }
  return layer.kind == LayerKind.camera
      ? laneGroupKey(layer.id, transformGroupHeaderLane.laneId)
      : null;
}

/// [rows] with every member lane of an OPEN graph seated in it — the graph
/// [open] holds for the lane's group ([laneGroupOf]).
///
/// Only a lane is seated: a header heads its graph from outside it, and the
/// rows a seat changes nothing about — what is stood on, selected and walked
/// — are the same rows (「서는곳 법 그대로」).
List<TimelineDisplayRow> seatLaneGraphs(
  List<TimelineDisplayRow> rows,
  Map<String, LaneGraph> open,
) {
  if (open.isEmpty) {
    return rows;
  }
  final lanes = <String, List<String>>{};
  for (final row in rows) {
    if (_graphKeyOf(row) case final key? when open.containsKey(key)) {
      (lanes[key] ??= []).add(row.lane!.laneId);
    }
  }
  final seats = {
    for (final MapEntry(:key, :value) in lanes.entries)
      key: TimelineGraphSeat(
        groupKey: key,
        graph: open[key]!,
        lanes: List.unmodifiable(value),
      ),
  };
  return List.unmodifiable([
    for (final row in rows)
      switch (seats[_graphKeyOf(row)]) {
        final seat? => row.seatedIn(seat),
        null => row,
      },
  ]);
}

/// The group key a lane row's graph would be keyed by, or null for a row
/// that is no member of a group.
String? _graphKeyOf(TimelineDisplayRow row) {
  final lane = row.lane;
  if (lane == null) {
    return null;
  }
  final header = laneGroupOf(lane.laneId);
  return header == null ? null : laneGroupKey(row.layer.id, header);
}

/// One open graph's run of member rows in a display-row list: where it
/// starts, how many rows it holds, and the seat they share.
typedef TimelineGraphBlock = ({int start, int count, TimelineGraphSeat seat});

/// The open graphs' blocks in [rows], in draw order — every run of rows
/// seated in one group's graph. A group's members are contiguous on both
/// grids (the x-sheet reverses the run, it never splits it).
List<TimelineGraphBlock> timelineGraphBlocks(List<TimelineDisplayRow> rows) {
  final blocks = <TimelineGraphBlock>[];
  var index = 0;
  while (index < rows.length) {
    final seat = rows[index].graph;
    if (seat == null) {
      index += 1;
      continue;
    }
    final start = index;
    while (index < rows.length &&
        rows[index].graph?.groupKey == seat.groupKey) {
      index += 1;
    }
    blocks.add((start: start, count: index - start, seat: seat));
  }
  return blocks;
}

import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/timeline_row_address.dart';
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

/// The key a row's PIN is pressed with (I-89 ③) — a lane that draws a
/// curve ([PropertyLaneRow.curve], never a header's) — or null for a row
/// that wears none. What a pin button turns, pressed or swept.
String? lanePinOf(Layer layer, PropertyLaneRow? lane) =>
    lane?.curve == null ? null : laneGroupKey(layer.id, lane!.laneId);

/// [rows] with every member lane of an OPEN graph seated in it — the graph
/// [graphs] holds open for the lane's group ([laneGroupOf]), with which of
/// the group's lanes [selection] holds and [graphs] pins.
///
/// Only a lane is seated: a header heads its graph from outside it, and the
/// rows a seat changes nothing about — what is stood on, selected and walked
/// — are the same rows (「서는곳 법 그대로」).
///
/// The graph [graphs] ENLARGES, where it is drawn, folds every other lane
/// to a thin strip — a lane of a shut group, or of another graph — and
/// every header and every layer row stand whole: the mock's 5판, whose
/// enlarged graph thins the lanes of every other group and leaves their
/// rows (「다른 행을 얇은 띠로 접어 패널 대부분을 이 그래프에 줍니다」).
List<TimelineDisplayRow> seatLaneGraphs(
  List<TimelineDisplayRow> rows,
  LaneGraphsView graphs, {
  required Set<TimelineRowAddress> selection,
}) {
  final open = graphs.open;
  if (open.isEmpty) {
    return rows;
  }
  final lanes = <String, List<TimelineDisplayRow>>{};
  for (final row in rows) {
    if (_graphKeyOf(row) case final key? when open.containsKey(key)) {
      (lanes[key] ??= []).add(row);
    }
  }
  List<String> idsOf(Iterable<TimelineDisplayRow> seated) =>
      List.unmodifiable([for (final row in seated) row.lane!.laneId]);
  final seats = {
    for (final MapEntry(:key, :value) in lanes.entries)
      key: TimelineGraphSeat(
        groupKey: key,
        graph: open[key]!,
        lanes: idsOf(value),
        picked: idsOf(value.where((row) => selection.contains(row.address))),
        pinned: idsOf(
          value.where(
            (row) => graphs.pinned.contains(
              laneGroupKey(row.layer.id, row.lane!.laneId),
            ),
          ),
        ),
        enlarged: key == graphs.enlarged,
      ),
  };
  final enlarged = seats.containsKey(graphs.enlarged);
  return List.unmodifiable([
    for (final row in rows)
      switch ((seats[_graphKeyOf(row)], row.lane)) {
        (final seat, final lane?)
            when enlarged &&
                !lane.isGroupHeader &&
                seat?.enlarged != true =>
          row.seatedIn(seat, folded: true),
        (final seat?, _) => row.seatedIn(seat),
        _ => row,
      },
  ]);
}

/// The lanes [seat]'s graph draws as its OWN (I-89 ③), as the rail draws
/// them — solid in its picture, and the rows that wear their chips.
///
/// 🗣️The mock's law (5판, 유저 2026-10-10 「서는곳 법 그대로」): the
/// group's lanes in the row selection; none of them selected, the lane
/// [standing] on, where it is one of the group's — a stood row is a
/// selection of one; stood outside the group, all of it. And every lane of
/// the group pinned to every graph, besides.
List<String> laneGraphDrawnLanes(
  TimelineGraphSeat seat,
  TimelineRowAddress? standing,
) {
  final own = seat.picked.isNotEmpty
      ? seat.picked
      : switch (standing) {
          LaneRowAddress(:final layerId, :final laneId)
              when _groupKeyOfLane(layerId, laneId) == seat.groupKey =>
            [laneId],
          _ => seat.lanes,
        };
  return [
    for (final lane in seat.lanes)
      if (own.contains(lane) || seat.pinned.contains(lane)) lane,
  ];
}

/// The group key a lane row's graph would be keyed by, or null for a row
/// that is no member of a group.
String? _graphKeyOf(TimelineDisplayRow row) {
  final lane = row.lane;
  return lane == null ? null : _groupKeyOfLane(row.layer.id, lane.laneId);
}

/// A lane as a header graph draws it (I-89 ③): its row's layer, whose
/// colour label its keys wear, and the lane.
typedef LaneGraphLine = ({Layer layer, PropertyLaneRow lane});

/// The pins [seat]'s graph draws as GUESTS (I-89 ③), dashed: every pinned
/// lane that is no member of its group — another group's, another row's —
/// in the order they were pinned. Its own group's pins are its own
/// ([laneGraphDrawnLanes]).
List<String> laneGraphGuests(TimelineGraphSeat seat, Set<String> pinned) => [
  for (final key in pinned)
    if (parseLaneGroupKey(key) case (:final layerId, :final laneId)
        when _groupKeyOfLane(layerId, laneId) != seat.groupKey)
      key,
];

/// The key of the group [laneId] is a member of on [layerId]'s row, or
/// null for a lane that is no member of a group — a header, a lane of its
/// own.
String? _groupKeyOfLane(LayerId layerId, String laneId) {
  final header = laneGroupOf(laneId);
  return header == null ? null : laneGroupKey(layerId, header);
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

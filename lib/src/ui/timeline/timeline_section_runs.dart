import 'dart:math' as math;

import '../../models/timeline_row_address.dart';
import 'lane_graph.dart' show laneGraphFoldedExtent, laneGraphMostExtent;
import 'lane_graph_seats.dart' show timelineGraphBlocks;
import 'property_lane_model.dart';
import 'timeline_grid_metrics.dart';
import 'timeline_row_edges.dart';
import 'timeline_section_policy.dart';

/// A consecutive run of display rows belonging to one timesheet section —
/// the geometry the section BRACKET wraps (the paper sheet's ACTION heading
/// enclosing its cel columns, laid along the layer axis).
///
/// Shared by both orientations (Axis rule): the horizontal timeline draws
/// runs as gutter segments beside the rail rows, the X-sheet as header
/// bands above the column headers.
class TimelineSectionRun {
  const TimelineSectionRun({
    required this.section,
    required this.startRowIndex,
    required this.rowCount,
  });

  final TimelineSection section;

  /// First display-row index of the run.
  final int startRowIndex;

  /// Number of consecutive display rows (layer + lane rows).
  final int rowCount;

  @override
  bool operator ==(Object other) =>
      other is TimelineSectionRun &&
      other.section == section &&
      other.startRowIndex == startRowIndex &&
      other.rowCount == rowCount;

  @override
  int get hashCode => Object.hash(section, startRowIndex, rowCount);

  @override
  String toString() =>
      'TimelineSectionRun(section: $section, startRowIndex: $startRowIndex, '
      'rowCount: $rowCount)';
}

/// Groups [rows] into consecutive section runs (lane rows belong to their
/// layer's section).
List<TimelineSectionRun> timelineSectionRuns(List<TimelineDisplayRow> rows) {
  final runs = <TimelineSectionRun>[];
  for (var index = 0; index < rows.length; index += 1) {
    final section = timelineSectionForLayerKind(rows[index].layer.kind);
    if (runs.isNotEmpty &&
        runs.last.section == section &&
        runs.last.startRowIndex + runs.last.rowCount == index) {
      final last = runs.removeLast();
      runs.add(
        TimelineSectionRun(
          section: last.section,
          startRowIndex: last.startRowIndex,
          rowCount: last.rowCount + 1,
        ),
      );
    } else {
      runs.add(
        TimelineSectionRun(section: section, startRowIndex: index, rowCount: 1),
      );
    }
  }
  return List.unmodifiable(runs);
}

/// Layer-axis extent of one display row: a row's height — but a row the
/// enlarged graph folds ([TimelineDisplayRow.folded]) stands as its thin
/// strip, and an open graph folded stands as ONE strip, its first lane's:
/// the mock's 5판 thins a shut group lane by lane and an open graph whole.
double timelineDisplayRowExtent(
  TimelineDisplayRow row,
  TimelineGridMetrics metrics,
) {
  if (!row.folded) {
    return metrics.layerRowHeight;
  }
  return switch (row.graph) {
    final seat? when seat.lanes.first != row.lane?.laneId => 0,
    _ => laneGraphFoldedExtent,
  };
}

/// Where [rows] sit along the layer axis — each at its own extent
/// ([timelineDisplayRowExtent]), an open graph's lanes joined into one unit
/// with its ROOM after the last of them: what the graph stands past its
/// lanes (I-89 ③).
///
/// Laid along a [view] that long, a graph stands no further than the view
/// lets one ([laneGraphMostExtent]) — the ENLARGED one exactly that far
/// (I-89 ③D), and one whose grip said more, kept, at the most: as the
/// storyboard draws a height kept above today's ceiling. A view of none is
/// no view, as it is to the row window: every graph as its grip says.
///
/// ⛔Built once per pass and handed round. Every grid surface that turns a
/// row into a place or a place into a row reads THIS, so the rail, the
/// cells, the sheet and the cursor cannot disagree about where a row is.
TimelineRowEdges timelineRowEdgesOf(
  List<TimelineDisplayRow> rows,
  TimelineGridMetrics metrics, {
  double view = 0,
}) {
  final rowExtent = metrics.layerRowHeight;
  final most = view > 0
      ? laneGraphMostExtent(view, rowExtent)
      : double.infinity;
  final slots = <TimelineRowSlot>[
    for (final row in rows)
      (
        extent: timelineDisplayRowExtent(row, metrics),
        room: 0,
        joinsNext: false,
      ),
  ];
  for (final block in timelineGraphBlocks(rows)) {
    final last = block.start + block.count - 1;
    var lanes = 0.0;
    for (var index = block.start; index <= last; index += 1) {
      lanes += slots[index].extent;
      slots[index] = (
        extent: slots[index].extent,
        room: 0,
        joinsNext: index < last,
      );
    }
    final seat = block.seat;
    final stands = switch (rows[block.start].folded) {
      true => 0.0,
      false when seat.enlarged && most.isFinite => most,
      false => math.min(seat.graph.extentAt(rowExtent), most),
    };
    slots[last] = (
      extent: slots[last].extent,
      room: math.max(0.0, stands - lanes),
      joinsNext: false,
    );
  }
  return TimelineRowEdges(slots, graphMost: most);
}

/// How many rows from [anchor] a pointer [crossOffset] from its start
/// stands over, where [edges] put [rows] ([TimelineRowEdges.rowFrom]) — 0
/// while [anchor] is not drawn. What every drag that spans rows reads: a
/// rail row's select, a cells span, a key span.
///
/// R9 #25: the gestures hand raw pixels and the grid resolves them where
/// it paints its rows. ↩️In one row height until a graph (I-89 ③) stood
/// taller than its lanes.
int timelineRowDeltaAt(
  List<TimelineDisplayRow> rows,
  TimelineRowEdges edges,
  TimelineRowAddress anchor,
  double crossOffset,
) {
  final at = rows.indexWhere((row) => row.address == anchor);
  return at < 0 ? 0 : edges.rowFrom(at, crossOffset) - at;
}

/// Layer-axis extent of one section run — its rows', and the room among
/// them ([edges] of the rows [run] was cut from).
double timelineSectionRunExtent(
  TimelineSectionRun run,
  TimelineRowEdges edges,
) =>
    edges.startOf(run.startRowIndex + run.rowCount) -
    edges.startOf(run.startRowIndex);

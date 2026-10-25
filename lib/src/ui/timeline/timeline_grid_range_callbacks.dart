import '../../models/timeline_row_address.dart';
import 'property_lane_model.dart';
import 'timeline_frame_range_gesture.dart';
import '../../models/timeline_frame_range.dart';
import 'timeline_row_edges.dart';
import 'timeline_row_span_resolver.dart';
import 'timeline_section_runs.dart' show timelineRowDeltaAt;

/// 🚨★★★ONE LAW FOR BOTH GRIDS' RANGE GESTURES.
///
/// The rail and the sheet each built the callbacks their range gesture
/// layer takes, and the two drifted the way twin lists always do: the
/// sheet's select handed the session a block-move target and nothing else,
/// while the rail's handed the head LANE and the span sliced off the rows
/// it actually drew (절대명령 2 「선택범위는 레이어 불문 자유롭게」, D42).
/// The audit's clone scan (2026-09-03) found the pair; this is the one
/// builder both grids call, so the sheet cannot fall a law behind again.
///
/// [dragRows] is a getter, not a list. 🚨Resolved against the STATE-HELD
/// rows at CALL time, never the build-local list: the cells rows are
/// MEMOIZED, a memo hit hands back the widget of an older build, and that
/// widget's gesture bundle carries these closures — capturing the list
/// froze the rows as of the build the row was cached in.
///
/// WHICH LAYER the pressed row belongs to: a lane row answers with the
/// layer it sits inside ([TimelineRowAddress.owningLayerId]). 🚨F-5 /
/// C3-lane-move: this read `row is LayerRowAddress` once, so a lane row was
/// never "inside" the selection it was visibly inside, and the press that
/// should have started a MOVE fell through to the select path and silently
/// redrew the band. Cross-row select (UI-R17 #8): the gesture's row delta
/// maps onto the display rows exactly like the move drags do.
TimelineRangeGestureCallbacks timelineGridRangeCallbacks({
  required TimelineFrameRangeHooks rangeHooks,
  required List<TimelineDisplayRow> Function() dragRows,
  required TimelineRowEdges Function() dragEdges,
  required TimelineRangeMoveRowResolver rangeMove,
  void Function(TimelineRowAddress row)? onGripTaken,
  void Function(TimelineRowAddress row)? onGripReleased,
}) {
  return TimelineRangeGestureCallbacks(
    isInSelection: (row, frameIndex) => timelineRowFrameInSelection(
      row,
      frameIndex,
      rangeHooks.selection.value,
    ),
    onSelectUpdate: (row, anchorIndex, headIndex, headCrossOffset) {
      final layerId = row.owningLayerId;
      if (layerId == null) {
        return;
      }
      final rows = dragRows();
      // R9 #25: raw pixels in, resolved where the grid paints its rows.
      final headRowDelta =
          timelineRowDeltaAt(rows, dragEdges(), row, headCrossOffset);
      final head = headRowDelta == 0
          ? null
          : resolveSelectionSpanHead(
              rows: rows,
              source: row,
              rowDelta: headRowDelta,
            );
      rangeHooks.onSelectUpdate(
        layerId,
        anchorIndex,
        headIndex,
        headLayerId: head?.layerId,
        headLaneId: head?.laneId,
        // 🚨★ THE SPAN, sliced off what this grid actually drew.
        spanRows: resolveSelectionSpanRows(
          rows: rows,
          anchor: row,
          rowDelta: headRowDelta,
        ),
      );
    },
    onTapClear: (_) => rangeHooks.onClear(),
    rowHolds: rangeMove.holdsRow,
    // A lane row begins the move of the layer it belongs to — the
    // fallback [LaneRowAddress] documents — and its rows count from it.
    // Refusing here is what made "grab the band on an fx row" do nothing
    // at all.
    onMoveBegin: (row, _) => rangeMove.begin(row),
    onMoveUpdate: rangeMove.update,
    onMoveEnd: rangeMove.end,
    onMoveCancel: rangeMove.cancel,
    // D42: EVERY range drag (select or move) takes the A5 grip — the host
    // that windows its rows pins the held one through these.
    onGripTaken: onGripTaken,
    onGripReleased: onGripReleased,
  );
}

/// The lane family's twin of [timelineGridRangeCallbacks]: one builder for
/// the callbacks a grid's lane range layer takes.
///
/// 🚨B4-④: a lane-anchored select drag that leaves its own lane group JOINS
/// the cells law above — same display-row slice, same hooks, same arguments
/// a cells anchor would report (유저: 「선택범위는 어떤 레이어를 건너든
/// 자유롭게, 규칙 두지 말 것」). Inside the group the host's lane-span path
/// keeps the drag, unchanged. One law, both axes.
///
/// [band] is the cells family's bundle the same grid built
/// ([timelineGridRangeCallbacks]): a press inside its band on a lane row is
/// the band's move (H20).
TimelineLaneRangeCallbacks timelineGridLaneRangeCallbacks({
  required TimelineLaneRangeHooks hostLaneRange,
  required TimelineFrameRangeHooks? rangeHooks,
  required List<TimelineDisplayRow> Function() dragRows,
  required TimelineRowEdges Function() dragEdges,
  TimelineRangeGestureCallbacks? band,
  void Function(TimelineRowAddress row)? onGripTaken,
  void Function(TimelineRowAddress row)? onGripReleased,
}) {
  return TimelineLaneRangeCallbacks(
    selection: hostLaneRange.selection,
    onSelectUpdate: (layerId, laneId, anchorIndex, headIndex, headCrossOffset) {
      final rows = dragRows();
      // R9 #25 on the lane family: raw pixels in, resolved the same way.
      final headRowDelta = timelineRowDeltaAt(
        rows,
        dragEdges(),
        LaneRowAddress(layerId, laneId),
        headCrossOffset,
      );
      final escalation = rangeHooks == null
          ? null
          : resolveLaneSpanEscalation(
              rows: rows,
              layerId: layerId,
              laneId: laneId,
              rowDelta: headRowDelta,
            );
      if (escalation == null) {
        // In-group: the head LANE resolves off the SAME drawn rows (C② —
        // the hosts' hand-kept lane lists retired). The addresses and the
        // head lane, each computed ONCE.
        final drawn = [for (final row in rows) row.address];
        final headLane = resolveInGroupHeadLane(
          rows: drawn,
          layerId: layerId,
          laneId: laneId,
          rowDelta: headRowDelta,
        );
        hostLaneRange.onSelectUpdate(
          layerId,
          laneId,
          anchorIndex,
          headIndex,
          // The span comes off the SAME drawn rows the head did — 절대명령
          // 2「선택범위는 레이어 불문 자유롭게」, and the reason three
          // per-family walks could go.
          laneSpanOverDrawnRows(
            rows: drawn,
            layerId: layerId,
            laneId: laneId,
            headLaneId: headLane ?? laneId,
          ),
        );
        return;
      }
      rangeHooks!.onSelectUpdate(
        layerId,
        anchorIndex,
        headIndex,
        headLayerId: escalation.headLayerId,
        headLaneId: escalation.headLaneId,
        spanRows: escalation.spanRows,
      );
    },
    onSelectRows: (rows, anchorIndex, headIndex) {
      final anchor = rows.first;
      final lanes = laneBoxLanesOf(rows);
      if (rangeHooks == null || lanes.length == rows.length) {
        hostLaneRange.onSelectUpdate(
          anchor.layerId,
          anchor.laneId,
          anchorIndex,
          headIndex,
          lanes,
        );
        return;
      }
      rangeHooks.onSelectUpdate(
        anchor.layerId,
        anchorIndex,
        headIndex,
        headLayerId: rows.last.layerId,
        headLaneId: rows.last.laneId,
        spanRows: rows,
      );
    },
    onTapAt: hostLaneRange.onTapAt,
    onActivateAt: hostLaneRange.onActivateAt,
    onTapClear: hostLaneRange.onTapClear,
    onCreateKeys: hostLaneRange.onCreateKeys,
    onMoveBegin: hostLaneRange.onMoveBegin,
    onMoveUpdate: hostLaneRange.onMoveUpdate,
    onMoveEnd: hostLaneRange.onMoveEnd,
    onMoveCancel: hostLaneRange.onMoveCancel,
    onGripTaken: onGripTaken,
    onGripReleased: onGripReleased,
    band: band,
  );
}

/// Whether the cells selection covers [row] at [frameIndex] — one law for
/// both grids: a lane row answers with the layer it sits inside
/// ([TimelineRowAddress.owningLayerId]).
///
/// ↩️F-87: the row ITSELF is asked ([TimelineFrameRangeSelection.coversRow]),
/// the law the storyboard's rail already presses by. A swept lane is inside
/// the band whether or not its layer's row was swept; a lane nobody swept
/// is not inside it because its layer's row was (H20: 「선택한 곳만」). Asked
/// through its layer, a band over an fx row and another row's cells pressed
/// on the fx row as outside — the silent re-select C3 closed.
bool timelineRowFrameInSelection(
  TimelineRowAddress row,
  int frameIndex,
  TimelineFrameRangeSelection? selection,
) =>
    selection != null &&
    selection.coversRow(row) &&
    selection.contains(frameIndex);

import '../../models/timeline_row_address.dart';
import 'property_lane_model.dart';
import 'timeline_frame_range_gesture.dart';
import '../../models/timeline_frame_range.dart';
import 'timeline_row_cross_offset.dart';
import 'timeline_row_span_resolver.dart';

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
  required double rowExtent,
  required List<TimelineDisplayRow> Function() dragRows,
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
      // R9 #25: the gesture hands raw pixels; the grid's rows are one
      // height, so the uniform resolve is right — with the heights the
      // grid paints, where they are known.
      final headRowDelta = uniformRowDeltaForCrossOffset(
        crossOffset: headCrossOffset,
        rowExtent: rowExtent,
      );
      final head = headRowDelta == 0
          ? null
          : resolveSelectionSpanHead(
              rows: rows,
              sourceLayerId: layerId,
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
    // A lane row begins the move of the layer it belongs to — the
    // fallback [LaneRowAddress] documents. Refusing here is what made
    // "grab the band on an fx row" do nothing at all.
    onMoveBegin: (row, _) {
      final layerId = row.owningLayerId;
      return layerId != null && rangeMove.begin(layerId);
    },
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
TimelineLaneRangeCallbacks timelineGridLaneRangeCallbacks({
  required TimelineLaneRangeHooks hostLaneRange,
  required TimelineFrameRangeHooks? rangeHooks,
  required double rowExtent,
  required List<TimelineDisplayRow> Function() dragRows,
  void Function(TimelineRowAddress row)? onGripTaken,
  void Function(TimelineRowAddress row)? onGripReleased,
}) {
  return TimelineLaneRangeCallbacks(
    selection: hostLaneRange.selection,
    onSelectUpdate: (layerId, laneId, anchorIndex, headIndex, headCrossOffset) {
      final rows = dragRows();
      // R9 #25 on the lane family: raw pixels in, resolved with THIS
      // grid's uniform row pitch.
      final headRowDelta = uniformRowDeltaForCrossOffset(
        crossOffset: headCrossOffset,
        rowExtent: rowExtent,
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
          headLane,
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
    onTapAt: hostLaneRange.onTapAt,
    onTapClear: hostLaneRange.onTapClear,
    onMoveBegin: hostLaneRange.onMoveBegin,
    onMoveUpdate: hostLaneRange.onMoveUpdate,
    onMoveEnd: hostLaneRange.onMoveEnd,
    onMoveCancel: hostLaneRange.onMoveCancel,
    onGripTaken: onGripTaken,
    onGripReleased: onGripReleased,
  );
}

/// Whether the cells selection covers [row] at [frameIndex] — one law for
/// both grids: a lane row answers with the layer it sits inside
/// ([TimelineRowAddress.owningLayerId]).
bool timelineRowFrameInSelection(
  TimelineRowAddress row,
  int frameIndex,
  TimelineFrameRangeSelection? selection,
) {
  final layerId = row.owningLayerId;
  return layerId != null &&
      selection != null &&
      selection.coversLayer(layerId) &&
      selection.contains(frameIndex);
}

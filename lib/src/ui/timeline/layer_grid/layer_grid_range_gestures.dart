part of '../layer_timeline_grid.dart';

/// THE RANGE GESTURES — the sweep that selects a frame range on a row or
/// a lane, and the policy that says which rows take one — as their own
/// object.
///
/// 🚨A collaborator carved out of `_LayerTimelineGridState` (the audit's
/// SRP cut, 2026-09-02). Measured before cutting: three State members
/// shared. It reaches the State through `_state`.
class _LayerGridRangeGestures {
  _LayerGridRangeGestures(this._state);

  final _LayerTimelineGridState _state;

  TimelineFrameRange get frameRangePolicy =>
      TimelineFrameRange.fromPlaybackDuration(
        playbackFrameCount: _state.widget.hooks.playbackFrameCount,
        minimumVisibleFrameCells: _state._metrics.minimumVisibleFrameCells,
      );

  /// The cells-family drag callbacks for this pass, or null when the
  /// host wired none.
  ///
  /// ⚠️It also loads `_rangeMoveResolver` with [rows], which is why it
  /// takes them rather than reading a field: the drag counts ROWS and
  /// lands on SLOTS, and only this list knows how many rows sit between
  /// two fx headers. Both happen in the same pass or neither does.
  TimelineRangeGestureCallbacks? rangeGestureFor(
    List<TimelineDisplayRow> rows,
  ) {
    final rangeHooks = _state.widget.hooks.rangeHooks;
    _state._rangeMoveResolver
      ..rows = rows
      ..session = rangeHooks?.move;
    return rangeHooks == null
        ? null
        : TimelineRangeGestureCallbacks(
            // WHICH LAYER the pressed row belongs to — a lane row answers
            // with the layer it sits inside ([TimelineRowAddress.owningLayerId]).
            //
            // 🚨F-5/C3-lane-move: this read `row is LayerRowAddress`, so a lane
            // row was never "inside" the selection it was visibly inside, and
            // the press that should have started a MOVE fell through to the
            // select path and silently redrew the band.
            isInSelection: (row, frameIndex) {
              final selection = rangeHooks.selection.value;
              final layerId = row.owningLayerId;
              return layerId != null &&
                  selection != null &&
                  selection.coversLayer(layerId) &&
                  selection.contains(frameIndex);
            },
            // Cross-row select (UI-R17 #8): the gesture's row delta maps
            // onto the display rows exactly like the move drags do.
            //
            // 🚨Resolved against the STATE-HELD [_dragRows] at CALL time,
            // never the build-local list. The cells rows are MEMOIZED: a
            // memo hit hands back the widget of an older build, and that
            // widget's gesture bundle carries THESE closures. Capturing
            // `rows` froze the row list as of the build the row was cached
            // in — twirl a lane group open and a memo-kept row's drag still
            // swept yesterday's three rows (the engine shards caught it
            // first: their tile inputs keep the memo warm). The MOVE path
            // never had the bug because [_rangeMoveResolver] is exactly
            // this pattern — one State-held object, refreshed per build.
            onSelectUpdate: (row, anchorIndex, headIndex, headCrossOffset) {
              // ⛔No kind gate on the anchor. WHICH rows a drag may sweep is
              // answered by the row LIST below and by nothing else — a test
              // here is how the transition clone and the lane rows came to
              // be unanchorable one kind at a time (유저 2026-08-12: 「헤더니까
              // 뭐 다르게한다거나 제발좀 절대로좀 그만좀하자」).
              final layerId = row.owningLayerId;
              if (layerId == null) {
                return;
              }
              // R9 #25: the gesture hands up raw pixels; this surface's
              // rows are one height (layer rows and lane rows alike), so
              // the resolve is the uniform one — the same arithmetic as
              // before, now stated where the heights are known.
              final headRowDelta = uniformRowDeltaForCrossOffset(
                crossOffset: headCrossOffset,
                rowExtent: _state._metrics.layerRowHeight,
              );
              // R27 #14: the head row may be a LANE row of the dragged
              // layer — the span then runs cell → lane → lane and stops
              // where the pointer is, instead of stepping over the whole
              // lane group to the next layer's cells.
              final head = headRowDelta == 0
                  ? null
                  : resolveSelectionSpanHead(
                      rows: _state._dragRows,
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
                  rows: _state._dragRows,
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
              return layerId != null &&
                  _state._rangeMoveResolver.begin(layerId);
            },
            onMoveUpdate: _state._rangeMoveResolver.update,
            onMoveEnd: _state._rangeMoveResolver.end,
            onMoveCancel: _state._rangeMoveResolver.cancel,
            // D42: EVERY range drag (select or move) takes the A5 grip —
            // the vertical auto-pan can slide the row window past the
            // gesture row; unpinned, a MOVE's dispose backstop commits
            // mid-drag and a SELECT's recognizer dies and the sweep
            // freezes. The pin is carved out of the spacers (O(1)); the
            // release is equality-guarded so it cannot drop a grip some
            // OTHER drag holds.
            onGripTaken: (row) => _state._heldDragRow = row,
            onGripReleased: (row) {
              if (_state._heldDragRow == row) {
                _state._heldDragRow = null;
              }
            },
          );
  }

  /// The lane-family drag callbacks for this pass, or null when the host
  /// wired none. Same display-row slice and the same hooks as the cells
  /// family above — see the comment inside.
  TimelineLaneRangeCallbacks? laneRangeFor(List<TimelineDisplayRow> rows) {
    // 🚨B4-④: a lane-anchored select drag that leaves its own lane group
    // JOINS the cells law above — same display-row slice, same hooks, same
    // arguments a cells anchor would report (유저: 「선택범위는 어떤
    // 레이어를 건너든 자유롭게, 규칙 두지 말 것」). Inside the group the
    // host's lane-span path keeps the drag, unchanged.
    final rangeHooks = _state.widget.hooks.rangeHooks;
    final hostLaneRange = _state.widget.hooks.laneRange;
    return hostLaneRange == null
        ? null
        : TimelineLaneRangeCallbacks(
            selection: hostLaneRange.selection,
            onSelectUpdate:
                (layerId, laneId, anchorIndex, headIndex, headCrossOffset) {
                  // R9 #25 on the lane family: the gesture hands raw
                  // pixels; THIS grid's rows are one height, so the
                  // uniform resolve is right — with the heights the grid
                  // paints, where they are known.
                  final headRowDelta = uniformRowDeltaForCrossOffset(
                    crossOffset: headCrossOffset,
                    rowExtent: _state._metrics.layerRowHeight,
                  );
                  // [_dragRows], not the build-local list — the same
                  // stale-closure rule as the cells handler above (lane
                  // rows are not memoized today, but the bundle they mount
                  // must not depend on that staying true).
                  final escalation = rangeHooks == null
                      ? null
                      : resolveLaneSpanEscalation(
                          rows: _state._dragRows,
                          layerId: layerId,
                          laneId: laneId,
                          rowDelta: headRowDelta,
                        );
                  if (escalation == null) {
                    // In-group: the head LANE resolves off the SAME drawn
                    // rows (C② — the hosts' hand-kept lane lists retired).
                    final drawn = [
                      for (final row in _state._dragRows) row.address,
                    ];
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
                      // The span comes off the SAME drawn rows the head
                      // did — 절대명령 2「선택범위는 레이어 불문 자유롭게」,
                      // and the reason three per-family walks could go.
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
            // D42: lane drags take the same A5 grip as the cells — a lane
            // row is a windowed display row like any other.
            onGripTaken: (row) => _state._heldDragRow = row,
            onGripReleased: (row) {
              if (_state._heldDragRow == row) {
                _state._heldDragRow = null;
              }
            },
          );
  }
}

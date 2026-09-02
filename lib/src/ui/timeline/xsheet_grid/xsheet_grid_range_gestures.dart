part of '../xsheet_timeline_grid.dart';

/// THE RANGE GESTURES — the sweep that selects a frame range on a column
/// or a lane, and the policy that says which rows take one — as their
/// own object.
///
/// 🚨A collaborator carved out of `_XSheetTimelineGridState` (the audit's
/// SRP cut, 2026-09-02). It reaches the State through `_state`.
class _XSheetGridRangeGestures {
  _XSheetGridRangeGestures(this._state);

  final _XSheetTimelineGridState _state;

  TimelineFrameRange get _frameRangePolicy =>
      TimelineFrameRange.fromPlaybackDuration(
        playbackFrameCount: _state.widget.hooks.playbackFrameCount,
        minimumVisibleFrameCells: _state._metrics.minimumVisibleFrameCells,
      );

  TimelineRangeGestureCallbacks? rangeGestureFor(
    List<TimelineDisplayRow> entries,
  ) {
    final rangeHooks = _state.widget.hooks.rangeHooks;
    _state._rangeMoveResolver
      ..rows = entries
      ..session = rangeHooks?.move;
    return rangeHooks == null
        ? null
        : TimelineRangeGestureCallbacks(
            // The horizontal grid's twin, one law: a lane row
            // answers with the layer it sits inside
            // ([TimelineRowAddress.owningLayerId]).
            isInSelection: (row, frameIndex) =>
                _state._rowFrameInSelection(row, frameIndex, rangeHooks),
            // Cross-row select (UI-R17 #8), transposed like the moves.
            //
            // 🚨[_dragRows] at CALL time, never the build-local
            // list: the cells columns are memoized, and a memo
            // hit serves an older build's gesture bundle — see
            // the horizontal grid's twin for the stale-rows bug
            // this closes.
            onSelectUpdate: (row, anchorIndex, headIndex, headCrossOffset) {
              final rowLayerId = row.owningLayerId;
              if (rowLayerId == null) {
                return;
              }
              // R9 #25: raw pixels in, resolved here — this
              // axis's columns are one width.
              final headRowDelta = uniformRowDeltaForCrossOffset(
                crossOffset: headCrossOffset,
                rowExtent: _state._metrics.layerRowHeight,
              );
              rangeHooks.onSelectUpdate(
                rowLayerId,
                anchorIndex,
                headIndex,
                headLayerId: headRowDelta == 0
                    ? null
                    : resolveBlockMoveTargetLayer(
                        rows: _state._dragRows,
                        sourceLayerId: rowLayerId,
                        rowDelta: headRowDelta,
                      ),
              );
            },
            onTapClear: (_) => rangeHooks.onClear(),
            onMoveBegin: (row, _) {
              final layerId = row.owningLayerId;
              return layerId != null &&
                  _state._rangeMoveResolver.begin(layerId);
            },
            onMoveUpdate: _state._rangeMoveResolver.update,
            onMoveEnd: _state._rangeMoveResolver.end,
            onMoveCancel: _state._rangeMoveResolver.cancel,
          );
  }

  /// The lane-family drag callbacks for this pass, or null when the host
  /// wired none. See the comment inside: one law, both axes.
  TimelineLaneRangeCallbacks? laneRangeFor(List<TimelineDisplayRow> entries) {
    // 🚨B4-④, transposed: the lane-anchored drag joins the cells
    // law the moment it leaves its own lane group — the same
    // wrap the horizontal grid applies (one law, both axes).
    final rangeHooks = _state.widget.hooks.rangeHooks;
    final hostLaneRange = _state.widget.hooks.laneRange;
    return hostLaneRange == null
        ? null
        : TimelineLaneRangeCallbacks(
            selection: hostLaneRange.selection,
            onSelectUpdate:
                (layerId, laneId, anchorIndex, headIndex, headCrossOffset) {
                  // R9 #25 on the lane family: raw pixels in,
                  // resolved with THIS grid's uniform column
                  // pitch.
                  final headRowDelta = uniformRowDeltaForCrossOffset(
                    crossOffset: headCrossOffset,
                    rowExtent: _state.widget.metrics.layerRowHeight,
                  );
                  final escalation = rangeHooks == null
                      ? null
                      : resolveLaneSpanEscalation(
                          rows: _state._dragRows,
                          layerId: layerId,
                          laneId: laneId,
                          rowDelta: headRowDelta,
                        );
                  if (escalation == null) {
                    // The rows' addresses and the head lane, each computed
                    // ONCE — the list was built three times and the head
                    // lane resolved twice per select event.
                    final addresses = [
                      for (final row in _state._dragRows) row.address,
                    ];
                    final headLane = resolveInGroupHeadLane(
                      rows: addresses,
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
                      laneSpanOverDrawnRows(
                        rows: addresses,
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
          );
  }
}

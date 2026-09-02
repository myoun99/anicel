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
        : timelineGridRangeCallbacks(
            rangeHooks: rangeHooks,
            rowExtent: _state._metrics.layerRowHeight,
            dragRows: () => _state._dragRows,
            rangeMove: _state._rangeMoveResolver,
            onGripTaken: _holdDragRow,
            onGripReleased: _releaseDragRow,
          );
  }

  /// The lane-family drag callbacks for this pass, or null when the host
  /// wired none. Same display-row slice and the same hooks as the cells
  /// family above — see the comment inside.
  TimelineLaneRangeCallbacks? laneRangeFor(List<TimelineDisplayRow> rows) {
    final hostLaneRange = _state.widget.hooks.laneRange;
    return hostLaneRange == null
        ? null
        : timelineGridLaneRangeCallbacks(
            hostLaneRange: hostLaneRange,
            rangeHooks: _state.widget.hooks.rangeHooks,
            rowExtent: _state._metrics.layerRowHeight,
            dragRows: () => _state._dragRows,
            onGripTaken: _holdDragRow,
            onGripReleased: _releaseDragRow,
          );
  }

  // D42: EVERY range drag (select or move) takes the A5 grip, and the held
  // row is PINNED in the row window while it does.
  void _holdDragRow(TimelineRowAddress row) => _state._heldDragRow = row;

  void _releaseDragRow(TimelineRowAddress row) {
    if (_state._heldDragRow == row) {
      _state._heldDragRow = null;
    }
  }
}

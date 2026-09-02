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
    // The SAME builder the rail calls — the sheet used to copy the rail's
    // callbacks and fall a law behind (no span rows, no head lane).
    return rangeHooks == null
        ? null
        : timelineGridRangeCallbacks(
            rangeHooks: rangeHooks,
            rowExtent: _state._metrics.layerRowHeight,
            dragRows: () => _state._dragRows,
            rangeMove: _state._rangeMoveResolver,
          );
  }

  /// The lane-family drag callbacks for this pass, or null when the host
  /// wired none. See the comment inside: one law, both axes.
  TimelineLaneRangeCallbacks? laneRangeFor(List<TimelineDisplayRow> entries) {
    final hostLaneRange = _state.widget.hooks.laneRange;
    return hostLaneRange == null
        ? null
        : timelineGridLaneRangeCallbacks(
            hostLaneRange: hostLaneRange,
            rangeHooks: _state.widget.hooks.rangeHooks,
            rowExtent: _state._metrics.layerRowHeight,
            dragRows: () => _state._dragRows,
          );
  }
}

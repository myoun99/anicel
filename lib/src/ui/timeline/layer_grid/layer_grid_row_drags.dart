part of '../layer_timeline_grid.dart';

/// THE ROW DRAGS — a layer row and an effect row made draggable in the
/// rail — as their own object.
///
/// 🚨A collaborator carved out of `_LayerTimelineGridState` (the audit's
/// SRP cut, 2026-09-02). It reaches the State through `_state`.
class _LayerGridRowDrags {
  _LayerGridRowDrags(this._state);

  final _LayerTimelineGridState _state;

  /// The slot is this row's place among the layer rows ON SCREEN, and the
  /// list handed to the policy is those rows' layers — see [layerRowsOf]
  /// for why it cannot be [TimelineDisplayRow.layerIndex] and
  /// `widget.layers` (F-31).
  Widget _draggable(TimelineDisplayRow row, Widget child) =>
      layerRowDragWrapper(
        row: row,
        dragRows: () => _state._dragRows,
        rowExtent: _state._metrics.layerRowHeight,
        axis: Axis.horizontal,
        hooks: _state.widget.hooks.rowDragHooks,
        onRowSelectionSpan: _state.widget.hooks.onRowSelectionSpan,
        // The held row is PINNED in the row window while its grip is taken
        // (the window would otherwise unmount it mid-drag).
        onGripTaken: () => _state._heldDragRow = row.address,
        onGripReleased: () {
          if (_state._heldDragRow == row.address) {
            _state._heldDragRow = null;
          }
        },
        child: child,
      );

  /// An fx header, made draggable: grabbing it re-orders the layer's effect
  /// CHAIN. The Transform group header is never wrapped — it is not a chain
  /// member, it is where the chain ends.
  Widget _effectDraggable(TimelineDisplayRow row, Widget child) {
    final hooks = _state.widget.hooks.rowDragHooks;
    final lane = row.lane;
    if (hooks == null || lane == null) {
      return child;
    }
    // 🚨B4-3 (유저, 몇 번째인지 세지 않겠다고 했다) — **EVERY ROW JOINS A
    // SELECTION.**
    //
    // > 「행의 **다른 fx끼리 넘어서 선택범위가 불가능.** 그 너머의 다른 행
    // > 선택해야 그때서야 가능. **이런 다른규칙 삭제좀하자고.**」
    //
    // ⛔The span resolver never had a rule about lanes — it is a plain slice
    // of the drawn row list. What was missing is WIRING: a lane row that is
    // not an fx chain header got no drag target at all, and the one that IS
    // a header was given `onCrossed` and never `onSelectCrossed`, which is
    // the only thing that grows a selection during a drag. So a span
    // anchored on a lane simply never updated, and a span anchored anywhere
    // else could not stop on one.
    //
    // ★A lane row cannot be RE-ORDERED unless it heads a chain, but every
    // row can be SELECTED. Those are two questions, and only the first one
    // ever needed an answer here — so the chain target is asked first and
    // the select-only target answers whenever it declines.
    return effectChainRowDragTarget(
          (row: row, lane: lane),
          hooks,
          (
            axis: Axis.horizontal,
            rowExtent: _state._metrics.layerRowHeight,
            dragRows: () => _state._dragRows,
            onSelectCrossed: (rowDelta) => _state
                .widget
                .hooks
                .onRowSelectionSpan
                ?.call(_state._dragRows, rowDelta),
            // The held row is PINNED in the row window while its grip is
            // taken (the window would otherwise unmount it mid-drag).
            onGripTaken: () => _state._heldDragRow = row.address,
            onGripReleased: () {
              if (_state._heldDragRow == row.address) {
                _state._heldDragRow = null;
              }
            },
          ),
          child: child,
        ) ??
        _state._lanes._laneSelectOnlyTarget(row, lane.laneId, hooks, child);
  }
}

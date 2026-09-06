part of '../layer_timeline_grid.dart';

/// THE ROW DRAGS — a rail row made draggable — as their own object.
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
  ///
  /// A LANE row (an fx chain header, a parameter lane) goes down the same
  /// wrapper: which target it gets is a question about the ROW, answered
  /// inside [layerRowDragWrapper], not about which grid is asking.
  Widget draggable(TimelineDisplayRow row, Widget child) => layerRowDragWrapper(
    row: row,
    dragRows: () => _state._dragRows,
    rowExtent: _state._metrics.layerRowHeight,
    axis: Axis.horizontal,
    hooks: _state.widget.hooks.rowDragHooks,
    onRowSelectionSpan: _state.widget.hooks.onRowSelectionSpan,
    pin: _state._heldRow,
    child: child,
  );
}

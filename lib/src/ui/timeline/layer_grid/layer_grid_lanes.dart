part of '../layer_timeline_grid.dart';

/// THE LANES — the lanes a row shows, expanding and collapsing them all,
/// and the select-only target a lane row answers — as their own object.
///
/// 🚨A collaborator carved out of `_LayerTimelineGridState` (the audit's
/// SRP cut, 2026-09-02). It reaches the State through `_state` and
/// rebuilds through `_rebuild`.
class _LayerGridLanes {
  _LayerGridLanes(this._state);

  final _LayerTimelineGridState _state;

  List<PropertyLaneRow> lanesFor(Layer layer) =>
      _state.widget.hooks.lanesForLayer?.call(layer) ?? const [];

  /// Legend LAYER-cell sweeps: the grid owns the lane knowledge (which
  /// layers HAVE lanes, which are expanded), so the all-lane fold rides its
  /// existing per-layer toggle.
  void _expandAllLanes() {
    final onToggle = _state.widget.hooks.onToggleLayerLanes;
    if (onToggle == null) {
      return;
    }
    for (final layer in _state.widget.layers) {
      if (lanesFor(layer).isNotEmpty &&
          !_state.widget.hooks.expandedLaneLayerIds.contains(layer.id)) {
        onToggle(layer.id);
      }
    }
  }

  void _collapseAllLanes() {
    final onToggle = _state.widget.hooks.onToggleLayerLanes;
    if (onToggle == null) {
      return;
    }
    for (final layerId in _state.widget.hooks.expandedLaneLayerIds.toList()) {
      onToggle(layerId);
    }
  }

  /// A lane row that heads nothing still takes part in a SELECTION — a
  /// target with no reorder to offer, only the span (B4-3).
  ///
  /// ⚠️`slotBefore` and `isLastRow` are the reorder caret's inputs and this
  /// target never fires one, so they say "this row, not the last" and stop
  /// there. `onCrossed` is a no-op for the same reason: a transform lane or
  /// an fx parameter holds no place in any list a drop could rewrite.
  Widget _laneSelectOnlyTarget(
    TimelineDisplayRow row,
    String laneId,
    TimelineRowDragHooks hooks,
    Widget child,
  ) => laneSelectOnlyDragTarget(
    (row: row, laneId: laneId),
    hooks,
    (axis: Axis.horizontal, rowExtent: _state._metrics.layerRowHeight),
    onSelectCrossed: _state.widget.hooks.onRowSelectionSpan == null
        ? null
        : (rowDelta) => _state.widget.hooks.onRowSelectionSpan!(
            _state._dragRows,
            rowDelta,
          ),
    child: child,
  );
}

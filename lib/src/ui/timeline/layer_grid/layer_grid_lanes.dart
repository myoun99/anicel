part of '../layer_timeline_grid.dart';

/// THE LANES — the lanes a row shows, and expanding and collapsing them
/// all — as their own object.
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
}

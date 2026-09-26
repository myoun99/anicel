part of '../xsheet_timeline_grid.dart';

/// THE COLUMN HEADERS — a layer's header across the top of the sheet, a
/// lane's, their natural extents, and the draggable header the rail
/// reorders with — as their own object.
///
/// 🚨A collaborator carved out of `_XSheetTimelineGridState` (the audit's
/// SRP cut, 2026-09-02). It reaches the State through `_state`.
class _XSheetGridHeaders {
  _XSheetGridHeaders(this._state);

  final _XSheetTimelineGridState _state;

  /// The header block's NATURAL extent for this sheet — what the stood-up
  /// rail costs laid out in full. The window never changes it.
  double get _naturalHeaderBlockExtent =>
      XSheetTimelineGrid.naturalHeaderBlockExtent(
        hasOnionColumn: _state.widget.hooks.onToggleLayerOnionSkin != null,
        hasBlendColumn: _state.widget.hooks.onLayerBlendModeSelected != null,
        columns: _state.widget.metrics.railColumns,
      );

  /// Just the column headers — the band strip has its own row above.
  double get naturalHeaderExtent =>
      _naturalHeaderBlockExtent - XSheetTimelineGrid._sectionBandHeight;

  /// One column header, made draggable along the sheet's own axis. A layer
  /// header moves the layer; an fx group header re-orders that layer's
  /// chain; every other lane header takes the span and nothing else
  /// (members do not move — the user's rule).
  ///
  /// A5-4 / F-16 / F-31: the SAME function the rail calls — the sheet used
  /// to copy its shape and drift behind it. It copied the LANE half too,
  /// and drifted there in exactly the same way (round 8), so the routing
  /// itself is the shared law now: the sheet only says which axis it is.
  ///
  /// The sheet lists the stack RAW where the rail reverses it, and the
  /// chain the other way round from the rail — neither is stated here.
  /// Both are inferred by the policy from the lists themselves.
  Widget draggableHeader(TimelineDisplayRow entry, Widget child) =>
      layerRowDragWrapper(
        row: entry,
        dragRows: () => _state._dragRows,
        rowExtent: _state._metrics.layerRowHeight,
        axis: Axis.vertical,
        hooks: _state.widget.hooks.rowDragHooks,
        onRowSelectionSpan: _state.widget.hooks.onRowSelectionSpan,
        // ⚠️No A5 grip pin here: this grid's LayerRailWindow is a paint
        // clip and the sheet builds every row, so nothing can unmount a
        // held column mid-drag (see [HeldRowPin]).
        child: child,
      );

  Widget _laneHeader(TimelineDisplayRow entry) {
    return ValueListenableBuilder<int>(
      valueListenable: _state.widget.hooks.frameCursor,
      builder: (context, cursorFrame, _) => TimelineDragPreviewRowGate(
        dragPreview: _state.widget.hooks.dragPreview,
        layer: entry.layer,
        rowBuilder: (context, layer) => TimelineLaneControlsRow(
          axis: Axis.vertical,
          keyPrefix: 'xsheet',
          layer: layer,
          lane: previewedLaneRow(
            row: entry,
            previewLayer: layer,
            lanesForLayer: _state._lanesFor,
          ),
          metrics: _state._metrics,
          width: _state._metrics.layerRowHeight,
          // Laid out at the natural extent like every other header; the
          // rail window above is what cuts it.
          height: naturalHeaderExtent,
          currentFrameIndex: cursorFrame,
          onSelectFrame: _state.widget.hooks.onSelectFrame,
          laneEdit: _state.widget.hooks.laneEdit,
          onToggleLaneGroup: _state.widget.hooks.onToggleLaneGroup,
          onToggleLaneGroupEnabled:
              _state.widget.hooks.onToggleLaneGroupEnabled,
          onResetLaneGroup: _state.widget.hooks.onResetLaneGroup,
          currentRowHooks: _state.widget.hooks.currentRowHooks,
          // The SAME flags the layer's own column header passes, so a
          // group header's fx lands in the sheet's fx row (R5 #7).
          hasOnionColumn: _state.widget.hooks.onToggleLayerOnionSkin != null,
          hasBlendColumn: _state.widget.hooks.onLayerBlendModeSelected != null,
        ),
      ),
    );
  }

  /// The header column for one display row: a lane's, or the layer's.
  Widget headerFor(TimelineDisplayRow entry) =>
      entry.isLane ? _laneHeader(entry) : _layerHeaderFor(entry);

  /// The layer header, fed the row's live facts the same way the rail row
  /// is (fx, onion, solo, arrow, lanes, fold).
  Widget _layerHeaderFor(TimelineDisplayRow entry) {
    final layer = entry.layer;
    final fold = _state._groupFoldFor(entry);
    final hooks = _state.widget.hooks;
    return TimelineLayerControlsRow(
      axis: Axis.vertical,
      keyPrefix: 'xsheet',
      mainExtent: naturalHeaderExtent,
      depth: entry.depth,
      onSettledPress: hooks.onSettledPress,
      labelDoubleClick: hooks.labelDoubleClick,
      linkPartners: hooks.layerLinkPartnersOf?.call(layer.id) ?? const [],
      opacityOverride: hooks.layerOpacityOverrideOf?.call(layer.id),
      onToggleLayerOnionSkin: hooks.onToggleLayerOnionSkin,
      onionSkinEnabled: hooks.layerOnionSkinEnabledOf?.call(layer.id) ?? false,
      onLayerBlendModeSelected: hooks.onLayerBlendModeSelected,
      wearsBaseComposite: attachRowWearsBaseComposite(
        layer,
        _state.widget.layers,
      ),
      layer: layer,
      active: layer.id == hooks.activeLayerId,
      // ⑨ · T1
      selected: hooks.selectedRows.contains(LayerRowAddress(layer.id)),
      metrics: _state._metrics,
      onSelectLayer: hooks.onSelectLayer,
      onToggleLayerVisibility: hooks.onToggleLayerVisibility,
      onLayerOpacityChanged: hooks.onLayerOpacityChanged,
      onLayerOpacityChangeEnd: hooks.onLayerOpacityChangeEnd,
      opacityDragPreview: hooks.opacityDragPreview,
      onToggleLayerTimesheet: hooks.onToggleLayerTimesheet,
      fxState: hooks.layerFxStateOf?.call(layer.id) ?? LayerFxState.on,
      onToggleLayerFx: hooks.onToggleLayerFx,
      onLayerMarkSelected: hooks.onLayerMarkSelected,
      onToggleLayerFillReference: hooks.onToggleLayerFillReference,
      onOpenLayerMixer: hooks.onOpenLayerMixer,
      onOpenLayerReference: hooks.onOpenLayerReference,
      isReferenceSourceShort:
          hooks.layerSourceIsShortOf?.call(layer.id) ?? false,
      attachArrowPlacement: hooks.attachArrowPlacementOf?.call(layer.id),
      isLayerSoloed: hooks.isLayerSoloed?.call(layer.id) ?? false,
      hasLanes: _state._lanesFor(layer).isNotEmpty,
      lanesExpanded: hooks.expandedLaneLayerIds.contains(layer.id),
      onToggleLanes: hooks.onToggleLayerLanes,
      // One fold twirl — the rail's rule, the rail's function.
      hasGroupFold: fold.has,
      groupFoldExpanded: fold.expanded,
      onToggleGroupFold: fold.onToggle,
    );
  }
}

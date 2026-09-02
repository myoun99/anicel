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
      );

  /// Just the column headers — the band strip has its own row above.
  double get naturalHeaderExtent =>
      _naturalHeaderBlockExtent - XSheetTimelineGrid._sectionBandHeight;

  /// One column header, made draggable along the sheet's own axis. A layer
  /// header moves the layer; an fx group header re-orders that layer's
  /// chain; every other lane header passes through untouched (members do
  /// not move — the user's rule).
  ///
  /// The sheet lists the stack RAW where the rail reverses it, and the
  /// chain the other way round from the rail — neither is stated here.
  /// Both are inferred by the policy from the lists themselves.
  Widget draggableHeader(TimelineDisplayRow entry, Widget child) {
    final hooks = _state.widget.hooks.rowDragHooks;
    if (hooks == null) {
      return child;
    }
    final lane = entry.lane;
    if (lane == null) {
      // A5-4 / F-16: **같은 함수**가 답한다 — x시트가 가로 레일의 모양을
      // 베껴서 같은 버그를 갖고 있던 자리다.
      final unmovable = unmovableRowSelectTarget(
        kind: entry.layer.kind,
        layerId: entry.layer.id,
        rowExtent: _state._metrics.layerRowHeight,
        axis: Axis.vertical,
        hooks: hooks,
        onSelectCrossed: (rowDelta) => _state.widget.hooks.onRowSelectionSpan
            ?.call(_state._dragRows, rowDelta),
        child: child,
      );
      if (unmovable != null) {
        return unmovable;
      }
      // F-31, transposed: the sheet counts the COLUMNS on screen, through
      // the same object the rail counts its rows with.
      final caret = LayerRowCaret.of(_state._dragRows, entry.layer.id);
      if (caret == null) {
        return child;
      }
      return LayerRowDragTarget(
        subject: LayerRowSubject(entry.layer.id),
        slotBefore: caret.slot,
        rowExtent: _state._metrics.layerRowHeight,
        axis: Axis.vertical,
        hooks: hooks,
        isLastRow: caret.isLastRow,
        // R5 #15: the sheet's columns take the ON-COLUMN drop the way the
        // rail's rows do — the band is measured along whichever axis this
        // surface runs, so the transposition costs nothing.
        onCrossed: (steps, onRow, inRow) {
          final slot = caret.slotFor(steps);
          final target = caret.onRowLayer(onRow);
          if (target != null) {
            hooks.onRowTarget(caret.layers, slot, target.id);
            return;
          }
          hooks.onUpdate(
            caret.layers,
            slot,
            pointerInRow: caret.onRowLayer(inRow)?.id,
          );
        },
        // ⑨: the SELECT half, counted in the sheet's own display columns.
        onSelectCrossed: hooks.onSelectBegin == null
            ? null
            : (rowDelta) => _state.widget.hooks.onRowSelectionSpan?.call(
                _state._dragRows,
                rowDelta,
              ),
        child: child,
      );
    }
    // 🚨B4-3: the same wiring the horizontal rail got. A lane row cannot be
    // RE-ORDERED unless it heads a chain, but every row can be SELECTED —
    // two questions, and only the first one ever needed an answer here.
    Widget selectOnly() {
      if (hooks.onSelectBegin == null ||
          _state.widget.hooks.onRowSelectionSpan == null) {
        return child;
      }
      return LayerRowDragTarget(
        subject: LaneRowSubject(entry.layer.id, lane.laneId),
        slotBefore: entry.layerIndex,
        rowExtent: _state._metrics.layerRowHeight,
        axis: Axis.vertical,
        hooks: hooks,
        isLastRow: false,
        onCrossed: (_, _, _) {},
        onSelectCrossed: (rowDelta) => _state.widget.hooks.onRowSelectionSpan
            ?.call(_state._dragRows, rowDelta),
        child: child,
      );
    }

    if (!lane.isGroupHeader) {
      return selectOnly();
    }
    final parsed = parseEffectLaneId(lane.laneId);
    if (parsed == null || parsed.parameterId != null) {
      return selectOnly();
    }
    final headers = effectHeaderRowsOf(_state._dragRows, entry.layer.id);
    final slot = headers.indexWhere((h) => h.effectId == parsed.effectId);
    if (slot < 0) {
      return selectOnly();
    }
    final myRowIndex = headers[slot].rowIndex;
    return LayerRowDragTarget(
      subject: EffectRowSubject(entry.layer.id, parsed.effectId),
      slotBefore: slot,
      rowExtent: _state._metrics.layerRowHeight,
      axis: Axis.vertical,
      hooks: hooks,
      isLastRow: slot == headers.length - 1,
      onCrossed: (steps, _, _) => hooks.onEffectUpdate(
        entry.layer.id,
        [for (final header in headers) header.effectId],
        slotForSteps(
          slot,
          rowStepsBetween(
            [for (final header in headers) header.rowIndex],
            myRowIndex,
            steps,
          ),
          headers.length,
        ),
      ),
      // B4-3: the SELECT half, the same one every other row already had.
      onSelectCrossed: hooks.onSelectBegin == null
          ? null
          : (rowDelta) => _state.widget.hooks.onRowSelectionSpan?.call(
              _state._dragRows,
              rowDelta,
            ),
      child: child,
    );
  }

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
    return TimelineLayerControlsRow(
      axis: Axis.vertical,
      keyPrefix: 'xsheet',
      mainExtent: naturalHeaderExtent,
      depth: entry.depth,
      onSettledPress: _state.widget.hooks.onSettledPress,
      isLinked: _state.widget.hooks.layerIsLinkedOf?.call(layer.id) ?? false,
      opacityOverride: _state.widget.hooks.layerOpacityOverrideOf?.call(
        layer.id,
      ),
      onToggleLayerOnionSkin: _state.widget.hooks.onToggleLayerOnionSkin,
      onionSkinEnabled:
          _state.widget.hooks.layerOnionSkinEnabledOf?.call(layer.id) ?? false,
      onLayerBlendModeSelected: _state.widget.hooks.onLayerBlendModeSelected,
      blendLanguage: _state.widget.hooks.blendLanguage,
      wearsBaseComposite: attachRowWearsBaseComposite(
        layer,
        _state.widget.layers,
      ),
      layer: layer,
      active: layer.id == _state.widget.hooks.activeLayerId,
      // ⑨ · T1
      selected: _state.widget.hooks.selectedRows.contains(
        LayerRowAddress(layer.id),
      ),
      metrics: _state._metrics,
      onSelectLayer: _state.widget.hooks.onSelectLayer,
      onToggleLayerVisibility: _state.widget.hooks.onToggleLayerVisibility,
      onLayerOpacityChanged: _state.widget.hooks.onLayerOpacityChanged,
      onLayerOpacityChangeEnd: _state.widget.hooks.onLayerOpacityChangeEnd,
      opacityDragPreview: _state.widget.hooks.opacityDragPreview,
      onToggleLayerTimesheet: _state.widget.hooks.onToggleLayerTimesheet,
      fxState:
          _state.widget.hooks.layerFxStateOf?.call(layer.id) ?? LayerFxState.on,
      onToggleLayerFx: _state.widget.hooks.onToggleLayerFx,
      onLayerMarkSelected: _state.widget.hooks.onLayerMarkSelected,
      onToggleLayerFillReference:
          _state.widget.hooks.onToggleLayerFillReference,
      onOpenLayerMixer: _state.widget.hooks.onOpenLayerMixer,
      attachArrowPlacement: _state.widget.hooks.attachArrowPlacementOf?.call(
        layer.id,
      ),
      isLayerSoloed: _state.widget.hooks.isLayerSoloed?.call(layer.id) ?? false,
      hasLanes: _state._lanesFor(layer).isNotEmpty,
      lanesExpanded: _state.widget.hooks.expandedLaneLayerIds.contains(
        layer.id,
      ),
      onToggleLanes: _state.widget.hooks.onToggleLayerLanes,
      // One fold twirl — the rail's rule, the rail's function.
      hasGroupFold: fold.has,
      groupFoldExpanded: fold.expanded,
      onToggleGroupFold: fold.onToggle,
    );
  }
}

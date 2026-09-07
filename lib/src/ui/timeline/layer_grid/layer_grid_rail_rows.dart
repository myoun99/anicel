part of '../layer_timeline_grid.dart';

/// THE RAIL ROWS — the layer controls rail the grid shows beside its
/// cells: each row memoised on its inputs, the legend header, the fold a
/// group carries, which row is active and selected, and the row at a rail
/// position — as their own object.
///
/// 🚨A collaborator carved out of `_LayerTimelineGridState` (the audit's
/// SRP cut, 2026-09-02). Measured before cutting: twelve members of its
/// own and four State members shared. It reaches the State through
/// `_state` and rebuilds through `_rebuild`.
class _LayerGridRailRows {
  _LayerGridRailRows(this._state);

  final _LayerTimelineGridState _state;

  LayerRailExtent get _railExtent =>
      _state.widget.railExtent ??
      (_state._ownedRailExtent ??= LayerRailExtent());

  /// The rail's NATURAL extent — what it costs laid out in full. The
  /// window never changes it; that is the whole point of the model.
  double get naturalRailWidth => _state._metrics.layerControlsWidth;

  /// Resolves a rail-local vertical position to the row there — LANE ROWS
  /// INCLUDED. Spacer gaps and positions past the window return null.
  ///
  /// The ROW rather than its layer, because a swipe needs its DEPTH: the
  /// leading columns sit after the folder indent, so their x is a function
  /// of the row (I-1).
  ///
  /// 🚨IT USED TO EXCLUDE LANE ROWS, and that rule had a source and an
  /// expiry. `git log -S` puts it in c07cfa40 (#509), when the sweep was
  /// THE EYE AND NOTHING ELSE — lane rows carry no eye, so skipping them
  /// was right. The sweep later widened to columns (I-1) and lane rows grew
  /// an fx toggle of their own, and the exclusion outlived its reason: a
  /// sweep down the fx column stepped over every lane row it crossed while
  /// the code's own rule said only rows with NO control in a column are
  /// skipped. 유저 2026-08-29: 「버튼이면 다 가능하도록」.
  ///
  /// ⚠️The uniform division holds for lane rows too — measured, both are
  /// 28.0 tall and meet with no gap.
  TimelineDisplayRow? _rowAtRailY(
    double localY,
    List<TimelineDisplayRow> windowRows,
    double leadingSpacerHeight,
  ) {
    final indexInWindow =
        ((localY - leadingSpacerHeight) / _state._metrics.layerRowHeight)
            .floor();
    if (indexInWindow < 0 || indexInWindow >= windowRows.length) {
      return null;
    }
    return windowRows[indexInWindow];
  }

  // ⛔"Which DISPLAY row the selection sits on" was written out here — a
  // second copy of [indexOfDisplayRow], which the ↑/↓ walk and the flip HUD
  // already read. The reveal asks that one now (round 8's grid
  // unification), so the rail and the walks can no longer disagree about
  // where the selection is.

  /// The memo gate for [_railRow] (UI-R7 #1): a controls row whose inputs
  /// match hands back the CACHED widget instance — a zoom step (or any
  /// rebuild that didn't touch the row) skips its whole Material subtree.
  /// Lane label rows stay unmemoized: they subscribe to the frame cursor
  /// themselves and their lane models churn identity per build.
  /// R28 #11: ONE selection — and now there is only one THING that can be
  /// selected. A folder is a layer, so `activeLayerId` answers for both
  /// and two rows can no longer read as selected at once by construction.
  bool _layerRowIsActive(Layer layer) =>
      layer.id == _state.widget.hooks.activeLayerId;

  Widget _railRowMemoized(TimelineDisplayRow row) {
    if (row.isLane) {
      return _state._rowDrags._effectDraggable(row, _railRow(row));
    }
    final fold = _groupFoldFor(row);
    final inputs = (
      layer: ControlsRowFace(row.layer),
      active: _layerRowIsActive(row.layer),
      selected: _state.widget.hooks.selectedRows.contains(row.address),
      hasLanes: _state._lanes.lanesFor(row.layer).isNotEmpty,
      lanesExpanded: _state.widget.hooks.expandedLaneLayerIds.contains(
        row.layer.id,
      ),
      depth: row.depth,
      hasGroupFold: fold.has,
      groupFoldExpanded: fold.expanded,
      fxState:
          _state.widget.hooks.layerFxStateOf?.call(row.layer.id) ??
          LayerFxState.on,
      onionSkinEnabled:
          _state.widget.hooks.layerOnionSkinEnabledOf?.call(row.layer.id) ??
          false,
      isLinked:
          _state.widget.hooks.layerIsLinkedOf?.call(row.layer.id) ?? false,
      // Solo is SESSION state, not a Layer field, so the layer comparison
      // cannot see it: the speaker's accent tint went stale the moment
      // solo moved anywhere but this row. It has always been shown here —
      // R10 R3 only made it settable from every rail, which is what turned
      // a latent staleness into one a user would hit.
      soloed: _state.widget.hooks.isLayerSoloed?.call(row.layer.id) ?? false,
      // The arrow reads the STACK (a folder's direction is its position
      // against its base), so the Layer comparison cannot see it change.
      attachArrow: _state.widget.hooks.attachArrowPlacementOf?.call(
        row.layer.id,
      ),
      layerRowHeight: _state._metrics.layerRowHeight,
      layerControlsWidth: _state._metrics.layerControlsWidth,
      sectionLabelGutterWidth: _state._metrics.sectionLabelGutterWidth,
      opacityDragPreview: ByIdentity(_state.widget.hooks.opacityDragPreview),
      blendLanguage: _state.widget.hooks.blendLanguage,
    );
    final cached = _state._railRowMemo[row.layer.id];
    if (cached != null && cached.inputs == inputs) {
      return _state._rowDrags._draggable(row, cached.row);
    }
    final built = _railRow(row);
    _state._railRowMemo[row.layer.id] = (inputs: inputs, row: built);
    return _state._rowDrags._draggable(row, built);
  }

  /// The rail row's element key — ONE builder for the window loop and the
  /// A5 pin site, so the two can never drift and the pinned element
  /// re-matches the same State when the window returns.
  ValueKey<String> _railRowKey(TimelineDisplayRow row) => ValueKey<String>(
    'timeline-rail-row-'
    '${row.layer.id}-'
    '${row.isFolder ? 'folder-${row.layer.id}' : row.lane?.laneId ?? 'row'}',
  );

  /// The legend header's memo gate (UI-R7 #1): rebuilt only when a
  /// legend-visible fact changes — zoom steps and unrelated session
  /// notifies reuse the instance, skipping its ~15 tooltip/flyout cells.
  Widget legendHeaderMemoized(List<TimelineDisplayRow> rows) {
    final displayedIds = _state._displayedLayerIds(rows);
    final inputs = (
      layerRowHeight: _state._metrics.layerRowHeight,
      layerControlsWidth: _state._metrics.layerControlsWidth,
      hasLegend: _state.widget.legend != null,
      hiddenSections: BySet(_state.widget.hooks.hiddenSections),
      rowFilter: _state.widget.hooks.rowFilter,
      marksInUse: BySet(_state._marksInUse()),
      kindsInUse: BySet(_state._kindsInUse()),
      visibilitySoloEnabled: _state.widget.visibilitySoloEnabled,
      anyLanesExpanded: _state.widget.hooks.expandedLaneLayerIds.isNotEmpty,
      allSeMuted: _state._allSeMuted(),
      displayedIds: BySet(displayedIds),
      masterOpacityValue: _state.widget.masterOpacityValue,
      hasLaneToggles: _state.widget.hooks.onToggleLayerLanes != null,
      displayedOnionSkinOn: _state.widget.displayedOnionSkinOn,
      blendLanguage: _state.widget.hooks.blendLanguage,
      hasBlendBulk: _state.widget.legend?.onSetBlendModeForDisplayed != null,
    );
    final cached = _state._legendHeaderMemo;
    if (cached != null && cached.inputs == inputs) {
      return cached.header;
    }
    final header = TimelineLayerControlsHeader(
      metrics: _state._metrics,
      legend: _state.widget.legend,
      hiddenSections: _state.widget.hooks.hiddenSections,
      onToggleSection: _state.widget.onToggleSection,
      rowFilter: _state.widget.hooks.rowFilter,
      marksInUse: inputs.marksInUse.value,
      kindsInUse: inputs.kindsInUse.value,
      visibilitySoloEnabled: _state.widget.visibilitySoloEnabled,
      anyLanesExpanded: inputs.anyLanesExpanded,
      allSeMuted: inputs.allSeMuted,
      // The fresh set is captured here — the token's BySet invalidates
      // the cached header whenever the displayed rows change.
      displayedLayerIds: () => displayedIds,
      displayedOpacity: _state.widget.masterOpacityValue,
      displayedOnionSkinOn: _state.widget.displayedOnionSkinOn,
      onExpandAllLanes: _state.widget.hooks.onToggleLayerLanes == null
          ? null
          : _state._lanes._expandAllLanes,
      onCollapseAllLanes: _state.widget.hooks.onToggleLayerLanes == null
          ? null
          : _state._lanes._collapseAllLanes,
      blendLanguage: _state.widget.hooks.blendLanguage,
    );
    _state._legendHeaderMemo = (inputs: inputs, header: header);
    return header;
  }

  /// One rail row (layer controls or a lane label), extracted so the
  /// windowed rail loop stays readable. Rows reserve an empty leading
  /// section slot — the section ZONES overlay whole runs (UI-R7 #2).
  Widget _railRow(TimelineDisplayRow row) {
    if (row.isLane) {
      // Lane labels show the value AT the cursor: subscribe here so a
      // tick rebuilds only these small cells.
      //
      // R10: and through the drag gate, so the blue value column follows a
      // key move per step. The band moved live while the number beside it
      // still read the committed track — the label is where you WATCH the
      // value, so it is the half that most needed to be live.
      return ValueListenableBuilder<int>(
        valueListenable: _state.widget.hooks.frameCursor,
        builder: (context, cursorFrame, _) => TimelineDragPreviewRowGate(
          dragPreview: _state.widget.hooks.dragPreview,
          layer: row.layer,
          rowBuilder: (context, layer) => TimelineLaneControlsRow(
            layer: layer,
            lane: previewedLaneRow(
              row: row,
              previewLayer: layer,
              lanesForLayer: _state._lanes.lanesFor,
            ),
            metrics: _state._metrics,
            currentFrameIndex: cursorFrame,
            onSelectFrame: _state.widget.hooks.onSelectFrame,
            laneEdit: _state.widget.hooks.laneEdit,
            onToggleLaneGroup: _state.widget.hooks.onToggleLaneGroup,
            onToggleLaneGroupEnabled:
                _state.widget.hooks.onToggleLaneGroupEnabled,
            onResetLaneGroup: _state.widget.hooks.onResetLaneGroup,
            currentRowHooks: _state.widget.hooks.currentRowHooks,
            leadingInset: layerSectionLabelSlotWidth,
            // The SAME flags the layer row below passes, so a group
            // header's fx lands in the layer rows' fx column (R5 #7).
            hasOnionColumn: _state.widget.hooks.onToggleLayerOnionSkin != null,
            hasBlendColumn:
                _state.widget.hooks.onLayerBlendModeSelected != null,
          ),
        ),
      );
    }
    final fold = _groupFoldFor(row);
    return TimelineLayerControlsRow(
      layer: row.layer,
      wearsBaseComposite: attachRowWearsBaseComposite(
        row.layer,
        _state.widget.layers,
      ),
      active: _layerRowIsActive(row.layer),
      // ⑨: in the row selection the row verbs act on.
      selected: _state.widget.hooks.selectedRows.contains(row.address),
      metrics: _state._metrics,
      onSelectLayer: _state.widget.hooks.onSelectLayer,
      // T10: the rail row and the frame cells take the SAME settled-tap
      // clear, because 「행이든 뭐든 동일하게」.
      onSettledPress: _state.widget.hooks.onSettledPress,
      onToggleLayerVisibility: _state.widget.hooks.onToggleLayerVisibility,
      onLayerOpacityChanged: _state.widget.hooks.onLayerOpacityChanged,
      onLayerOpacityChangeEnd: _state.widget.hooks.onLayerOpacityChangeEnd,
      onToggleLayerTimesheet: _state.widget.hooks.onToggleLayerTimesheet,
      fxState:
          _state.widget.hooks.layerFxStateOf?.call(row.layer.id) ??
          LayerFxState.on,
      onToggleLayerFx: _state.widget.hooks.onToggleLayerFx,
      onionSkinEnabled:
          _state.widget.hooks.layerOnionSkinEnabledOf?.call(row.layer.id) ??
          false,
      onToggleLayerOnionSkin: _state.widget.hooks.onToggleLayerOnionSkin,
      onLayerMarkSelected: _state.widget.hooks.onLayerMarkSelected,
      onToggleLayerFillReference:
          _state.widget.hooks.onToggleLayerFillReference,
      onOpenLayerMixer: _state.widget.hooks.onOpenLayerMixer,
      isLayerSoloed:
          _state.widget.hooks.isLayerSoloed?.call(row.layer.id) ?? false,
      attachArrowPlacement: _state.widget.hooks.attachArrowPlacementOf?.call(
        row.layer.id,
      ),
      hasLanes: _state._lanes.lanesFor(row.layer).isNotEmpty,
      lanesExpanded: _state.widget.hooks.expandedLaneLayerIds.contains(
        row.layer.id,
      ),
      onToggleLanes: _state.widget.hooks.onToggleLayerLanes,
      depth: row.depth,
      // One fold twirl: a folder folds its members, an attach base folds
      // its attach rows — the one answer both grids ask for.
      hasGroupFold: fold.has,
      groupFoldExpanded: fold.expanded,
      onToggleGroupFold: fold.onToggle,
      opacityDragPreview: _state.widget.hooks.opacityDragPreview,
      isLinked:
          _state.widget.hooks.layerIsLinkedOf?.call(row.layer.id) ?? false,
      onLayerBlendModeSelected: _state.widget.hooks.onLayerBlendModeSelected,
      blendLanguage: _state.widget.hooks.blendLanguage,
      opacityOverride: _state.widget.hooks.layerOpacityOverrideOf?.call(
        row.layer.id,
      ),
    );
  }

  /// The row's fold twirl — [timelineGroupFoldFor] bound to this grid's hooks.
  TimelineGroupFold _groupFoldFor(TimelineDisplayRow row) =>
      timelineGroupFoldFor(
        row: row,
        layers: _state.widget.layers,
        collapsedAttachBaseIds: _state.widget.hooks.collapsedAttachBaseIds,
        onToggleLayerCollapsed: _state.widget.hooks.onToggleLayerCollapsed,
        onToggleAttachGroup: _state.widget.hooks.onToggleAttachGroup,
      );

  /// The rail column: every layer row is its controls, inside the window
  /// the splitter sizes.
  ///
  /// One of the four slots `TimelineLayerFrameBodyLayout` lays out. It
  /// takes the row window as ONE value rather than the seven locals it
  /// unpacks below — that is what [_RowWindow] is for, and unpacking under
  /// the same names is what lets the tree below move verbatim.
  Widget buildLayerControlsRail(
    ColorScheme colorScheme,
    List<TimelineDisplayRow> rows,
    double? availableRailExtent,
    _RowWindow window,
    List<RailToggleColumn<TimelineDisplayRow>> swipeColumns,
  ) {
    final rowWindow = window.range;
    final windowRows = window.rows;
    final leadingRowSpacerHeight = window.leadingSpacerHeight;
    final trailingRowSpacerHeight = window.trailingSpacerHeight;
    final pinnedIndex = window.pinnedIndex;
    final pinnedBefore = window.pinnedBefore;
    final pinnedAfter = window.pinnedAfter;
    return LayerRailWindow(
      axis: Axis.horizontal,
      rail: _railExtent,
      naturalExtent: naturalRailWidth,
      availableExtent: availableRailExtent,
      child: KeyedSubtree(
        key: const ValueKey<String>('timeline-layer-controls-rail'),
        child: KeyedSubtree(
          key: const ValueKey<String>('timeline-layer-rows-scroll-body'),
          // Sections live INSIDE the rows
          // (UI-R5) as run-spanning ZONES
          // (UI-R7 #2): the rows reserve the
          // leading slot, the zone overlay
          // paints the old gutter bracket
          // over it.
          child: RailColumnSwipe<TimelineDisplayRow>(
            axis: Axis.vertical,
            columns: swipeColumns,
            rowAt: (localY) {
              final row = _rowAtRailY(
                localY,
                windowRows,
                leadingRowSpacerHeight,
              );
              return row == null
                  ? null
                  : (
                      row: row,
                      depth: row.depth,
                      // A lane row and its
                      // owner share a layer,
                      // so the sweep dedupes
                      // by BOTH.
                      id:
                          '${row.layer.id.value}'
                          '/${row.lane?.laneId ?? ''}',
                    );
            },
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The rail is windowed
                    // with the same
                    // layer-axis slice as the
                    // frame rows; keys keep
                    // row state glued to its
                    // layer through window
                    // shifts.
                    // A5: a
                    // pinned
                    // (held)
                    // row is
                    // carved
                    // out of
                    // its
                    // spacer —
                    // total
                    // extent is
                    // unchanged.
                    if (pinnedBefore) ...[
                      if (pinnedIndex > 0)
                        SizedBox(
                          height: pinnedIndex * _state._metrics.layerRowHeight,
                        ),
                      KeyedSubtree(
                        key: _railRowKey(rows[pinnedIndex]),
                        child: _railRowMemoized(rows[pinnedIndex]),
                      ),
                      if (rowWindow.startIndex - pinnedIndex - 1 > 0)
                        SizedBox(
                          height:
                              (rowWindow.startIndex - pinnedIndex - 1) *
                              _state._metrics.layerRowHeight,
                        ),
                    ] else if (leadingRowSpacerHeight > 0)
                      SizedBox(height: leadingRowSpacerHeight),
                    for (final row in windowRows)
                      KeyedSubtree(
                        key: _railRowKey(row),
                        child: _railRowMemoized(row),
                      ),
                    if (pinnedAfter) ...[
                      if (pinnedIndex - rowWindow.endIndexExclusive > 0)
                        SizedBox(
                          height:
                              (pinnedIndex - rowWindow.endIndexExclusive) *
                              _state._metrics.layerRowHeight,
                        ),
                      KeyedSubtree(
                        key: _railRowKey(rows[pinnedIndex]),
                        child: _railRowMemoized(rows[pinnedIndex]),
                      ),
                      if (rows.length - pinnedIndex - 1 > 0)
                        SizedBox(
                          height:
                              (rows.length - pinnedIndex - 1) *
                              _state._metrics.layerRowHeight,
                        ),
                    ] else if (trailingRowSpacerHeight > 0)
                      SizedBox(height: trailingRowSpacerHeight),
                    if (_state.widget.layers.isEmpty)
                      SizedBox(
                        width:
                            _state._metrics.layerControlsWidth -
                            _state._metrics.sectionLabelGutterWidth,
                        height: _state._metrics.layerRowHeight,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            AppText.strings.tlNoLayers,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                // The section ZONES over the
                // rows' reserved band slots
                // (UI-R7 #2): the old gutter
                // bracket inside the rows.
                // Full rows, not the window
                // (A3) — labels anchor to the
                // section's true extent.
                Positioned(
                  left: 0,
                  top: 0,
                  child: _state._sectionBandOverlay(rows),
                ),
                // T1's one band
                // per contiguous
                // run — but only
                // over the LAYER
                // area (A2
                // 2026-08-17
                // reversed T1's
                // full-width
                // call): the
                // section zone
                // is the
                // sections' own
                // plate, not
                // part of the
                // selection.
                Positioned(
                  left: layerSectionLabelSlotWidth,
                  top: 0,
                  right: 0,
                  bottom: 0,
                  child: TimelineRowSelectionBands(
                    selectedFlags: [
                      for (final row in windowRows)
                        _state.widget.hooks.selectedRows.contains(row.address),
                    ],
                    rowExtent: _state._metrics.layerRowHeight,
                    leadingSpacer: leadingRowSpacerHeight,
                    crossExtent:
                        _state._metrics.layerControlsWidth -
                        layerSectionLabelSlotWidth,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

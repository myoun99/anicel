part of '../storyboard_panel.dart';

/// THE ROWS AND THEIR LABELS — the SE and transition label rows, the
/// transition strip row, and the draggable versions of the track-effect
/// and SE rows — as their own object.
///
/// 🚨A collaborator carved out of `_StoryboardPanelState` (the audit's SRP
/// cut, 2026-09-02). It reaches the State through `_state`.
class _StoryboardRowsAndLabels {
  _StoryboardRowsAndLabels(this._state);

  final _StoryboardPanelState _state;

  /// The V row's fx label rows, with each GROUP HEADER made draggable so the
  /// chain can be re-ordered here (the layer rail's gesture, one level up).
  ///
  /// The pointer counts LANE rows and the chain counts HEADERS, and the two
  /// differ the moment a group is twirled open — which is exactly when
  /// someone reaches for the order. [effectStepsBetween] converts, the same
  /// way the timeline's rail does it.
  List<Widget> draggableTrackEffectRows(Track track, List<Widget> rows) {
    final hooks = _state.widget.rowDragHooks;
    final lanes = _state._railRows._trackEffectLanes(track);
    if (hooks == null || lanes.length != rows.length) {
      return rows;
    }
    final carrierId = trackTransformLaneCarrierId(track.id);
    final headers = <({int rowIndex, EffectId effectId})>[];
    for (var index = 0; index < lanes.length; index += 1) {
      final parsed = parseEffectLaneId(lanes[index].laneId);
      if (parsed != null && parsed.parameterId == null) {
        headers.add((rowIndex: index, effectId: parsed.effectId));
      }
    }
    final displayEffects = [for (final header in headers) header.effectId];
    return [
      for (var index = 0; index < rows.length; index += 1)
        () {
          final parsed = parseEffectLaneId(lanes[index].laneId);
          final slot = parsed == null || parsed.parameterId != null
              ? -1
              : displayEffects.indexOf(parsed.effectId);
          if (slot < 0) {
            return rows[index]; // A parameter lane is not a handle.
          }
          return LayerRowDragTarget(
            subject: EffectRowSubject(carrierId, parsed!.effectId),
            slotBefore: slot,
            rowExtent: _state._rowHeights.lane,
            axis: Axis.horizontal,
            hooks: hooks,
            grip: () => [effectRowDragChip(lanes[index])],
            isLastRow: slot == displayEffects.length - 1,
            onCrossed: (steps, _, _) => hooks.onEffectUpdate(
              carrierId,
              displayEffects,
              slotForSteps(
                slot,
                rowStepsBetween(
                  [for (final header in headers) header.rowIndex],
                  index,
                  steps,
                ),
                displayEffects.length,
              ),
            ),
            child: rows[index],
          );
        }(),
    ];
  }

  /// Lane rail label rows on the shared substrate — an S row's lanes
  /// ([_StoryboardRailRows._seLanes]) or a V row's fx chain
  /// ([_StoryboardRailRows._trackEffectLanes]): the group headers plus the
  /// twirled-open member lanes, storyboard-prefixed. [active] gates the
  /// navigator's frame jumps and value edits.
  List<Widget> laneLabels({
    required Layer carrier,
    required List<PropertyLaneRow> lanes,
    required PropertyLaneEditCallbacks? laneEdit,
    required bool active,

    /// The group each header twirls, per LANE: a list's headers do not share
    /// one (an S row's groups key by [laneGroupKey], the V row's effect chain
    /// by effect).
    required String Function(PropertyLaneRow lane) groupKeyOf,
    ValueListenable<int?>? frameCursor,
    ValueChanged<int>? onSelectFrame,

    /// The header's own ON/OFF switch (AE's per-effect eyeball). Null leaves
    /// the glyph inert. ↩️「which is what a Transform header wants here」 held
    /// until F-101 gave the S rows the timeline's switch.
    void Function(PropertyLaneRow lane)? onToggleGroupEnabled,

    /// The header's RESET (R5, AE's group Reset). Null hides the button —
    /// a header whose group has no reset route must not show one.
    void Function(PropertyLaneRow lane)? onResetGroup,
  }) {
    final laneHeight = _state._rowHeights.lane;
    final metrics = TimelineGridMetrics(
      frameCellWidth: _state.widget.pixelsPerFrame,
      layerRowHeight: laneHeight - 2,
      railColumns: layerRailColumnWidthsIn(_state.context),
    );
    final onToggleGroup = _state.widget.onToggleTransformGroup;
    Widget row(PropertyLaneRow lane, int frameIndex) => TimelineLaneControlsRow(
      layer: carrier,
      lane: lane,
      metrics: metrics,
      width: _state._naturalRailWidth,
      height: laneHeight,
      currentFrameIndex: frameIndex,
      onSelectFrame: active
          ? onSelectFrame
          : null,
      laneEdit: lane.isGroupHeader || !active ? null : laneEdit,
      onToggleLaneGroup: onToggleGroup == null
          ? null
          : (_, _) => onToggleGroup(groupKeyOf(lane)),
      onToggleLaneGroupEnabled: onToggleGroupEnabled == null
          ? null
          : (_, _) => onToggleGroupEnabled(lane),
      onResetLaneGroup: onResetGroup == null || !lane.isGroupHeader
          ? null
          : (_, _) => onResetGroup(lane),
      keyPrefix: 'storyboard',
      leadingInset: layerSectionLabelSlotWidth,
      currentRowHooks: _state.widget.currentRowHooks,
    );

    // The track's rows — V and S alike, their keys are the track's — pass the
    // GLOBAL playhead (R4b). ↩️The S rows passed the ACTIVE cut's local cursor
    // until F-102, which put their values and keys at the wrong frame in any
    // cut but the first. Either way the row SUBSCRIBES, so a committed seek
    // rebuilds these label cells and nothing else (the timeline rail's own
    // line).
    return [
      for (final lane in lanes)
        if (frameCursor == null)
          row(lane, 0)
        else
          ValueListenableBuilder<int?>(
            valueListenable: frameCursor,
            builder: (context, frameIndex, _) => row(lane, frameIndex ?? 0),
          ),
    ];
  }

  Widget seLabelRow(Track track, int slot) {
    final trackLayer = _trackSeAt(track, slot);
    return _draggableSeRow(track, slot, trackLayer, _seLabel(track, slot));
  }

  /// The transition row's rail label — the timeline row's chrome (sheet,
  /// mark, eye — B5③) and no creation verb of its own. Everything else this
  /// row can do is already a gesture on the strip (grips size the span, a
  /// press opens its term dialog) or the shared Edit Instance verb, which
  /// creates on an empty frame.
  Widget transitionLabelRow(Track track) {
    final layer = track.transitionLayer;
    return _StoryboardTransitionLabel(
      track: track,
      layer: layer,
      active: _state.widget.selectedRow == LayerRowAddress(layer.id),
      height: _state._rowHeights.transition,
      onSelectLayer: _state.widget.onSelectLayer,
      onToggleLayerVisibility: _state.widget.onToggleLayerVisibility,
      onLayerMarkSelected: _state.widget.onLayerMarkSelected,
      onToggleLayerTimesheet: _state.widget.onToggleLayerTimesheet,
    );
  }

  /// The transition row's strip: the track's spans on the GLOBAL axis, live
  /// through the session's edge-drag form while a grip is held.
  Widget transitionStripRow(Track track, double width, TimelineScale scale) {
    final committed = track.transitionLayer;
    final height = _state._rowHeights.transition;
    Widget row(Layer layer) => _StoryboardTransitionRow(
      track: track,
      layer: layer,
      width: width,
      height: height,
      timelineScale: scale,
      defById: _state.widget.transitionDefById,
      crossingTooltip: _state.widget.transitionCrossingTooltip,
      commaDrag: _state.widget.transitionCommaDrag,
      onRowFramePress: _state.widget.onRowFramePress,
      onEditSpan: _state.widget.onEditTransitionSpan,
      // The SE rows' selection bundle, unchanged: one rail, one range verb.
      select: _state.widget.seSelect,
      railRowAt: (anchorRow, crossOffset) =>
          _state._railRows._railRowAtCrossOffset(
            track: track,
            anchorRow: anchorRow,
            crossOffset: crossOffset,
          ),
    );
    // The SE strips' gate, as is: a grip or a move publishes the row's two
    // forms on the one channel, and this strip — the track axis — draws the
    // GLOBAL one while the cut's rows draw the projection.
    return TimelineDragPreviewRowGate(
      dragPreview: _state.widget.dragPreview,
      layer: committed,
      useGlobalForm: true,
      rowBuilder: (context, layer) => row(layer),
    );
  }

  Widget _draggableSeRow(Track track, int slot, Layer? trackLayer, Widget row) {
    final hooks = _state.widget.rowDragHooks;
    // No active-cut gate: an S row is a TRACK fixture and re-orders its
    // own track's list, so which cut is open has nothing to say about it
    // (user, 2026-08-09: "S행은 V랑 관련없이 독립적으로 움직일 수 있어야
    // 해"). The gate guarded a session that committed to the SELECTED
    // track; the commit resolves the row's own track now.
    if (hooks == null || trackLayer == null) {
      return row;
    }
    // The rail lists the slots it SHOWS top-down — the track's list
    // reversed, less the rows the filter hides, as the timeline's display
    // rows leave them out; `modelInsertionForSlot` infers the rest from the
    // two lists.
    final displayRows = [
      for (final shown in _state._railRows._shownSeSlots(track))
        ?_trackSeAt(track, shown),
    ];
    final displayIndex = displayRows.indexWhere(
      (layer) => layer.id == trackLayer.id,
    );
    return LayerRowDragTarget(
      subject: LayerRowSubject(trackLayer.id),
      slotBefore: displayIndex,
      rowExtent: _state._railRows._seRowGroupExtent(track, slot),
      axis: Axis.horizontal,
      hooks: hooks,
      grip: () => layerRowDragChips(
        rows: _state._railRows._seRowsInDisplayOrder(track),
        pressed: trackLayer.id,
        hooks: hooks,
      ),
      isLastRow: displayIndex == displayRows.length - 1,
      // The S rows are a flat SE list — no row here holds another, so there
      // is nothing for an on-row drop to mean and the caret stays the only
      // answer (R5 #15).
      onCrossed: (steps, _, _) => hooks.onUpdate(
        displayRows,
        slotForSteps(displayIndex, steps, displayRows.length),
      ),
      // 🚨A5-3② — the SELECT half of the same drag, which this rail simply
      // did not have. ⑨'s law is that the first drag SELECTS and a drag
      // starting INSIDE the selection moves; without these the press went
      // straight to the move here while the timeline made you select first,
      // and 「통일이 안 돼 있다」 was exactly that.
      onSelectCrossed: _state.widget.onSeRowSelectionSpan == null
          ? null
          : (rowDelta) => _state.widget.onSeRowSelectionSpan!(
              _state._railRows._seRowsInDisplayOrder(track),
              rowDelta,
            ),
      child: row,
    );
  }

  Widget _seLabel(Track track, int slot) {
    final trackLayer = _trackSeAt(track, slot);
    return _StoryboardSeLabel(
      track: track,
      slot: slot,
      height: _state._rowHeights.se,
      active:
          trackLayer != null &&
          _state.widget.selectedRow == LayerRowAddress(trackLayer.id),
      onSelectLayer: _state.widget.onSelectLayer,
      laneExpanded: _state.widget.expandedSeAudioRows.contains(
        StoryboardPanel.seRowKey(track, slot),
      ),
      onToggleLane: _state.widget.onToggleSeRowLane == null
          ? null
          : () => _state.widget.onToggleSeRowLane!(track, slot),
      activeLayer: _activeSlotLayerOf(track, _state.widget.activeCutId, slot),
      onToggleLayerVisibility: _state.widget.onToggleLayerVisibility,
      onOpenLayerMixer: _state.widget.onOpenLayerMixer,
      isLayerSoloed: _state.widget.isLayerSoloed,
      onLayerOpacityChanged: _state.widget.onLayerOpacityChanged,
      onLayerOpacityChangeEnd: _state.widget.onLayerOpacityChangeEnd,
      onLayerMarkSelected: _state.widget.onLayerMarkSelected,
      onToggleLayerTimesheet: _state.widget.onToggleLayerTimesheet,
      layerFxStateOf: _state.widget.layerFxStateOf,
      onToggleLayerFx: _state.widget.onToggleLayerFx,
      opacityDragPreview: _state.widget.opacityDragPreview,
    );
  }

  /// The V row, made draggable to re-order the project's TRACKS (R5 #9).
  ///
  /// The rail lists tracks in the project's own order (the caller walks
  /// `project.tracks` forward), so the row index IS the slot before it and
  /// nothing has to be reversed the way the S rows' list does.
  ///
  /// ⚠️ The pitch is THIS group's height, so tracks of differing heights
  /// drift after the first step — the same limitation the S rows have when
  /// their lanes are open, and the same fix (a per-row extent list on the
  /// shared drag widget) would close both.
  Widget trackDraggable(Track track, int index, Widget child) {
    final hooks = _state.widget.rowDragHooks;
    final trackCount = _state.widget.project.tracks.length;
    if (hooks == null || hooks.onTrackUpdate == null || trackCount < 2) {
      // One track cannot be re-ordered, and a rail with no hooks is
      // display-only — either way the row stays a plain label.
      return child;
    }
    return LayerRowDragTarget(
      subject: TrackRowSubject(track.id),
      slotBefore: index,
      rowExtent: _state._railRows._trackGroupExtent(track),
      // ④: the handle is the V row, the pitch is the whole group — so the
      // drag is told how far into the group the handle starts.
      grabOffsetWithinRun: _state._railRows._trackGroupExtentAboveVRow(track),
      axis: Axis.horizontal,
      hooks: hooks,
      grip: () => [(icon: _vRowGlyph, label: _vRowName(index))],
      isLastRow: index == trackCount - 1,
      // A track holds nothing, so its middle means nothing: the caret is
      // the only answer and the on-row arm stays unused (the S rows'
      // reasoning, one list up).
      onCrossed: (steps, _, _) =>
          hooks.onTrackUpdate!(slotForSteps(index, steps, trackCount)),
      child: child,
    );
  }
}

/// A V row's name and glyph — what its label row shows, and what its chip
/// says once the row is picked up (I-39), so the two cannot name the row
/// differently.
String _vRowName(int index) => 'V${index + 1}';
const IconData _vRowGlyph = Icons.movie_outlined;

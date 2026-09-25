part of '../xsheet_timeline_grid.dart';

/// THE COLUMNS — the sheet's columns, one per displayed row: which column
/// is at an x, the swipe columns the rail sweeps, the gate a column
/// passes, and building them — as their own object.
///
/// 🚨A collaborator carved out of `_XSheetTimelineGridState` (the audit's
/// SRP cut, 2026-09-02). It reaches the State through `_state`.
class _XSheetGridColumns {
  _XSheetGridColumns(this._state);

  final _XSheetTimelineGridState _state;

  /// The layer columns a STRETCH of strip-local x covers — the x-sheet's
  /// answer to the rail's "which rows did the sweep pass over" (F-66; why
  /// a stretch rather than a point is in [RailColumnSwipe.rowsIn]).
  ///
  /// 🚨THE UNIFORM STRIP, which is the rail's own walk ([uniformRailRowsIn])
  /// — every column header is one [TimelineGridMetrics.layerRowHeight] wide,
  /// lane columns included, and this sheet IS the rail turned on its side.
  /// ⛔So the division is not written here a second time; what is this
  /// grid's own is only what a column at an index is. [origin] is 0 because
  /// the strip starts at its own edge, unlike the rail's spacer.
  ///
  /// A LANE column is still IN the list — it carries none of these toggles,
  /// so the column itself reads null and the sweep steps over it, exactly
  /// as it does for the rail's lane rows.
  List<RailSwipeRow<TimelineDisplayRow>> columnsIn(
    double fromX,
    double toX,
    List<TimelineDisplayRow> entries,
  ) => uniformRailRowsIn<TimelineDisplayRow>(
    from: fromX,
    to: toX,
    origin: 0,
    pitch: _state._metrics.layerRowHeight,
    count: entries.length,
    rowAt: (index) => (
      row: entries[index],
      depth: entries[index].depth,
      id: entries[index].address,
    ),
  );

  /// The sweepable columns — ONE list for both grids ([timelineSwipeColumns]),
  /// laid on the header's own extent: the rail's row width turned on its side
  /// (the slot skeleton lays these cells with `axis: Axis.vertical`, so a
  /// slot's WIDTH is its height here).
  List<RailToggleColumn<TimelineDisplayRow>> swipeColumns() =>
      timelineSwipeColumns(
        hooks: _state.widget.hooks,
        crossExtent: _state._headers.naturalHeaderExtent,
        leadingOrigin: 0,
        columns: _state.widget.metrics.railColumns,
      );

  Widget _gatedColumn(
    TimelineDisplayRow entry,
    TimelineVisibleRange frameRange,
    TimelineVirtualizationPlan plan,
    double viewportExtent,
  ) {
    return RepaintBoundary(
      key: ValueKey<String>(
        'xsheet-column-${entry.layer.id}-${entry.lane?.laneId ?? 'cells'}',
      ),
      child: TimelineDragPreviewRowGate(
        dragPreview: _state.widget.hooks.dragPreview,
        layer: entry.layer,
        rowBuilder: (context, layer) =>
            _columnFor(entry, layer, frameRange, plan, viewportExtent),
      ),
    );
  }

  Widget _columnFor(
    TimelineDisplayRow entry,
    Layer layer,
    TimelineVisibleRange frameRange,
    TimelineVirtualizationPlan plan,
    double viewportExtent,
  ) {
    // Recorded for the window, which is recomputed on bucket crossings —
    // outside any build.
    _state._frameViewportExtent = viewportExtent;
    if (entry.isLane) {
      return laneIsSeAudio(entry.lane!)
          ? SeAudioLaneFrameRow(
              axis: Axis.vertical,
              keyPrefix: 'xsheet',
              layer: layer,
              frameStartIndex: frameRange.startIndex,
              frameEndIndexExclusive: frameRange.endIndexExclusive,
              leadingFrameSpacerWidth: plan.leadingFrameSpacerWidth,
              trailingFrameSpacerWidth: plan.trailingFrameSpacerWidth,
              metrics: _state._metrics,
              frameRate: _state.widget.hooks.projectFrameRate,
              audioPeaksFor: _state.widget.hooks.audioPeaksFor,
              spillInLeadFrames:
                  _state.widget.hooks.spillInLeadFrames[entry.layer.id],
              onSetClipOffset:
                  _state.widget.hooks.audioLane?.onSetClipOffset == null
                  ? null
                  : (clipIndex, offsetFrames) =>
                        _state.widget.hooks.audioLane!.onSetClipOffset!(
                          entry.layer.id,
                          clipIndex,
                          offsetFrames,
                        ),
              offsetDrag: _state.widget.hooks.audioLane?.offsetDrag,
              onSetClipFades:
                  _state.widget.hooks.audioLane?.onSetClipFades == null
                  ? null
                  : (clipIndex, fadeIn, fadeOut) =>
                        _state.widget.hooks.audioLane!.onSetClipFades!(
                          entry.layer.id,
                          clipIndex,
                          fadeIn,
                          fadeOut,
                        ),
            )
          : TimelineLaneFrameRow(
              axis: Axis.vertical,
              keyPrefix: 'xsheet',
              layer: layer,
              // R10: the previewed lane while a key drag is in flight —
              // the same re-derivation the horizontal body does.
              lane: previewedLaneRow(
                row: entry,
                previewLayer: layer,
                lanesForLayer: _state._lanesFor,
              ),
              frameStartIndex: frameRange.startIndex,
              frameEndIndexExclusive: frameRange.endIndexExclusive,
              leadingFrameSpacerWidth: plan.leadingFrameSpacerWidth,
              trailingFrameSpacerWidth: plan.trailingFrameSpacerWidth,
              metrics: _state._metrics,
              // The LANE selection domain (UI-R23 #3 part 2) — EVERY row's
              // lanes now, camera included (2026-08-08; see the rail's
              // twin for why it stood down and why the reason was wrong).
              // Through the B4-④ escalation wrap, like the horizontal grid.
              laneRange: _state._laneRange,
            );
    }
    // PRO-TIMELINE scrolling (UI-R15→R16, transposed): the cells column
    // gets FULL bounds — its painter windows itself off the quantized
    // bucket (repaint per span crossing), so the bucket pass diffs
    // identical params and records nothing; the sparse widget-cell kinds
    // re-window internally under the same bucket.
    return TimelineFrameCellsRow(
      axis: Axis.vertical,
      keyPrefix: 'xsheet',
      onActivateCell: _state.widget.hooks.onActivateCell,
      instructionDefById: _state.widget.hooks.instructionDefById,
      instructionCrossingTooltip:
          _state.widget.hooks.instructionCrossingTooltip,
      audioPeaksFor: _state.widget.hooks.audioPeaksFor,
      projectFrameRate: _state.widget.hooks.projectFrameRate,
      showSeconds: _state.widget.hooks.showSeconds,
      audioLane: _state.widget.hooks.audioLane,
      onDropMediaAssetOnLayer: _state.widget.hooks.onDropMediaAssetOnLayer,
      acceptsMediaAssetOnLayer: _state.widget.hooks.acceptsMediaAssetOnLayer,
      onHoverMediaAssetOnLayer: _state.widget.hooks.onHoverMediaAssetOnLayer,
      onLeaveMediaAssetOnLayer: _state.widget.hooks.onLeaveMediaAssetOnLayer,
      // The sheet shows what the timeline shows: a file held over a column
      // draws the cells it would author there. ⛔Not the sheet's own rule —
      // the same span off the same channel, resolved by the same function.
      silhouette: timelineDragSilhouetteFor(
        _state.widget.hooks.dragPreview?.value,
        layer.id,
      ),
      seClipMarkerTooltip: _state.widget.hooks.seClipMarkerTooltip,
      spillInLeadFrames: _state.widget.hooks.spillInLeadFrames[layer.id],
      layer: layer,
      baseLayer: entry.layer,
      playbackFrameCount: _state.widget.hooks.playbackFrameCount,
      geometry: _state._frameScroll.publishFrameGeometry(layer.kind),
      crossAxisExtent: _state._metrics.layerRowHeight,
      windowBucket: _state._frameWindowBucket,
      viewportMainExtent: viewportExtent,
      exposureStateForLayer: _state.widget.hooks.exposureStateForLayer,
      frameNameForLayer: _state.widget.hooks.frameNameForLayer,
      celContent: _state.widget.hooks.celContent,
      onSelectLayer: _state.widget.hooks.onSelectLayer,
      onSelectFrame: _state.widget.hooks.onSelectFrame,
      onSettledPress: _state.widget.hooks.onSettledPress,
      commaDrag: _state.widget.hooks.commaDrag,
      rangeGesture: _state._rangeGesture,
      runEdit: _state.widget.hooks.runEdit,
      substrateGeneration: _state.widget.hooks.substrateGeneration,
      // The CAMERA column's union key markers (B4) — the shared lane key
      // marker code, resolved per rebuild like the lanes are.
      unionLane: _state.widget.hooks.unionLaneForLayer?.call(layer),
    );
  }

  /// One column per display row. A RepaintBoundary per column (mirrors the
  /// horizontal rows): the cursor layer repaints alone on ticks. The gate
  /// inside makes an edge-drag step rebuild exactly the dragged layer's
  /// column.
  Widget buildColumns(
    List<TimelineDisplayRow> entries,
    TimelineVirtualizationPlan plan,
    double bodyViewportHeight,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < entries.length; index += 1)
          _gatedColumn(
            entries[index],
            plan.frameRange,
            plan,
            bodyViewportHeight,
          ),
      ],
    );
  }
}

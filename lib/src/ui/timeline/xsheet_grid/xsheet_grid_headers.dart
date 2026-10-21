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
        optionalColumns: _state.widget.hooks.optionalRailColumns,
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
        dragEdges: () => _state._dragEdges,
        axis: Axis.vertical,
        hooks: _state.widget.hooks.rowDragHooks,
        onRowSelectionSpan: _state.widget.hooks.onRowSelectionSpan,
        // ⚠️No A5 grip pin here: this grid's LayerRailWindow is a paint
        // clip and the sheet builds every row, so nothing can unmount a
        // held column mid-drag (see [HeldRowPin]).
        child: child,
      );

  /// One lane's HEADER cell — the transposed rail row. R10 adds the drag
  /// gate for the same reason the horizontal rail has it: the blue value
  /// column must follow a key move per step, not sit on the committed
  /// track until the pointer lifts.
  Widget _laneHeader(TimelineDisplayRow entry) {
    // The header subscribes to the cursor itself, on a layer of its own
    // ([TimelineLaneControlsRow]).
    return TimelineDragPreviewRowGate(
      dragPreview: _state.widget.hooks.dragPreview,
      layer: entry.layer,
      slice: (layer) => laneRowSlice(layer, entry.lane!.laneId),
      rowBuilder: (context, layer) => TimelineLaneControlsRow(
        axis: Axis.vertical,
        keyPrefix: 'xsheet',
        layer: layer,
        lane: previewedLaneRow(
          row: entry,
          previewLayer: layer,
          lanesForLayer: _state.widget.hooks.lanesOf,
        ),
        metrics: _state._metrics,
        width: timelineDisplayRowExtent(entry, _state._metrics),
        // Laid out at the natural extent like every other header; the
        // rail window above is what cuts it.
        height: naturalHeaderExtent,
        frameCursor: _state.widget.hooks.frameCursor,
        onSelectFrame: _state.widget.hooks.onSelectFrame,
        laneEdit: _state.widget.hooks.laneEdit,
        onToggleLaneGroup: _state.widget.hooks.onToggleLaneGroup,
        onToggleLaneGroupEnabled: _state.widget.hooks.onToggleLaneGroupEnabled,
        onResetLaneGroup: _state.widget.hooks.onResetLaneGroup,
        currentRowHooks: _state.widget.hooks.currentRowHooks,
        // The SAME answer the layer's own column header reads, so a
        // group header's fx lands in the sheet's fx row (R5 #7).
        optionalColumns: _state.widget.hooks.optionalRailColumns,
        laneGraphs: _state.widget.hooks.laneGraphs,
        laneGraphVerbs: _state.widget.hooks.laneGraphVerbs,
        seat: entry.graph,
        folded: entry.folded,
      ),
    );
  }

  /// [entry]'s column header, draggable. A LAYER's is kept while nothing
  /// it is built from changed — the rail's memo, turned on its side
  /// ([KeptLayerControlsRows], F-244): a commit rebuilt every header of
  /// the sheet. A lane's is built every pass.
  Widget header(TimelineDisplayRow entry) {
    if (entry.isLane) {
      return draggableHeader(entry, _laneHeader(entry));
    }
    final grid = _controlsRowGrid;
    final fold = _state._groupFoldFor(entry);
    final facts = layerControlsRowFacts(
      entry,
      grid,
      fold: fold,
      hasLanes: _state.widget.hooks.lanesOf(entry.layer).isNotEmpty,
    );
    final drag = layerRowDragInputs(
      row: entry,
      drawnRows: _state._dragRows,
      hooks: grid.hooks.rowDragHooks,
      onRowSelectionSpan: grid.hooks.onRowSelectionSpan,
    );
    return _kept.keep(
      _state._berths,
      entry,
      (facts: facts, drag: drag),
      () => layerControlsRowFrom(facts, entry, grid, fold),
    );
  }

  late final KeptLayerControlsRows _kept = KeptLayerControlsRows(
    draggableHeader,
  );

  /// Every column's [header] where [edges] puts it — the room after a
  /// graph's last lane left empty, and a column of no extent no box, as
  /// the rail leaves them (I-89 ③) — each in its column's BERTH.
  List<Widget> headers(
    List<TimelineDisplayRow> entries,
    TimelineRowEdges edges,
  ) => [
    for (var index = 0; index < entries.length; index += 1) ...[
      if (edges.extentOf(index) > 0)
        KeyedSubtree(
          key: _state._berths.keyOf(entries[index]),
          child: header(entries[index]),
        ),
      if (edges.roomOf(index) > 0) SizedBox(width: edges.roomOf(index)),
    ],
  ];

  /// The header strip as its controls rows see it: the rail's record,
  /// turned on its side — each header laid out at the strip's natural
  /// extent, which the rail window above then cuts.
  LayerControlsRowGrid get _controlsRowGrid => (
    hooks: _state.widget.hooks,
    layers: _state.widget.layers,
    metrics: _state._metrics,
    axis: Axis.vertical,
    keyPrefix: 'xsheet',
    mainExtent: naturalHeaderExtent,
  );
}

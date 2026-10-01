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

  /// One column: a layer of its own size, and in it the row's gate — an
  /// edge-drag step re-runs the builder with the preview layer substituted
  /// for the drag target's column only. A layer's CELLS column is kept
  /// while nothing it is built from changed ([keptTimelineCellsRow] — the
  /// timeline's rows' memo, F-244); a lane's is built every pass.
  Widget _gatedColumn(
    TimelineDisplayRow entry,
    TimelineVirtualizationPlan plan,
    TimelineCellsRowGrid grid,
  ) {
    // 🚨F-244: a layer of the column's own size, as the horizontal rows have
    // — a drag step rebuilds the dragged column in ITS scope, not the grid's.
    // The box is laid FRESH on every pass, outside the kept column: a zoom
    // step moves its extent and keeps the column.
    return SizedBox(
      key: ValueKey<String>(
        'xsheet-column-${entry.layer.id}-${entry.lane?.laneId ?? 'cells'}',
      ),
      width: timelineDisplayRowExtent(entry, _state._metrics),
      height: plan.totalFrameContentWidth,
      child: entry.isLane
          ? timelineGatedRow(
              entry,
              grid.hooks.dragPreview,
              (context, layer) =>
                  timelineLaneRowFrom(entry, layer, grid, _laneSpan(plan)),
            )
          : keptTimelineCellsRow(_kept, entry, grid),
    );
  }

  final Map<LayerId, KeptTimelineCellsRow> _kept = {};

  /// The frames the sheet lays its lane columns over — its plan's window
  /// and room — and their selection domain ([timelineLaneRowFrom]).
  TimelineLaneRowSpan _laneSpan(TimelineVirtualizationPlan plan) => (
    startIndex: plan.frameRange.startIndex,
    endIndexExclusive: plan.frameRange.endIndexExclusive,
    leadingSpacer: plan.leadingFrameSpacerWidth,
    trailingSpacer: plan.trailingFrameSpacerWidth,
    laneRange: _state._laneRange,
  );

  /// The sheet's columns as their cells see them — the timeline's rows'
  /// record, turned on its side.
  ///
  /// PRO-TIMELINE scrolling (UI-R15→R16, transposed): the cells column
  /// gets FULL bounds — its painter windows itself off the quantized
  /// bucket (repaint per span crossing), so the bucket pass diffs
  /// identical params and records nothing; the sparse widget-cell kinds
  /// re-window internally under the same bucket.
  TimelineCellsRowGrid _cellsRowGrid(double viewportExtent) => (
    hooks: _state.widget.hooks,
    metrics: _state._metrics,
    geometry: _state._frameScroll.publishFrameGeometry(),
    windowBucket: _state._frameWindowBucket,
    viewportMainExtent: viewportExtent,
    rangeGesture: _state._rangeGesture,
    axis: Axis.vertical,
    keyPrefix: 'xsheet',
  );

  /// One column per display row. A RepaintBoundary per column (mirrors the
  /// horizontal rows): the cursor layer repaints alone on ticks. The gate
  /// inside makes an edge-drag step rebuild exactly the dragged layer's
  /// column, and a commit — or a bucket crossing — rebuilds none it did
  /// not change.
  Widget buildColumns(
    List<TimelineDisplayRow> entries,
    TimelineVirtualizationPlan plan,
    double bodyViewportHeight,
  ) {
    // Recorded for the window, which is recomputed on bucket crossings —
    // outside any build. ⚠️Before the geometry is published: the window is
    // laid over this extent.
    _state._frameViewportExtent = bodyViewportHeight;
    final grid = _cellsRowGrid(bodyViewportHeight);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in entries) _gatedColumn(entry, plan, grid),
      ],
    );
  }
}

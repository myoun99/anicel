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
  /// 🚨THE RAIL'S OWN WALK ([railRowsAlong]) — this sheet IS the rail
  /// turned on its side, [edges] its columns where the rail's are its rows.
  /// ⛔So the walk is not written here a second time; what is this grid's
  /// own is only what a column at an index is. Every column is built, so
  /// the whole strip is the window.
  ///
  /// A LANE column is still IN the list — it carries none of these toggles,
  /// so the column itself reads null and the sweep steps over it, exactly
  /// as it does for the rail's lane rows.
  List<RailSwipeRow<TimelineDisplayRow>> columnsIn(
    double fromX,
    double toX,
    List<TimelineDisplayRow> entries,
    TimelineRowEdges edges,
  ) => railRowsAlong<TimelineDisplayRow>(
    from: fromX,
    to: toX,
    edges: edges,
    built: TimelineVisibleRange(
      startIndex: 0,
      endIndexExclusive: entries.length,
    ),
    rowAt: (index) => (row: entries[index], id: entries[index].address),
  );

  /// The sweepable columns — ONE list for both grids ([timelineSwipeColumns]).
  List<RailToggleColumn<TimelineDisplayRow>> swipeColumns() =>
      timelineSwipeColumns(
        hooks: timelineRailSwipeHooks(
          _state.widget.hooks,
          _state.widget.layers,
        ),
      );

  /// One column: a layer of its own size, and in it the row's gate — an
  /// edge-drag step shows the preview layer in the drag target's column
  /// only. A layer's CELLS column is kept while its shape is what it was
  /// ([keptTimelineCellsRow] — the timeline's rows' memo, F-244); a lane's
  /// is built every pass.
  Widget _gatedColumn(
    TimelineDisplayRow entry,
    TimelineCellsRowGrid grid,
    double totalFrameContentHeight,
  ) {
    // 🚨F-244: a layer of the column's own size, as the horizontal rows have
    // — a drag step rebuilds the dragged column in ITS scope, not the grid's.
    // The box is laid FRESH on every pass, outside the kept column: a zoom
    // step moves its extent and keeps the column. Built in its BERTH and
    // named for its layer, as the timeline's rows are (I-57).
    return Named(
      'xsheet-column-${entry.layer.id}-${entry.lane?.laneId ?? 'cells'}',
      key: _state._berths.keyOf(entry),
      child: SizedBox(
        width: timelineDisplayRowExtent(entry, _state._metrics),
        height: totalFrameContentHeight,
        child: entry.isLane
            ? timelineGatedRow(
                entry,
                grid.hooks.dragPreview,
                (context, layer) =>
                    timelineLaneRowFrom(entry, layer, grid, _laneSpan),
              )
            : keptTimelineCellsRow(_kept, _state._berths, entry, grid),
      ),
    );
  }

  final KeptTimelineCellsRows _kept = KeptTimelineCellsRows();

  /// The frames the sheet lays its lane columns over — all of them, as the
  /// timeline's rows body lays its lanes (a lane windows itself off the
  /// bucket) — and their selection domain ([timelineLaneRowFrom]).
  TimelineLaneRowSpan get _laneSpan => (
    startIndex: 0,
    endIndexExclusive: _state._frameScroll.renderedFrameCount,
    leadingSpacer: 0,
    trailingSpacer: 0,
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
  TimelineCellsRowGrid _cellsRowGrid() => (
    hooks: _state.widget.hooks,
    metrics: _state._metrics,
    geometry: _state._frameScroll.publishFrameGeometry(),
    windowBucket: _state._frameWindowBucket,
    frameAxisController: _state._frameScrollController,
    nextPage: _state._nextPage,
    rangeGesture: _state._rangeGesture,
    axis: Axis.vertical,
    keyPrefix: 'xsheet',
  );

  /// One column per display row. A RepaintBoundary per column (mirrors the
  /// horizontal rows): the cursor layer repaints alone on ticks. The gate
  /// inside makes an edge-drag step rebuild exactly the dragged layer's
  /// column, and a commit — or a bucket crossing — rebuilds none it did
  /// not change.
  ///
  /// An open graph's lanes are ONE graph, the timeline's way
  /// ([timelineFrameSide]).
  Widget buildColumns(
    List<TimelineDisplayRow> entries,
    TimelineRowEdges edges,
    double bodyViewportHeight,
    double totalFrameContentHeight,
  ) {
    // Recorded for the window, which is recomputed on bucket crossings —
    // outside any build. ⚠️Before the geometry is published: the window is
    // laid over this extent.
    _state._frameViewportExtent = bodyViewportHeight;
    final grid = _cellsRowGrid();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: timelineFrameSide(
        (rows: entries, first: 0, edges: edges, kept: timelineRowBuiltNow),
        grid,
        cells: (entry) => _gatedColumn(entry, grid, totalFrameContentHeight),
        laneRange: _state._laneRange,
      ),
    );
  }
}

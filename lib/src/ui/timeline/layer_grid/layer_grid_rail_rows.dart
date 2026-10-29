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

  /// What the rail keeps of its rows while only the window moves.
  final WindowMoveKeep _keep = WindowMoveKeep();

  LayerRailExtent get _railExtent =>
      _state.widget.railExtent ??
      (_state._ownedRailExtent ??= LayerRailExtent());

  /// The rail's NATURAL extent — what it costs laid out in full. The
  /// window never changes it; that is the whole point of the model.
  double get naturalRailWidth => _state._metrics.layerControlsWidth;

  /// Resolves a STRETCH of rail-local vertical positions to the rows it
  /// covers — LANE ROWS INCLUDED, spacer gaps and rows past the window left
  /// out, in top-to-bottom order whichever way the stretch was given (F-66;
  /// the reason a segment is asked for at all is in [RailColumnSwipe.rowsIn]).
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
  /// The walk is [railRowsAlong]'s, over the edges the window was cut from;
  /// all that is left here is what a row at an index is.
  List<RailSwipeRow<TimelineDisplayRow>> _railRowsIn(
    double fromY,
    double toY,
    List<TimelineDisplayRow> rows,
    _RowWindow window,
  ) => railRowsAlong<TimelineDisplayRow>(
    from: fromY,
    to: toY,
    edges: window.edges,
    built: window.range,
    rowAt: (index) => _railSwipeRow(rows[index]),
  );

  /// A row as the shared swipe wants it. The identity is what the sweep
  /// dedupes by, and a lane row and its owner share a layer — so it is
  /// BOTH.
  RailSwipeRow<TimelineDisplayRow> _railSwipeRow(TimelineDisplayRow row) => (
    row: row,
    id: '${row.layer.id.value}/${row.lane?.laneId ?? ''}',
  );

  // ⛔"Which DISPLAY row the selection sits on" was written out here — a
  // second copy of [indexOfDisplayRow], which the ↑/↓ walk and the flip HUD
  // already read. The reveal asks that one now (round 8's grid
  // unification), so the rail and the walks can no longer disagree about
  // where the selection is.

  /// The memo gate for the rail's rows (UI-R7 #1): a controls row whose
  /// facts match hands back the CACHED widget instance — a zoom step (or any
  /// rebuild that didn't touch the row) skips its whole Material subtree.
  /// Lane label rows stay unmemoized: they subscribe to the frame cursor
  /// themselves and their lane models churn identity per build.
  ///
  /// The memo is the x-sheet header's too ([KeptLayerControlsRows]) — one
  /// reading of a controls row, one keeping of it, for both grids (F-244).
  Widget _railRowMemoized(TimelineDisplayRow row, RowBerthMap berths) {
    if (row.isLane) {
      return _state._rowDrags.draggable(row, _laneRow(row));
    }
    final grid = _controlsRowGrid;
    final fold = _groupFoldFor(row);
    final facts = layerControlsRowFacts(
      row,
      grid,
      fold: fold,
      hasLanes: _state.widget.hooks.lanesOf(row.layer).isNotEmpty,
    );
    return _state._railRowMemo.keep(
      berths,
      row,
      (facts: facts, drag: _state._rowDrags.inputsFor(row)),
      () => layerControlsRowFrom(facts, row, grid, fold),
    );
  }

  /// The rail as its controls rows see it — the x-sheet's header strip is
  /// the same record turned on its side.
  LayerControlsRowGrid get _controlsRowGrid => (
    hooks: _state.widget.hooks,
    layers: _state.widget.layers,
    metrics: _state._metrics,
    axis: Axis.horizontal,
    keyPrefix: 'timeline',
    mainExtent: null,
  );

  /// Row [index]'s rail row where [window] lays [rows] — none for a row of
  /// no extent: an open graph the enlarged one folds stands as its first
  /// lane's strip (I-89 ③D).
  ///
  /// ONE builder for the window loop and the A5 pin site, so the two can
  /// never drift: the row is built in its BERTH ([RowBerths]), which is
  /// what re-matches the pinned element's State when the window returns,
  /// and NAMED for its layer ([Named]) — a key spelled from the layer
  /// remade every row of the rail on a cut switch (I-57).
  Widget? _railRowAt(
    List<TimelineDisplayRow> rows,
    _RowWindow window,
    int index,
  ) => window.edges.extentOf(index) > 0
      ? _keep.row(
          window.berths.keyOf(rows[index]),
          () => Named(
            _railRowName(rows[index]),
            key: window.berths.keyOf(rows[index]),
            child: _railRowMemoized(rows[index], window.berths),
          ),
        )
      : null;

  String _railRowName(TimelineDisplayRow row) =>
      'timeline-rail-row-'
      '${row.layer.id}-'
      '${row.isFolder ? 'folder-${row.layer.id}' : row.lane?.laneId ?? 'row'}';

  /// The legend header — which keeps itself while what it shows holds
  /// ([TimelineLayerControlsHeader.facts]): zoom steps, unrelated notifies
  /// and cut switches hand back the cells it had.
  Widget legendHeader() =>
      _state._legendRail.header(metrics: _state._metrics);

  /// One lane label row, extracted so the windowed rail loop stays
  /// readable. Rows reserve an empty leading section slot — the section
  /// ZONES overlay whole runs (UI-R7 #2). A layer row is the controls row
  /// both grids build ([layerControlsRowFrom]).
  Widget _laneRow(TimelineDisplayRow row) {
    // Lane labels show the value AT the cursor: the row subscribes to it
    // itself, on a layer of its own, so a tick rebuilds only these small
    // cells and lays out nothing around them ([TimelineLaneControlsRow]).
    //
    // R10: and through the drag gate, so the blue value column follows a
    // key move per step. The band moved live while the number beside it
    // still read the committed track — the label is where you WATCH the
    // value, so it is the half that most needed to be live.
    return TimelineDragPreviewRowGate(
      dragPreview: _state.widget.hooks.dragPreview,
      layer: row.layer,
      slice: (layer) => laneRowSlice(layer, row.lane!.laneId),
      rowBuilder: (context, layer) => TimelineLaneControlsRow(
        layer: layer,
        lane: previewedLaneRow(
          row: row,
          previewLayer: layer,
          lanesForLayer: _state.widget.hooks.lanesOf,
        ),
        metrics: _state._metrics,
        frameCursor: _state.widget.hooks.frameCursor,
        onSelectFrame: _state.widget.hooks.onSelectFrame,
        laneEdit: _state.widget.hooks.laneEdit,
        onToggleLaneGroup: _state.widget.hooks.onToggleLaneGroup,
        onToggleLaneGroupEnabled:
            _state.widget.hooks.onToggleLaneGroupEnabled,
        onResetLaneGroup: _state.widget.hooks.onResetLaneGroup,
        currentRowHooks: _state.widget.hooks.currentRowHooks,
        leadingInset: layerSectionLabelSlotWidth,
        // The SAME answer the layer row reads, so a group
        // header's fx lands in the layer rows' fx column (R5 #7).
        optionalColumns: _state.widget.hooks.optionalRailColumns,
        laneGraphs: _state.widget.hooks.laneGraphs,
        laneGraphVerbs: _state.widget.hooks.laneGraphVerbs,
        seat: row.graph,
        height: timelineDisplayRowExtent(row, _state._metrics),
        folded: row.folded,
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
  /// The first of the three slots `TimelineLayerFrameBodyLayout` lays out.
  /// Only its rows and their selection bands are laid again when the
  /// window moves ([_RowWindowCut.laid]); the rail around them is the
  /// pass's.
  Widget buildLayerControlsRail(
    List<TimelineDisplayRow> rows,
    double? availableRailExtent,
    _RowWindowCut window,
    List<RailToggleColumn<TimelineDisplayRow>> swipeColumns,
  ) {
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
            rowsIn: (fromY, toY) => _railRowsIn(fromY, toY, rows, window.now),
            child: Stack(
              children: [
                window.laid((window) => _windowedRailRows(rows, window)),
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
                  child: _state._sectionBandOverlay(rows, window.edges),
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
                  child: window.laid(
                    (window) => TimelineRowSelectionBands(
                      selectedFlags: [
                        for (final row in window.rows)
                          _state.widget.hooks.selectedRows.contains(
                            row.address,
                          ),
                      ],
                      edges: window.edges,
                      firstRow: window.range.startIndex,
                      crossExtent:
                          _state._metrics.layerControlsWidth -
                          layerSectionLabelSlotWidth,
                    ),
                  ),
                ),
                // The layer area as a place entrance, on top so a file let
                // go anywhere on the rail finds it — an empty box the rest
                // of the time, so every row keeps its own pointer.
                if (placementEntrance(
                      key: const ValueKey<String>(
                        'timeline-layer-placement-entrance',
                      ),
                    )
                    case final entrance?)
                  Positioned.fill(child: entrance),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The rail's rows where [window] lays [rows], the rest of them spacers.
  ///
  /// It takes the row window as ONE value rather than the seven locals it
  /// unpacks below — that is what [_RowWindow] is for, and unpacking under
  /// the same names is what lets the tree below move verbatim.
  Widget _windowedRailRows(List<TimelineDisplayRow> rows, _RowWindow window) {
    final rowWindow = window.range;
    final edges = window.edges;
    final leadingRowSpacerHeight = window.leadingSpacerHeight;
    final trailingRowSpacerHeight = window.trailingSpacerHeight;
    final pinnedIndex = window.pinnedIndex;
    final pinnedBefore = window.pinnedBefore;
    final pinnedAfter = window.pinnedAfter;
    _keep.lay(window.pass);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The rail is windowed with the same layer-axis slice as the frame
        // rows; keys keep row state glued to its layer through window
        // shifts. A5: a pinned (held) row is carved out of its spacer —
        // total extent is unchanged.
        if (pinnedBefore) ...[
          if (edges.startOf(pinnedIndex) > 0)
            SizedBox(height: edges.startOf(pinnedIndex)),
          ?_railRowAt(rows, window, pinnedIndex),
          if (leadingRowSpacerHeight - edges.endOf(pinnedIndex) > 0)
            SizedBox(
              height: leadingRowSpacerHeight - edges.endOf(pinnedIndex),
            ),
        ] else if (leadingRowSpacerHeight > 0)
          SizedBox(height: leadingRowSpacerHeight),
        for (
          var index = rowWindow.startIndex;
          index < rowWindow.endIndexExclusive;
          index += 1
        ) ...[
          ?_railRowAt(rows, window, index),
          // An open graph's room, after its last lane: no row, so nothing
          // of a row's is built in it.
          if (edges.roomOf(index) > 0) SizedBox(height: edges.roomOf(index)),
        ],
        if (pinnedAfter) ...[
          if (edges.startOf(pinnedIndex) -
                  edges.startOf(rowWindow.endIndexExclusive) >
              0)
            SizedBox(
              height:
                  edges.startOf(pinnedIndex) -
                  edges.startOf(rowWindow.endIndexExclusive),
            ),
          ?_railRowAt(rows, window, pinnedIndex),
          if (edges.total - edges.endOf(pinnedIndex) > 0)
            SizedBox(height: edges.total - edges.endOf(pinnedIndex)),
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
              child: EmptyStateText(
                AppText.strings.tlNoLayers,
                place: EmptyStatePlace.list,
              ),
            ),
          ),
      ],
    );
  }

  /// The layer area as a place entrance — over the rail's rows, and over
  /// the room under them where the body is taller than they are, [lead]
  /// the rows' extent there — or null where the host takes no file
  /// between layers.
  ///
  /// ONE entrance for both, so a gap is counted in the rows the same way
  /// wherever the file is let go: under the rows is past the last of them,
  /// the foot — where ACTION stands on the rail, and where an ACTION with
  /// no row is (F-372).
  Widget? placementEntrance({required Key key, double lead = 0}) {
    final onDrop = _state.widget.hooks.onDropMediaAssetBetweenLayers;
    if (onDrop == null) {
      return null;
    }
    final rowDrag = _state.widget.hooks.rowDragHooks;
    return LayerPlacementEntrance(
      key: key,
      rowAxis: Axis.vertical,
      lead: lead,
      rows: () => (rows: _state._dragRows, edges: _state._dragEdges),
      onHover: rowDrag?.onPlacementHover,
      onLeave: rowDrag?.onPlacementLeave,
      accepts: rowDrag?.acceptsPlacement,
      onDrop: onDrop,
    );
  }
}

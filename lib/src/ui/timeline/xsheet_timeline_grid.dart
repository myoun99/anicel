import '../canvas/canvas_press.dart' show canvasPressButtons, canvasPressPans;
import '../widgets/empty_state_text.dart';
import '../widgets/named.dart';
import '../widgets/tick_layer.dart';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/layer.dart';
import '../text/app_face.dart';
import '../text/app_strings.dart' show AppText;
import '../theme/app_theme.dart';
import 'layer_label_controls.dart';
import 'layer_rail_columns.dart';
import 'rail_column_swipe.dart';
import 'layer_rail_window.dart';

import 'timeline_grid_range_gestures.dart';
import 'timeline_scroll_offset_sync.dart';
import 'timeline_frame_axis_follower.dart';
import 'timeline_cell_style.dart';
import 'timeline_frame_coordinate_policy.dart'
    show frameRangeVisibleWidth, timelineFrameEdge;
import 'timeline_frame_ruler_painter.dart' show TimelineRulerScale;
import 'timeline_ruler_playhead_writing.dart';
import 'timeline_cut_end_handle.dart';
import 'lane_row_slice.dart';
import 'timeline_drag_preview.dart';
import '../../models/project_frame_rate.dart';
import 'timeline_row_selection_bands.dart' show TimelineRowSelectionBands;
import 'layer_drop_policy.dart'
    show effectHeaderRowsOf, rowsWithSilhouette;
import 'layer_placement_entrance.dart';
import 'layer_row_drag.dart';
import 'layer_controls_row_facts.dart';
import 'timeline_cells_row_facts.dart';
import '../listenable_rebind.dart';
import 'timeline_edge_auto_pan.dart';
import 'timeline_frame_range_gesture.dart';
import 'timeline_ruler_cursor_overlay.dart';
import 'timeline_frame_geometry.dart'
    show TimelineFrameGeometry, timelineFrameWindowMarginPx;
import 'timeline_frame_scrub.dart';
import 'timeline_frame_cursor_layer.dart';
import 'timeline_frame_range_policy.dart';
import 'timeline_frame_window.dart';
import '../text/laid_out_glyph.dart';
import 'timeline_glyph_cache.dart';
import 'property_lane_model.dart';
import 'row_berths.dart';
import 'timeline_grid_metrics.dart';
import 'timeline_lane_rows.dart';
import 'timeline_horizontal_offset_policy.dart';
import '../input/two_axis_drag.dart';
import 'timeline_grid_shell.dart';
import 'timeline_horizontal_scrollbar_rail.dart';
import 'timeline_ruler_cut_end_boundary.dart';
import 'timeline_ruler_norishiro_boundary.dart';
import 'timeline_section_policy.dart';
import 'timeline_section_runs.dart';
import 'timeline_vertical_scrollbar_rail.dart';
import 'timeline_visible_range.dart';
import 'timeline_lane_graph.dart' show timelineFrameSide, timelineRowBuiltNow;
import 'timeline_row_edges.dart';
import 'timeline_zoom_anchor_policy.dart';
import 'timeline_frame_grid_stack.dart';
import 'timeline_grid_sheet.dart';
import 'timeline_layer_controls_row.dart';
import '../layout/device_grid_scroll_controller.dart';
import 'timeline_grid_hooks.dart';
import 'timeline_grid_legend_rail.dart';
import 'timeline_swipe_columns.dart';
import '../repaint_props.dart';
import '../text/word_bake.dart' show RepaintOnWordBakes;

part 'xsheet_grid/xsheet_grid_frame_scroll.dart';
part 'xsheet_grid/xsheet_grid_headers.dart';
part 'xsheet_grid/xsheet_grid_columns.dart';
part 'xsheet_grid/xsheet_grid_reveal.dart';

/// The vertical X-sheet: the SAME grid logic as the horizontal
/// [LayerTimelineGrid], transposed.
///
/// The transposition is a metrics trick: the frame axis runs vertically, so
/// [_metrics.frameCellWidth] is the frame ROW height and
/// [_metrics.layerRowHeight] is the layer COLUMN width. Every policy the
/// horizontal grid uses — frame range, offset resolution, the frame window,
/// coordinate conversion, cell style/block visuals, selected exposure
/// range, playhead visibility, cut-end boundary — is reused unchanged with
/// the axes swapped; only the thin widget composition differs.
class XSheetTimelineGrid extends StatefulWidget {
  const XSheetTimelineGrid({
    super.key,
    required this.hooks,
    required this.layers,
    this.railExtent,
    this.frameAxisOffset,
    this.layerAxisOffset,
    this.metrics = defaultMetrics,
  });

  final List<Layer> layers;

  /// What the session answers this grid — see [TimelineGridHooks]. The
  /// rail and the sheet read the SAME bundle, so neither can lack an
  /// answer the other has.
  final TimelineGridHooks hooks;

  /// The header block's window size, set by this sheet's splitter and
  /// persisted by the workspace. Null = a session-local one of our own.
  final LayerRailExtent? railExtent;

  /// Where the FRAME axis stands — the rail's [LayerTimelineGrid
  /// .frameAxisOffset], transposed: kept by the workspace so a fold does
  /// not throw it away (F-143). Null = a session-local one of our own.
  final ValueNotifier<double>? frameAxisOffset;

  /// Where the LAYER axis stands — the rail's [LayerTimelineGrid
  /// .layerAxisOffset], transposed: across the columns, the project's
  /// (F-267). Null = nobody keeps it; the columns start at the left.
  final ValueNotifier<double>? layerAxisOffset;

  /// Grid geometry (transposed); frameCellWidth carries the frame-axis zoom
  /// as the frame ROW height here.
  final TimelineGridMetrics metrics;

  /// TRANSPOSED metrics: frameCellWidth = frame row height, layerRowHeight
  /// = layer column width, layerControlsWidth = frame-number rail width.
  /// No section gutter here — the X-sheet's section axis is horizontal and
  /// section controls live on the column headers.
  ///
  /// R10 R6: every number here is now the timeline's, turned on its side.
  /// They used to be 36/164/72 — hand-tuned, and free to drift the moment
  /// anyone touched the timeline. A column is exactly as wide as a row is
  /// tall now, which is what makes the two grids read as one grid.
  static const TimelineGridMetrics defaultMetrics = TimelineGridMetrics(
    // A frame ROW is as tall as a frame CELL is wide.
    frameCellWidth: timelineFrameCellWidth,
    // A layer COLUMN is as wide as a layer ROW is tall — 164 → 28. This is
    // the change that makes everything in the header stand up: nothing
    // reads horizontally in 28px.
    layerRowHeight: timelineLayerRowHeight,
    // The frame-number RAIL is as wide as the ruler is tall — 72 → 28. If
    // the seconds label gets tight it is fixed in the SHARED ruler, so both
    // panels get better at once (no per-panel exception).
    layerControlsWidth: timelineFrameRulerExtent,
    sectionLabelGutterWidth: 0,
  );

  /// The section band above the layer headers: the paper sheet's
  /// ACTION/SE/CAM group headings, each wrapping its columns. It is the
  /// rail's reserved section SLOT stood up, so it is that slot's extent.
  static const double _sectionBandHeight = layerSectionLabelSlotWidth;

  /// ★ The header block is the timeline's rail, turned on its side — EVERY
  /// control single file, plus a name as generous as the rail's own name
  /// column and the third of it the rail gave up ([_nameTheRailGaveUp]).
  /// A control the rail gains or sheds the block gains or sheds with it,
  /// with nothing to remember; the rail's names are the rail's own.
  ///
  /// R10 R6 shed columns a short panel could not afford; the user's call
  /// was the opposite — "타임라인에 있는거 싹다 넣어. 뭐 빼지말고" — and
  /// R6a answered it by scaling the whole column down. Both are gone. The
  /// block is ALWAYS this tall, and a panel that cannot spend it sees a
  /// narrower WINDOW onto it (the rail-window round): the tail is cut, the
  /// splitter says where, and nothing inside rearranges.
  ///
  /// [optionalColumns] is the HOST's answer about which optional columns
  /// exist at all — the legend beside the headers must size from the same
  /// answer or its icons stop naming the columns under them.
  static double naturalHeaderBlockExtent({
    required LayerRailOptionalColumns optionalColumns,
    required LayerRailColumnWidths columns,
  }) =>
      _sectionBandHeight +
      (layerRailLeadingWidth - layerSectionLabelSlotWidth) +
      _naturalNameExtent(columns) +
      _laneGraphRoom +
      layerRailTrailingWidth(
        columns: columns,
        optionalColumns: optionalColumns,
      ) +
      _headerBorderExtent;

  /// What the block keeps past the rail stood up (I-89-Q17 A, 유저
  /// 2026-10-12: 「시트 머리는 지금 높이 그대로(+22)」): a header graph's
  /// slot gave it this room from 10-11, a stood-up lane stands its pin and
  /// chips in it, and the rail's answer to I-89 Q1 took the slot and left
  /// the room. Taken off, the lanes shed both — the pin and chips are what
  /// a column pays last.
  static const double _laneGraphRoom = 22;

  /// The NAME's share of the rail — what the horizontal row's `Expanded`
  /// resolves to once every slot has been served, the onion's and the
  /// blend's among them — read off the rail's own width
  /// ([timelineLayerControlsWidthFor]) and its own slots
  /// ([layerRailTrailingWidth]), so the stood-up rail grows as the rail
  /// does under the OS text size. ↩️The slots were listed here by hand, at
  /// 1×: the rail paid its lane value column's growth and the sheet did not.
  ///
  /// Less the room the rail pays a lane's value HANDS
  /// ([layerLaneValueHandsWidth]): the sheet writes a lane's value row
  /// turned on its side, at the rail's length, in the lane's own column,
  /// where it fits under the lane's name (유저 2026-10-11: 「머리칸이라기보다
  /// 편집숫자들 … 진짜로 90도눕혀서 쓰는것처럼 하면 길이 다 타임라인이랑
  /// 똑같이 들어갈거같은데」). 🔬Paid, the header took 76 of a bottom dock
  /// that stops at 640 (`EditorPanelLayoutModel.maxDockExtent`): its frame
  /// rows went from about four to two (2026-10-10), and once the value was
  /// turned the block no longer fit the tallest dock at all — the window
  /// cut its tail, the SE speaker and the opacity and blend columns with it
  /// (2026-10-11). Asked with the rail's full length on offer, the user
  /// kept this one (유저 2026-10-11 「여쭐것 둘다 문제없음」).
  static double _naturalNameExtent(LayerRailColumnWidths columns) =>
      timelineLayerControlsWidthFor(columns) +
      _nameTheRailGaveUp -
      layerLaneValueHandsWidth -
      layerRailLeadingWidth -
      layerRailTrailingWidth(
        columns: columns,
        optionalColumns: (onion: true, blend: true),
      );

  /// What the rail's names gave up and the sheet's kept (F-409, 유저
  /// 2026-10-19: 「x시트는 가로모드랑 레이어영역 총 길이 안맞춰도됨. 버튼이나
  /// 패딩개선등 통일할건 통일하지만 x시트는 애초에 지금도 fx부분 보면 공간
  /// 부족하거나 하니 총 길이는 유지해도됨」): the rail went 519 → 461 for its
  /// names alone, and the block keeps the length it had.
  static const double _nameTheRailGaveUp = 58;

  /// The column header's own hairlines, top and bottom.
  static const double _headerBorderExtent = 2;

  @override
  State<XSheetTimelineGrid> createState() => _XSheetTimelineGridState();
}

class _XSheetTimelineGridState extends State<XSheetTimelineGrid>
    implements TimelineLegendHost {
  /// The integer rate the grid COUNTS with — the ruler's second marks
  /// and row labels are frame arithmetic, never real time (see
  /// [ProjectFrameRate.countingBase]).
  int get _countingFps => widget.hooks.projectFrameRate.countingBase;

  /// Resolves range-move column deltas against the entries built this pass.
  final TimelineRangeMoveRowResolver _rangeMoveResolver =
      TimelineRangeMoveRowResolver();

  /// The LIVE frame-axis geometry the painted columns follow (R28 #4 — the
  /// timeline's rule, transposed). Its identity outlives zoom steps, so the
  /// row memo hands cached columns back while the geometry underneath moves;
  /// listeners are render objects only (see the timeline body's note).
  final ValueNotifier<TimelineFrameGeometry> _frameGeometry = ValueNotifier(
    const TimelineFrameGeometry(
      frameCellExtent: 1,
      frameStartIndex: 0,
      frameEndIndexExclusive: 0,
    ),
  );

  /// The WINDOWED twin (zoom round, the timeline body's split transposed):
  /// the columns whose every consumer reads geometry live are laid out at a
  /// constant pixel window instead of `frames * cellHeight`, so a zoom step
  /// re-lays-out one box per column rather than everything inside it. The
  /// sparse kinds keep [_frameGeometry] — their span overlays are widgets
  /// positioned from build-time scalars, and a window sliding under them
  /// without a rebuild would strand them.
  final ValueNotifier<TimelineFrameGeometry> _windowedFrameGeometry =
      ValueNotifier(
        const TimelineFrameGeometry(
          frameCellExtent: 1,
          frameStartIndex: 0,
          frameEndIndexExclusive: 0,
        ),
      );

  /// The frame-axis viewport recorded by the last build — the window's
  /// extent, needed again when the bucket moves outside a build.
  double _frameViewportExtent = 0;

  /// The fallback rail extent for hosts that keep none of their own.
  LayerRailExtent? _ownedRailExtent;

  // ── the rail scrub: the SHARED object ───────────────────────────────
  //
  // [TimelineFrameScrub], the one the timeline's ruler holds too — the same
  // six members, turned by the axis (the audit's clone scan, round 8).
  late final TimelineFrameScrub _railScrub = TimelineFrameScrub(
    axis: Axis.vertical,
    viewportKey: _railScrubViewportKey,
    controller: _frameScrollController,
    hooks: () => widget.hooks,
    frameCellExtent: () => _metrics.frameCellWidth,
    renderedFrameCount: () => _frameScroll.renderedFrameCount,
    scrolledFrameOffset: () => _frameAxis.paintedOffset,
  );

  /// The fallback rail extent for hosts that keep none of their own — the
  /// window the splitter sizes and the workspace persists.
  LayerRailExtent get _railExtent =>
      widget.railExtent ?? (_ownedRailExtent ??= LayerRailExtent());

  // ── the column headers: their own object ────────────────────────────
  //
  // A collaborator (timeline/xsheet_grid/xsheet_grid_headers.dart, a part of this
  // library). The State keeps the entry points its build tree calls.
  late final _XSheetGridHeaders _headers = _XSheetGridHeaders(this);

  // ── the columns: their own object, in their own file ────────────────
  //
  // A collaborator (timeline/xsheet_grid/xsheet_grid_columns.dart, a part of this
  // library). The State keeps the entry points its build tree calls.
  late final _XSheetGridColumns _columns = _XSheetGridColumns(this);

  // ── the frame scroll: its own object, in its own file ───────────────
  //
  // A collaborator (timeline/xsheet_grid/xsheet_grid_frame_scroll.dart, a part of this
  // library). The State keeps the entry points its build tree calls.
  late final _XSheetGridFrameScroll _frameScroll = _XSheetGridFrameScroll(this);

  /// The door a collaborator rebuilds through - setState is protected,
  /// and a collaborator is not a subclass.
  void _rebuild(VoidCallback fn) => setState(fn);

  /// The per-build gesture bundle (rebuilt in [build], consumed by the
  /// column builder).
  TimelineRangeGestureCallbacks? _rangeGesture;

  /// The per-build LANE gesture bundle (B4-④): the host's callbacks with
  /// the escalation seam wrapped in — a lane-anchored drag that leaves its
  /// own group joins the cells law, exactly as on the horizontal grid.
  TimelineLaneRangeCallbacks? _laneRange;

  // The layers and the frames are the sheet: one sheet, dragged both ways
  // at once (F-351).
  late final TwoAxisScrollController _frameScrollController;
  late final TwoAxisScrollController _layerScrollController;

  /// Frame-axis offset + window bucket notifiers (UI-R9 #12a, the
  /// horizontal grid's structure transposed): scroll pixels move the rail
  /// translate only; cell crossings re-window the columns; the grid never
  /// rebuilds per pixel.
  ///
  /// The host's when it keeps one — read ONCE, as on the rail.
  late final ValueNotifier<double> _frameAxisOffset =
      widget.frameAxisOffset ?? _ownedFrameAxisOffset;
  final ValueNotifier<double> _ownedFrameAxisOffset = ValueNotifier<double>(0);
  final ValueNotifier<int> _frameWindowBucket = ValueNotifier<int>(0);

  /// The host's record of the layer axis ([XSheetTimelineGrid
  /// .layerAxisOffset]) — read ONCE, as the frame axis's is.
  late final ValueNotifier<double>? _keptLayerAxis = widget.layerAxisOffset;

  /// Lets go of [_keptLayerAxis] ([followKeptAxis]).
  late final VoidCallback _letGoOfKeptColumns;

  /// The frame axis following its controller — the rail's follower, the
  /// same object, transposed by nothing but which controller it holds.
  late final TimelineFrameAxisFollower _frameAxis = TimelineFrameAxisFollower(
    controller: _frameScrollController,
    frameAxisOffset: _frameAxisOffset,
    frameWindowBucket: _frameWindowBucket,
    cellExtent: () => _metrics.frameCellWidth,
    baseFrameCount: () => _rangeGestures.frameRangePolicy.visibleFrameCount,
    viewportFillFrames: () => _viewportFillFrameCells,
    rebuild: _rebuild,
    isMounted: () => mounted,
  );

  /// Where the playing run's next turn stands the frame axis — what the
  /// columns bake that page's tiles for while it plays this one.
  TimelineNextPage? _nextPage() =>
      _frameAxis.nextPage(runFrames: widget.hooks.runFrames);

  /// UI-R9 #9, transposed to y: the frame axis pulled to the offset the
  /// layout resolved, one frame later — the rail's object.
  late final TimelineScrollOffsetSync _frameSync = TimelineScrollOffsetSync(
    _frameScrollController,
    isMounted: () => mounted,
  );
  final GlobalKey _railScrubViewportKey = GlobalKey();

  TimelineGridMetrics get _metrics => widget.metrics;

  @override
  void initState() {
    super.initState();
    // PEN-10: pen-friendly positions — while a stylus is nearby, a
    // coasting fling stops hiding the cells from hit-testing.
    // Born where the axis stands, as on the rail (F-143) — an orientation
    // switch or an unfold builds this sheet afresh, and a newborn 0 would be
    // recorded as a scroll.
    _frameScrollController = TwoAxisScrollController(
      bornAt: _frameAxisOffset,
    );
    // The columns too, where the project left them (F-267).
    _layerScrollController = TwoAxisScrollController(
      bornAt: _keptLayerAxis,
    );
    _frameScrollController.addListener(_frameAxis.handleScroll);
    _letGoOfKeptColumns = followKeptAxis(
      _layerScrollController,
      _keptLayerAxis,
      isMounted: () => mounted,
    );
    _frameWindowBucket.addListener(_frameScroll.handleFrameWindowBucket);
    widget.hooks.revealSelectionTick?.addListener(_reveal.handleRevealSelection);
    widget.hooks.frameCursor.addListener(_reveal.handlePlaybackPage);
  }

  // ── revealing a selection: its own object ───────────────────────────
  //
  // A collaborator (timeline/xsheet_grid/xsheet_grid_reveal.dart, a part of this
  // library). The State keeps the entry points its build tree calls.
  late final _XSheetGridReveal _reveal = _XSheetGridReveal(this);

  @override
  void didUpdateWidget(covariant XSheetTimelineGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hooks.revealSelectionTick !=
        widget.hooks.revealSelectionTick) {
      oldWidget.hooks.revealSelectionTick?.removeListener(
        _reveal.handleRevealSelection,
      );
      widget.hooks.revealSelectionTick?.addListener(_reveal.handleRevealSelection);
    }
    rebindListener(
      oldWidget.hooks.frameCursor,
      widget.hooks.frameCursor,
      _reveal.handlePlaybackPage,
    );
    // Zoom-around-playhead (transposed): the playhead ROW stays put on
    // screen through zoom when visible; otherwise the top-edge frame
    // anchors. Same policy as the horizontal timeline (Axis rule).
    applyZoomAnchoredScroll(
      _frameScrollController,
      oldPixelsPerFrame: oldWidget.metrics.frameCellWidth,
      newPixelsPerFrame: widget.metrics.frameCellWidth,
      anchorFrame: widget.hooks.frameCursor.value,
    );
  }

  @override
  void dispose() {
    widget.hooks.revealSelectionTick?.removeListener(_reveal.handleRevealSelection);
    widget.hooks.frameCursor.removeListener(_reveal.handlePlaybackPage);
    _frameAxis.dispose();
    _frameScrollController
      ..removeListener(_frameAxis.handleScroll)
      ..dispose();
    _letGoOfKeptColumns();
    _layerScrollController.dispose();
    _frameWindowBucket.removeListener(_frameScroll.handleFrameWindowBucket);
    _frameGeometry.dispose();
    _windowedFrameGeometry.dispose();
    // ⛔Only our own — the host's outlives this sheet by design.
    _ownedFrameAxisOffset.dispose();
    _frameWindowBucket.dispose();
    _ownedRailExtent?.dispose();
    super.dispose();
  }

  // ── the range gestures: their own object ────────────────────────────
  //
  // The ONE collaborator both grids hold (timeline_grid_range_gestures.dart).
  // The State keeps the entry points its build tree calls.
  //
  // No pin: this grid's LayerRailWindow is a paint clip, every column stays
  // built, so nothing can unmount a held row mid-gesture.
  late final TimelineGridRangeGestures _rangeGestures =
      TimelineGridRangeGestures(
        hooks: () => widget.hooks,
        metrics: () => _metrics,
        dragRows: () => _dragRows,
        dragEdges: () => _dragEdges,
        rangeMove: _rangeMoveResolver,
      );

  /// Frame cells the current viewport needs to be fully papered (UI-R12
  /// #16) — recorded by build's outer LayoutBuilder. Zero until layout.
  int _viewportFillFrameCells = 0;

  /// The legend in the corner, the rail's hand ([TimelineGridLegendRail]).
  late final TimelineGridLegendRail _legendRail = TimelineGridLegendRail(this);

  @override
  TimelineGridHooks get hooks => widget.hooks;

  @override
  List<Layer> get layers => widget.layers;

  @override
  List<TimelineDisplayRow> get drawnRows => _dragRows;

  /// The row's fold twirl — [timelineGroupFoldFor] bound to this grid's hooks.
  TimelineGroupFold _groupFoldFor(TimelineDisplayRow row) =>
      timelineGroupFoldFor(
        row: row,
        layers: widget.layers,
        collapsedAttachBaseIds: widget.hooks.collapsedAttachBaseIds,
        onToggleLayerCollapsed: widget.hooks.onToggleLayerCollapsed,
        onToggleAttachGroup: widget.hooks.onToggleAttachGroup,
      );

  /// The display entries of the pass in flight, for the drag's row → slot
  /// conversion (see [effectHeaderRowsOf]).
  List<TimelineDisplayRow> _dragRows = const [];

  /// Where [_dragRows] sit across the sheet — what a pointer's x is read
  /// in, beside the list it is counted in.
  TimelineRowEdges _dragEdges = TimelineRowEdges.uniform(0, 0);

  /// Which elements each column is built in — its header's and its cells'
  /// alike, as the rail's rows and the timeline's cells are ([RowBerths]).
  final RowBerths _rowBerths = RowBerths();

  /// The berths of the columns the pass in flight DRAWS.
  late RowBerthMap _berths;

  Widget _buildRailSplitter(_SheetGeometry geometry) {
    final availableHeaderExtent = geometry.availableHeaderExtent;
    final naturalHeaderBlockExtent = geometry.naturalHeaderBlockExtent;
    return LayerRailSplitter(
      key: const ValueKey<String>('xsheet-rail-splitter'),
      axis: Axis.vertical,
      extent: _railExtent,
      naturalExtent: naturalHeaderBlockExtent,
      availableExtent: availableHeaderExtent,
    );
  }

  /// The grid sheet under the columns (I-44) — the timeline's, turned on
  /// its side: every column's ground, every frame line and every column
  /// seam, once.
  Widget _buildGridSheet(
    List<TimelineDisplayRow> entries,
    TimelineRowEdges edges,
  ) {
    return TimelineRowsGridSheet(
      key: const ValueKey<String>('xsheet-grid-sheet'),
      axis: Axis.vertical,
      rows: entries,
      edges: edges,
      frameCellExtent: _metrics.frameCellWidth,
      activeLayerId: widget.hooks.activeLayerId,
      standing: widget.hooks.currentRowHooks?.currentRow,
    );
  }

  Widget _buildFrameVerticalViewport(
    List<TimelineDisplayRow> entries,
    _SheetGeometry geometry,
  ) {
    final bodyViewportHeight = geometry.bodyViewportHeight;
    return SingleChildScrollView(
      key: const ValueKey<String>('xsheet-frame-vertical-viewport'),
      controller: _frameScrollController,
      child: DeviceGridScrollBody(
        controller: _frameScrollController,
        axisDirection: AxisDirection.down,
        child: SizedBox(
          height: geometry.totalFrameContentHeight,
          // The timeline's stack, turned on its side: the grid sheet under
          // the columns (D32, I-44), the cursor layer over them, and where
          // the film stops stated over everything (the user's layer order).
          //
          // 🚨Built for the full frames, as the timeline's rows body is — a
          // scroll rebuilds nothing here: the columns and the cursor window
          // themselves off the bucket. ↩️The stack sat in a builder of the
          // bucket and handed the lanes and the cursor its window, so every
          // crossing built the whole frame body again
          // (xsheet-bucket-crossing-rebuilds-the-frame-body, 10-30).
          child: TimelineFrameGridStack(
            axis: Axis.vertical,
            rowsBody: _rowBerths.counting(
              _columns.buildColumns(
                entries,
                geometry.columnEdges,
                bodyViewportHeight,
                geometry.totalFrameContentHeight,
              ),
            ),
            gridSheet: _buildGridSheet(entries, geometry.columnEdges),
            playheadExtent: geometry.totalFrameContentHeight,
            playhead: _buildCursorLayer(
              entries,
              geometry.columnEdges,
              bodyViewportHeight,
            ),
            cutEndDrag: widget.hooks.cutEndDrag,
            dragPreview: widget.hooks.dragPreview,
            frameCellExtent: _metrics.frameCellWidth,
            playbackFrameCount: widget.hooks.playbackFrameCount,
            noriShiro: widget.hooks.noriShiro,
          ),
        ),
      ),
    );
  }

  /// The cursor layer carries the playhead + selection visuals; ticks
  /// repaint it alone. Over the full frames, windowed off the bucket — the
  /// timeline's own (`LayerTimelineGrid._buildPlayhead`).
  Widget _buildCursorLayer(
    List<TimelineDisplayRow> entries,
    TimelineRowEdges edges,
    double bodyViewportHeight,
  ) {
    return TimelineCursorLayer(
      axis: Axis.vertical,
      currentRow: widget.hooks.currentRowHooks?.currentRow,
      selectedSemanticsKey: const ValueKey<String>('xsheet-selected-cell'),
      frameRangeSelection: widget.hooks.rangeHooks?.selection,
      // R27 #14: one band for cells and lanes alike.
      laneRangeSelection: widget.hooks.laneRange?.selection,
      dragPreview: widget.hooks.dragPreview,
      frameCursor: widget.hooks.frameCursor,
      rows: entries,
      edges: edges,
      activeLayerId: widget.hooks.activeLayerId,
      frameStartIndex: 0,
      frameEndIndexExclusive: _frameScroll.renderedFrameCount,
      leadingFrameSpacerWidth: 0,
      metrics: _metrics,
      crossAxisExtent: edges.total,
      windowBucket: _frameWindowBucket,
      viewportMainExtent: bodyViewportHeight,
    );
  }

  Widget _buildLayerHorizontalViewport(
    ColorScheme colorScheme,
    List<TimelineDisplayRow> entries,
    List<TimelineSectionRun> sectionRuns,
    _SheetGeometry geometry,
  ) {
    final availableHeaderExtent = geometry.availableHeaderExtent;
    final naturalHeaderBlockExtent = geometry.naturalHeaderBlockExtent;
    final splitterSlotExtent = geometry.splitterSlotExtent;
    final columnsContentWidth = geometry.columnsContentWidth;
    return SingleChildScrollView(
      key: const ValueKey<String>('xsheet-layer-horizontal-viewport'),
      controller: _layerScrollController,
      scrollDirection: Axis.horizontal,
      child: DeviceGridScrollBody(
        controller: _layerScrollController,
        axisDirection: AxisDirection.right,
        child: SizedBox(
          width: columnsContentWidth,
          child: Column(
            children: [
              // The header's wheel is its window's, as its pan is: a notch
              // pushes the window down the headers, and with Shift the
              // layers across, as a notch over the cells does (F-447-Q1,
              // [PanSlideRegion]).
              // ↩️F-159 (유저 2026-09-18: 「x시트에서 레이어 영역의 휠을
              // 통한 스크롤이 작동안함. 타임라인이랑 법 통일」) took every
              // notch here for the layers. F-447 (유저 10-23: 「x시트의
              // 레이어영역의 휠조작이 작동안함 … 프레임 영역이랑 법
              // 통일」) asked again, and its Q1 chose the area's own law —
              // the pan's.
              LayerRailWindow(
                axis: Axis.vertical,
                rail: _railExtent,
                naturalExtent: naturalHeaderBlockExtent,
                availableExtent: availableHeaderExtent,
                child: Column(
                  children: [
                    // The paper sheet's group headings: one
                    // bracket cell per section run, wrapping
                    // its columns.
                    Row(
                      // Named so a probe can
                      // measure where the band
                      // sits against the headers
                      // it caps (F-32).
                      key: const ValueKey<String>('xsheet-section-band-row'),
                      children: [
                        for (final run in sectionRuns)
                          _XSheetSectionBandCell(
                            run: run,
                            height: XSheetTimelineGrid._sectionBandHeight,
                            extent: timelineSectionRunExtent(
                              run,
                              geometry.columnEdges,
                            ),
                          ),
                      ],
                    ),
                    // 🆕F-26 (유저 2026-08-24):
                    // 「선택범위ui도 예전모습 그대로
                    // **하나하나 실루엣 선택**되고
                    // 있음」 — the sheet ringed each
                    // selected column on its own
                    // while the rail drew ONE band
                    // per contiguous run. Same
                    // widget, turned on its side.
                    Stack(
                      children: [
                        // 🚨The rail's bulk-drag, TURNED ON ITS SIDE. Same
                        // widget, same columns; the x-sheet is the rail
                        // transposed, so the sweep runs ACROSS the layer
                        // columns instead of down the rows.
                        RailColumnSwipe<TimelineDisplayRow>(
                          axis: Axis.horizontal,
                          columns: _columns.swipeColumns(),
                          rowsIn: (from, to) => _columns.columnsIn(
                            from,
                            to,
                            entries,
                            geometry.columnEdges,
                          ),
                          child: _rowBerths.counting(
                            Row(
                              children: _headers.headers(
                                entries,
                                geometry.columnEdges,
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: TimelineRowSelectionBands(
                            axis: Axis.vertical,
                            selectedFlags: [
                              for (final entry in entries)
                                widget.hooks.selectedRows.contains(
                                  entry.address,
                                ),
                            ],
                            edges: geometry.columnEdges,
                            crossExtent: _headers.naturalHeaderExtent,
                          ),
                        ),
                        // The sheet's header strip is the rail turned on its
                        // side, so it is the same place entrance, along x.
                        if (widget.hooks.onDropMediaAssetBetweenLayers
                            case final onDrop?)
                          Positioned.fill(
                            child: LayerPlacementEntrance(
                              key: const ValueKey<String>(
                                'xsheet-layer-placement-entrance',
                              ),
                              rowAxis: Axis.horizontal,
                              rows: () =>
                                  (rows: _dragRows, edges: _dragEdges),
                              onHover:
                                  widget.hooks.rowDragHooks?.onPlacementHover,
                              onLeave:
                                  widget.hooks.rowDragHooks?.onPlacementLeave,
                              accepts:
                                  widget.hooks.rowDragHooks?.acceptsPlacement,
                              onDrop: onDrop,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // Reserves the gap the splitter
              // floats over.
              SizedBox(height: splitterSlotExtent),
              Expanded(
                child: ScrollConfiguration(
                  // The rail between the frame numbers
                  // and the cells is THE scrollbar; the
                  // desktop auto-overlay was the
                  // duplicate (UI-R10 #22).
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: _buildFrameVerticalViewport(
                    entries,
                    geometry,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVerticalScrollbar(_SheetGeometry geometry) {
    final bodyViewportHeight = geometry.bodyViewportHeight;
    final totalFrameContentHeight = geometry.totalFrameContentHeight;
    return TimelineVerticalScrollbarRail(
      key: const ValueKey<String>('xsheet-vertical-scrollbar'),
      controller: _frameScrollController,
      viewportHeight: bodyViewportHeight,
      contentHeight: totalFrameContentHeight,
    );
  }

  Widget _buildRailCursorOverlay(_SheetGeometry geometry) {
    final bodyViewportHeight = geometry.bodyViewportHeight;
    return TimelineRulerCursorOverlay(
      keyValue: 'xsheet-rail-cursor-overlay',
      axis: Axis.vertical,
      playhead: widget.hooks.frameCursor,
      repaintSignal: widget.hooks.frameReadySignal,
      windowBucket: _frameWindowBucket,
      viewportMainExtent: bodyViewportHeight,
      renderedFrames: _frameScroll.renderedFrameCount,
      cellWidth: _metrics.frameCellWidth,
      readyRunsIn: widget.hooks.readyRunsIn,
    );
  }

  Widget _buildRailScrubArea(_SheetGeometry geometry) {
    final bodyViewportHeight = geometry.bodyViewportHeight;
    final totalFrameContentHeight = geometry.totalFrameContentHeight;
    final cutEndBoundaryOffset = geometry.cutEndBoundaryOffset;
    return Listener(
      key: const ValueKey<String>('xsheet-frame-rail-scrub-area'),
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        // R26 #34: a press that pans is the pan's, not a scrub.
        if (canvasPressPans(canvasPressButtons(event))) {
          return;
        }
        _railScrub.resetTracking();
        _railScrub.pressAt(event.position);
      },
      onPointerUp: (_) => _railScrub.endScrub(),
      onPointerCancel: (_) => _railScrub.endScrub(),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragStart: (details) {
          _railScrub.pressAt(details.globalPosition);
        },
        onVerticalDragUpdate: (details) {
          _railScrub.dragTo(details.globalPosition);
        },
        onVerticalDragEnd: (_) => _railScrub.resetTracking(),
        onVerticalDragCancel: _railScrub.resetTracking,
        child: ClipRect(
          key: _railScrubViewportKey,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minHeight: totalFrameContentHeight,
            maxHeight: totalFrameContentHeight,
            minWidth: _metrics.layerControlsWidth,
            maxWidth: _metrics.layerControlsWidth,
            // Pixels move the TRANSLATE only; the
            // rail painter windows itself off the
            // offset (UI-R15 — no bucket rebuild).
            //
            // R9 #3 (transposed): the RAW scroll
            // position, overscroll included —
            // the clamp is for correcting the
            // CONTROLLER, not for paint.
            //
            // 🚨★★★F-32: THE SAME
            // CORRECTION THE CELLS GET.
            //
            // 유저: 「해당 레이어 영역
            // 자체가 밀림 … 띠가 살짝
            // 아래로 2px정도?」 — and it
            // only happens 「스크롤에
            // 따라」, which is the tell.
            //
            // The frame CELLS scroll
            // through
            // [DeviceGridScrollBody],
            // which cancels the offset's
            // sub-device-pixel fraction.
            // This rail moved by a RAW
            // translate, so it kept that
            // fraction — 🧪measured at
            // ratio 1.5: rail 360.0 vs
            // cells 359.667, a third of a
            // logical pixel apart, at
            // rest identical.
            //
            // ⛔Not a rounding of its own
            // here: the correction is
            // that widget's, and a second
            // copy of the arithmetic is
            // how the two drift apart
            // again the next time either
            // is touched.
            //
            // ↩️F-95: the translate read a
            // NOTIFIER that a resize past
            // the end never reached; the
            // follower reads the position
            // when it paints.
            child: ScrollFollower(
              controller: _frameScrollController,
              axisDirection: AxisDirection.down,
              child: Builder(
                builder: (context) {
                  return SizedBox(
                    width: _metrics.layerControlsWidth,
                    height: totalFrameContentHeight,
                    child: Stack(
                      children: [
                        // SPLIT (shared with the
                        // horizontal rulers): the
                        // numbers are static, so a
                        // seek no longer re-records
                        // a glyph per frame; the
                        // tint and the cached bar
                        // ride the overlay below.
                        // UI-R15: full bounds — the
                        // rail painter windows
                        // itself off the offset.
                        RepaintBoundary(
                          child: _XSheetFrameNumberRail(
                            frameStartIndex: 0,
                            frameEndIndexExclusive: _frameScroll.renderedFrameCount,
                            playhead: widget.hooks.frameCursor,
                            playbackFrameCount: widget.hooks.playbackFrameCount,
                            leadingFrameSpacerHeight: 0,
                            trailingFrameSpacerHeight: 0,
                            metrics: _metrics,
                            onSelectFrame: _railScrub.selectClampedFrame,
                            framesPerSecond: _countingFps,
                            showSeconds: widget.hooks.showSeconds,
                            windowBucket: _frameWindowBucket,
                            viewportMainExtent: bodyViewportHeight,
                          ),
                        ),
                        Positioned.fill(
                          child: _buildRailCursorOverlay(geometry),
                        ),
                        // 🚨F-244: the two marks
                        // a drag moves, on a layer
                        // of their own — as the
                        // timeline ruler's.
                        TickOverlay(
                          children: [
                            // UI-R18 #14: the rail's
                            // line follows the live
                            // trim preview so it
                            // never splits from the
                            // body's.
                            if (widget.hooks.cutEndDrag != null &&
                                widget.hooks.dragPreview != null)
                              ValueListenableBuilder<TimelineDragPreview?>(
                                valueListenable: widget.hooks.dragPreview!,
                                builder: (context, preview, _) =>
                                    TimelineRulerCutEndBoundary(
                                      axis: Axis.vertical,
                                      left: timelineFrameEdge(
                                        timelineCutEndPreviewFrameCount(
                                          preview: preview,
                                          cutId:
                                              widget.hooks.cutEndDrag!.cutId,
                                          playbackFrameCount:
                                              widget.hooks.playbackFrameCount,
                                        ),
                                        _metrics.frameCellWidth,
                                      ),
                                    ),
                              )
                            else
                              TimelineRulerCutEndBoundary(
                                axis: Axis.vertical,
                                left: cutEndBoundaryOffset,
                              ),
                            // The のりしろ mark,
                            // transposed: a length
                            // below the cut's end,
                            // riding a drag as the
                            // timeline ruler's does.
                            TimelineRulerNoriShiro(
                              dragPreview: widget.hooks.dragPreview,
                              cutId: widget.hooks.cutEndDrag?.cutId,
                              playbackFrameCount:
                                  widget.hooks.playbackFrameCount,
                              noriShiro: widget.hooks.noriShiro,
                              metrics: _metrics,
                              axis: Axis.vertical,
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const layerAxisScrollbarExtent = timelineBottomScrollbarRailHeight;

    // The law, the glide stop and the overscroll clamp — [TimelineGridShell]
    // carries the PEN-9 / PEN-12 #7 / D43-2 decisions for both grids; this
    // is the horizontal grid's twin.
    return TimelineGridShell(
      ground: colorScheme.surfaceContainerHighest,
      framesPerSecond: _countingFps,
      controllers: [_frameScrollController, _layerScrollController],
      layers: widget.layers,
      child: ValueListenableBuilder<double?>(
        valueListenable: _railExtent,
        builder: (context, _, _) => LayoutBuilder(
          builder: (context, constraints) {
            // The header block is ALWAYS its natural extent; the splitter
            // says how much of it the panel shows. R10 R6 packed the name
            // and R6a scaled the whole column — both are retired, and with
            // them the arithmetic that had to guarantee the sheet a
            // minimum reserve the header could not eat.
            final naturalHeaderBlockExtent = _headers._naturalHeaderBlockExtent;
            // What the sheet can spare for the header block — the ONE
            // value the window, scrollbar and splitter read
            // ([layerRailAvailableExtent]; the header is the rail stood
            // up, so its axis is vertical).
            final availableHeaderExtent = layerRailAvailableExtent(
              constraints,
              railAxis: Axis.vertical,
              scrollbarLaneExtent: layerAxisScrollbarExtent,
            );
            final headerBlockHeight = _railExtent.windowExtent(
              naturalHeaderBlockExtent,
              availableExtent: availableHeaderExtent,
            );
            // The grip's own slot gives ground last: in a panel so short
            // that even a zero-height window plus 5px would overflow
            // (the header sweep goes down to 20px), the slot is what
            // shrinks rather than a yellow stripe appearing.
            final splitterSlotExtent = constraints.hasBoundedHeight
                ? math.min(
                    LayerRailSplitter.thickness,
                    math.max(
                      0.0,
                      constraints.maxHeight -
                          layerAxisScrollbarExtent -
                          headerBlockHeight,
                    ),
                  )
                : LayerRailSplitter.thickness;
            final bodyViewportHeight = constraints.hasBoundedHeight
                ? (constraints.maxHeight -
                          layerAxisScrollbarExtent -
                          headerBlockHeight -
                          splitterSlotExtent)
                      .clamp(0.0, double.infinity)
                      .toDouble()
                : 0.0;
            // Viewport paper fill (UI-R12 #16): the frame column runs to the
            // body's bottom edge — recorded before every consumer of
            // [_renderedFrameCount] below.
            _viewportFillFrameCells = endlessViewportFillFrames(
              viewportExtent: bodyViewportHeight,
              frameCellExtent: _metrics.frameCellWidth,
            );
            _frameAxis.rereadAfterLayout();
            _frameSync.synchronize(
              _frameScroll.effectiveFrameScrollOffset(
                requestedOffset: _frameAxisOffset.value,
                viewportExtent: bodyViewportHeight,
              ),
            );

            // Hidden sections contribute no columns; the section band above
            // the headers carries each section's bracket (shared row/run
            // policy with the horizontal grid).
            final entries = widget.hooks.displayRows(
              widget.layers,
              lanesForLayer: widget.hooks.lanesOf,
              // R9 #23: the sheet's lanes open LEFTWARD — one axis rule
              // with the horizontal grid's downward one, so "further from
              // the layer means applied later" reads the same in both.
              lanesPrecedeLayer: true,
            );
            // The row drag counts COLUMNS and lands on slots; only this
            // list knows how many columns sit between two fx headers.
            _dragRows = entries;
            // The columns' view: the sheet less the frame-number rail and
            // the scrollbar column beside it (the row of three below) —
            // as far as an enlarged graph stands (I-89 ③D).
            final columnsView = constraints.hasBoundedWidth
                ? math.max(
                    0.0,
                    constraints.maxWidth -
                        _metrics.layerControlsWidth -
                        _metrics.verticalScrollbarWidth,
                  )
                : 0.0;
            TimelineRowEdges lay(List<TimelineDisplayRow> laid) =>
                timelineRowEdgesOf(laid, _metrics, view: columnsView);
            _dragEdges = lay(entries);
            // ⚠️AFTER the line above: the sheet draws the silhouette column
            // the timeline draws, and the gap is counted on the list
            // without it ([rowsWithSilhouette]).
            final drawnEntries = rowsWithSilhouette(
              entries,
              widget.hooks.dragPreview?.value,
            );
            // Over the DRAWN columns: the headers and the cells are both
            // built from them.
            _berths = _rowBerths.berthsFor(
              drawnEntries,
              world: widget.hooks.substrateGeneration,
            );
            // Drawn, so the content is one column wider while a file
            // hovers — an extent that forgot it would clip the column it
            // pushed along.
            final columnEdges = identical(drawnEntries, entries)
                ? _dragEdges
                : lay(drawnEntries);
            // The bundles are FIELDS here (the x-sheet reads them from more
            // than one builder), so the assignment stays and only the
            // construction moved.
            _rangeGesture = _rangeGestures.rangeGestureFor(entries);
            _laneRange = _rangeGestures.laneRangeFor(
              entries,
              band: _rangeGesture,
            );
            // The DRAWN columns: the band brackets what is on screen, and a
            // silhouette column standing in the drawing section belongs
            // inside that bracket.
            final sectionRuns = timelineSectionRuns(drawnEntries);

            final totalFrameContentHeight = _frameScroll._totalFrameContentHeight;
            final cutEndBoundaryOffset = timelineCutEndBoundaryX(
              playbackFrameCount: widget.hooks.playbackFrameCount,
              metrics: _metrics,
            );
            // ONE value for the seven numbers above — see [_SheetGeometry].
            final geometry = _SheetGeometry(
              availableHeaderExtent: availableHeaderExtent,
              naturalHeaderBlockExtent: naturalHeaderBlockExtent,
              splitterSlotExtent: splitterSlotExtent,
              bodyViewportHeight: bodyViewportHeight,
              totalFrameContentHeight: totalFrameContentHeight,
              columnEdges: columnEdges,
              cutEndBoundaryOffset: cutEndBoundaryOffset,
            );
            // The DRAWN end, following a live trim so the blue line, the wash
            // edge and the ruler's letters never split from the red line
            // mid-drag (one function, four surfaces).

            return Stack(
              children: [
                Column(
                  children: [
                    // The LAYER axis runs across the sheet, so its scrollbar is
                    // the strip along the top — and the corner at its start, over
                    // the frame axis's bar (F-459-Q1), holds the seconds toggle.
                    SizedBox(
                      height: layerAxisScrollbarExtent,
                      child: Row(
                        children: [
                          TimelineSecondsToggleCorner(
                            key: const ValueKey<String>(
                              'xsheet-time-display-toggle-button',
                            ),
                            width: _metrics.verticalScrollbarWidth,
                            height: layerAxisScrollbarExtent,
                            showSeconds: widget.hooks.showSeconds,
                            onChanged: widget.hooks.onShowSecondsChanged,
                          ),
                          SizedBox(width: _metrics.layerControlsWidth),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) =>
                                  TimelineHorizontalScrollbarRail(
                                    key: const ValueKey<String>(
                                      'xsheet-horizontal-scrollbar',
                                    ),
                                    controller: _layerScrollController,
                                    viewportWidth:
                                        constraints.hasBoundedWidth
                                        ? constraints.maxWidth
                                        : 0.0,
                                    contentWidth: math.max(
                                      geometry.columnsContentWidth,
                                      _metrics.layerRowHeight,
                                    ),
                                    height: layerAxisScrollbarExtent,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ONE column, split by the splitter: the RAIL's
                          // own bar above it, the FRAME axis's below. The
                          // column was already here at 14px carrying only the
                          // frame bar — widening it and halving it was the
                          // whole change (the user saw this before I did).
                          // It stands at the sheet's far left — F-459-Q1
                          // (유저 2026-10-23): 「x시트의 왼쪽 끝을 원함. 룰러랑
                          // 칸 사이가 아님」. ↩️F-409 had stood it at the far
                          // right; before that it stood between the
                          // frame-number rail and the cells.
                          SizedBox(
                            width: _metrics.verticalScrollbarWidth,
                            child: Column(
                              children: [
                                LayerRailScrollbar(
                                  axis: Axis.vertical,
                                  rail: _railExtent,
                                  naturalExtent: naturalHeaderBlockExtent,
                                  availableExtent: availableHeaderExtent,
                                  laneExtent:
                                      _metrics.verticalScrollbarWidth,
                                  keyPrefix: 'xsheet',
                                ),
                                SizedBox(height: splitterSlotExtent),
                                Expanded(
                                  child: _buildVerticalScrollbar(geometry),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: _metrics.layerControlsWidth,
                            child: Column(
                              children: [
                                // R10 R6: the corner is the LEGEND COLUMN now.
                                // It used to read 'Frame' and label nothing —
                                // the sheet was the one grid whose columns had
                                // no headings at all. Same legend widget as the
                                // timeline's, stood up, so each icon lands on
                                // the header slot it names — and inside the same
                                // window, so the two are cut at one line.
                                LayerRailWindow(
                                  axis: Axis.vertical,
                                  rail: _railExtent,
                                  naturalExtent: naturalHeaderBlockExtent,
                                  availableExtent: availableHeaderExtent,
                                  child: _legendRail.header(
                                    axis: Axis.vertical,
                                    metrics: _metrics,
                                    railExtent: naturalHeaderBlockExtent,
                                  ),
                                ),
                                SizedBox(height: splitterSlotExtent),
                                Expanded(
                                  child: _buildRailScrubArea(geometry),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: widget.layers.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: EmptyStateText(
                                      AppText.strings.tlNoLayers,
                                      place: EmptyStatePlace.list,
                                    ),
                                  )
                                : ScrollConfiguration(
                                    // The custom rails ARE the scrollbars — the
                                    // desktop auto-overlay doubled the vertical one
                                    // (UI-R10 #22).
                                    behavior: ScrollConfiguration.of(
                                      context,
                                    ).copyWith(scrollbars: false),
                                    child: TwoAxisDrag(
                                      axes: [
                                        _layerScrollController,
                                        _frameScrollController,
                                      ],
                                      child: _buildLayerHorizontalViewport(
                                        colorScheme,
                                        // THE drawing entrance — the columns
                                        // and their headers come from here,
                                        // so the silhouette column enters
                                        // once, for both.
                                        drawnEntries,
                                        sectionRuns,
                                        geometry,
                                      ),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // The grip floats over the 5px slot all three columns
                // reserve, over the headers. It starts after the
                // frame-number rail: that column is the FRAME axis's and
                // the splitter has nothing to say about it — and the bar
                // column stands before it since F-459-Q1.
                Positioned(
                  left:
                      _metrics.verticalScrollbarWidth +
                      _metrics.layerControlsWidth,
                  right: 0,
                  top: layerAxisScrollbarExtent + headerBlockHeight,
                  height: splitterSlotExtent,
                  child: _buildRailSplitter(geometry),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The vertical frame-number rail: the X-sheet counterpart of the
/// horizontal grid's frame header row, sharing its styling and dim rules.
class _XSheetFrameNumberRail extends StatelessWidget {
  const _XSheetFrameNumberRail({
    required this.frameStartIndex,
    required this.frameEndIndexExclusive,
    required this.playbackFrameCount,
    required this.leadingFrameSpacerHeight,
    required this.trailingFrameSpacerHeight,
    required this.metrics,
    required this.onSelectFrame,
    this.framesPerSecond = 24,
    this.showSeconds = false,
    this.windowBucket,
    this.viewportMainExtent = 0,
    this.playhead,
  });

  final int frameStartIndex;
  final int frameEndIndexExclusive;
  final int playbackFrameCount;
  final double leadingFrameSpacerHeight;
  final double trailingFrameSpacerHeight;
  final TimelineGridMetrics metrics;
  final ValueChanged<int> onSelectFrame;
  final int framesPerSecond;
  final bool showSeconds;

  /// PRO-TIMELINE scrolling (UI-R15→R16): the painter windows itself off
  /// the quantized bucket — pass full bounds, repaint per span crossing.
  final ValueListenable<int>? windowBucket;
  final double viewportMainExtent;

  /// The playhead the rail writes its own pair at (I-16) — a null VALUE
  /// writes none; a rail without one (null) never mounts the writing.
  final ValueListenable<int?>? playhead;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final height =
        leadingFrameSpacerHeight +
        frameRangeVisibleWidth(
          startFrameIndex: frameStartIndex,
          endFrameIndexExclusive: frameEndIndexExclusive,
          frameCellWidth: metrics.frameCellWidth,
        ) +
        trailingFrameSpacerHeight;
    // PAINTERIZED (UI-R14 #1, the ruler's UI-R13 #1 treatment — 통일화):
    // the whole rail is one CustomPaint; per-frame row widgets are gone.
    // Tests probe [TimelineRulerScale.modelAt]/`cellRectFor` through the
    // 'xsheet-frame-rail-paint' key; selection stays on the rail's
    // viewport-level scrub listener.
    final scale = TimelineRulerScale(
      axis: Axis.vertical,
      frameStartIndex: frameStartIndex,
      frameEndIndexExclusive: frameEndIndexExclusive,
      playbackFrameCount: playbackFrameCount,
      leadingFrameSpacer: leadingFrameSpacerHeight,
      crossExtent: metrics.layerControlsWidth,
      metrics: metrics,
      colorScheme: colorScheme,
      face: appFaceOf(DefaultTextStyle.of(context).style),
      numberType: XSheetFrameRailPainter.numberType,
      secondsFontSize: 8,
      framesPerSecond: framesPerSecond,
      showSeconds: showSeconds,
      windowBucket: windowBucket,
      viewportMainExtent: viewportMainExtent,
      // The RAIL grays its past-playback tail where the ruler does
      // not (UI-R18 #9) — see [TimelineRulerScale.pastPlaybackWash].
      pastPlaybackWash: AppColors.washUp.withValues(alpha: 0.72),
    );
    return SizedBox(
      key: const ValueKey<String>('xsheet-frame-number-rail'),
      width: metrics.layerControlsWidth,
      height: height,
      child: timelineRulerStripWithWriting(
        strip: CustomPaint(
          key: const ValueKey<String>('xsheet-frame-rail-paint'),
          size: Size(metrics.layerControlsWidth, height),
          painter: XSheetFrameRailPainter(scale: scale),
        ),
        writingKey: const ValueKey<String>('xsheet-rail-playhead-writing'),
        playhead: playhead,
        writing: (held) => TimelineRulerPlayheadWritingPainter(
          scale: scale,
          playhead: held,
          layout: XSheetFrameRailPainter.glyphsAt,
        ),
      ),
    );
  }
}

/// The X-sheet frame rail as ONE CustomPainter (UI-R14 #1 — the shared
/// ruler's UI-R13 #1 treatment, transposed): number rows, the seconds
/// column, selection tint, playback dimming and the cached strip paint
/// in a single pass. Public for the test probe.
class XSheetFrameRailPainter extends CustomPainter
    with RepaintOnProps, RepaintOnWordBakes {
  XSheetFrameRailPainter({required this.scale})
    : super(repaint: scale.windowBucket);

  /// The frame scale this rail draws — the ruler's, field for field
  /// ([TimelineRulerScale]), the rect and the model with it. Only the paint
  /// is this rail's own.
  final TimelineRulerScale scale;

  @override
  void paintWords(Canvas canvas, Size size) {
    final colorScheme = scale.colorScheme;
    final linePaint = Paint()..strokeWidth = 1;
    // D8 (2026-08-18): the rail used to stroke a faint RECT around every
    // row — no cadence, no 6f/second strengthening, half a pixel off the
    // ruler's snap: one of the "미묘하게 다른 가이드선". It lays its paper
    // and its writing through the very call the horizontal ruler lays its
    // own with ([TimelineRulerScale.paintWindow] — once "the transposed
    // same thing", now the same code); the structural right edge still
    // paints once below.
    scale.paintWindow(canvas, glyphsAt);
    // The cached-range strip moved to [TimelineRulerCursorOverlay] (in its
    // vertical form, hugging the right edge): cached-ness is derived state
    // with no invalidation event, so it must repaint freely rather than
    // ride this gated painter.

    // The structural right edge, full strength, whatever the zoom.
    canvas.drawLine(
      Offset(size.width - 0.5, 0),
      Offset(size.width - 0.5, size.height),
      linePaint..color = colorScheme.outlineVariant,
    );
  }

  /// Where the rail writes at [frameIndex] — the second on the row's
  /// leading corner and the number centred — and with [current] the
  /// playhead's own pair there (I-16), in [timelineRulerPlayheadInk] as the
  /// ruler writes it.
  static List<TimelineGlyphPlacement> glyphsAt(
    TimelineRulerScale scale,
    int frameIndex, {
    required bool current,
  }) {
    final writing = scale.writingAt(frameIndex, current: current);
    final rect = scale.cellRectFor(frameIndex);
    final colorScheme = scale.colorScheme;
    final glyphs = <TimelineGlyphPlacement>[];
    // Seconds on the row's leading CORNER (UI-R10 #27): the second (counted
    // from 0, [timelineRulerSecondsLabel]) prints bold on its boundary row.
    //
    // R10 R6: the rail narrowed 72 → 28 with the frame-number rail now
    // derived from the ruler's height, and a centred 14pt three-digit
    // number filled the whole 28px — straight through a seconds glyph
    // that sat beside it. Both numbers converge on the SHARED ruler's
    // answers instead of the sheet growing an exception: the corner
    // placement ([secondsCornerGlyph]) and the 11pt base.
    // ⚠️A point smaller than the horizontal ruler: the rail narrowed to
    // 28px (R10 R6). The CORNER is the shared answer, the size is not.
    final second = secondsCornerGlyph(rect, (
      text: writing.second,
      fontSize: scale.secondsFontSize,
      color: scale.secondsInk(current: current),
      face: scale.face,
    ));
    if (second != null) {
      glyphs.add(second);
    }
    if (writing.number.isNotEmpty) {
      // Set in the type the cadence measured ([TimelineRulerScale.numberType]).
      final style = scale
          .numberTypeAt(everyFrame: scale.labelEveryFrames == 1)
          .copyWith(
            color: scale.modelAt(frameIndex).outsidePlaybackRange
                ? colorScheme.onSurfaceVariant.withValues(alpha: 0.55)
                : colorScheme.onSurface,
          );
      final painter = laidOutGlyph(
        writing.number,
        scale.inkOf(style, current: current),
      );
      // Every row's number stands in a row of its own, so every one narrows
      // into it the way the ruler's do ([TimelineRulerScale.numberFitIn]).
      final fit = scale.numberFitIn(rect, painter);
      glyphs.add((
        painter: painter,
        offset: Offset(
          rect.center.dx - painter.width * fit.x / 2,
          rect.center.dy - painter.height / 2,
        ),
        fit: fit,
      ));
    }
    return glyphs;
  }

  /// The type the RAIL sets its numbers in ([TimelineRulerScale.numberType]):
  /// fitted into its row, at every cadence.
  ///
  /// R9 #4: the number SHRINKS to fit its row before it thins out — the
  /// horizontal ruler's rule, through the same helper. The 14 was
  /// hard-coded, so a zoomed-out row printed a 14pt glyph into a 6px
  /// slot.
  static TextStyle numberType(
    TimelineRulerScale scale, {
    required bool everyFrame,
  }) => scale.face.copyWith(
    // 14 → 11, the SHARED ruler's base (R10 R6). The 14 was the sheet's
    // own number, affordable only while the rail was 72 wide.
    fontSize: timelineFittedGlyphFontSize(
      11,
      scale.metrics.frameCellWidth,
      crossExtent: scale.crossExtent,
    ),
  );

  // Shared laid-out-TextPainter cache (UI-R16): rail numbers repeat
  // across repaints — fresh layout per label was the debug hot spot.
  @override
  Object get props => (scale,);

  // ↩️Every row got a node, because "the rail numbers every frame" — which
  // stopped being so when its numbers began to thin with the ruler's
  // (R9 #4). A node stands where a number is written, the ruler's code
  // ([TimelineRulerScale.windowSemantics]).
  @override
  SemanticsBuilderCallback get semanticsBuilder =>
      (size) => scale.windowSemantics();
}

/// One cell of the section band above the layer headers: the paper sheet's
/// group heading wrapping its columns. Display-only — section visibility
/// lives on the toolbar toggles. The band label is horizontal already (the
/// band runs along the layer axis here).
class _XSheetSectionBandCell extends StatelessWidget {
  const _XSheetSectionBandCell({
    required this.run,
    required this.extent,
    required this.height,
  });

  /// Resolved per layout: the strip gives ground with the block (R10 R6).
  final double height;

  final TimelineSectionRun run;
  final double extent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Container(
        width: extent,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.washDown,
          border: Border.all(color: colorScheme.outline, width: 1),
        ),
        // The band runs ALONG the layer axis, so its label stays
        // horizontal. It used to SHRINK into a narrow run; the rail-window
        // round retired that everywhere on screen, so a one-column run
        // ellipsises like any other label that outgrows its slot.
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              timelineSectionLabel(run.section),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 1.2,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The x-sheet's per-pass geometry: what one build computed from its
/// constraints and rows, and every slot below it reads.
///
/// Seven locals in one builder scope said this before it had a name,
/// which meant the layer viewport slot needed ten parameters to leave
/// build. The same finding as the layer grid's [_RowWindow]: when the
/// parameter list explodes, something has no name.
class _SheetGeometry {
  const _SheetGeometry({
    required this.availableHeaderExtent,
    required this.naturalHeaderBlockExtent,
    required this.splitterSlotExtent,
    required this.bodyViewportHeight,
    required this.totalFrameContentHeight,
    required this.columnEdges,
    required this.cutEndBoundaryOffset,
  });

  /// What the sheet can spare for the header block, or null when the
  /// height is unbounded.
  final double? availableHeaderExtent;
  final double naturalHeaderBlockExtent;
  final double splitterSlotExtent;
  final double bodyViewportHeight;
  final double totalFrameContentHeight;

  /// Where the DRAWN columns sit across the sheet — the rail's
  /// [TimelineRowEdges], turned on its side.
  final TimelineRowEdges columnEdges;
  final double cutEndBoundaryOffset;

  double get columnsContentWidth => columnEdges.total;
}

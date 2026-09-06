import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/layer.dart';
import '../../models/attached_layer_resolve.dart'
    show attachRowWearsBaseComposite;
import '../../models/layer_kind.dart';
import '../text/app_strings.dart' show AppText;
import '../theme/app_theme.dart';
import 'layer_label_controls.dart';
import 'layer_rail_columns.dart';
import 'rail_column_swipe.dart';
import 'layer_rail_window.dart';
import 'frame_window_semantics.dart';

import 'timeline_grid_range_gestures.dart';
import 'timeline_scroll_offset_sync.dart';
import 'timeline_frame_axis_follower.dart';
import 'timeline_cell_style.dart';
import 'timeline_frame_ruler_painter.dart'
    show TimelineRulerHeaderModel, TimelineRulerScale, timelineRulerSecondsLabel;
import 'timeline_cut_end_handle.dart';
import 'timeline_drag_preview.dart';
import '../../models/project_frame_rate.dart';
import '../../models/timeline_row_address.dart';
import 'timeline_selected_exposure_outline.dart' show TimelineRowSelectionBands;
import 'effect_lane_policy.dart' show parseEffectLaneId;
import 'layer_drop_policy.dart'
    show effectChainAfterCrossing, effectHeaderRowsOf;
import 'layer_row_drag.dart';
import 'timeline_edge_auto_pan.dart';
import 'timeline_frame_range_gesture.dart';
import 'timeline_ruler_cursor_overlay.dart';
import 'timeline_frame_cells_row.dart' show TimelineFrameCellsRow;
import 'timeline_frame_geometry.dart'
    show TimelineFrameGeometry, timelineFrameWindowMarginPx;
import 'timeline_frame_coordinate_policy.dart';
import 'timeline_frame_cursor_layer.dart';
import 'timeline_beat_lines.dart';
import 'timeline_frame_range_policy.dart';
import 'timeline_frame_window.dart';
import 'timeline_glyph_cache.dart';
import 'property_lane_model.dart';
import 'timeline_grid_metrics.dart';
import 'se_audio_lane.dart';
import 'timeline_lane_rows.dart';
import 'timeline_horizontal_offset_policy.dart';
import 'timeline_layer_controls_header.dart';
import '../input/pen_friendly_scroll_controller.dart';
import 'timeline_grid_shell.dart';
import 'timeline_horizontal_scrollbar_rail.dart';
import 'timeline_ruler_cut_end_boundary.dart';
import 'timeline_ruler_norishiro_boundary.dart';
import 'timeline_section_policy.dart';
import 'timeline_section_runs.dart';
import 'timeline_vertical_scrollbar_rail.dart';
import 'timeline_virtualization_plan.dart';
import 'timeline_visible_range.dart';
import 'timeline_zoom_anchor_policy.dart';
import 'timeline_frame_grid_stack.dart';
import 'timeline_layer_controls_row.dart';
import '../layout/device_grid_scroll_controller.dart';
import 'timeline_grid_hooks.dart';
import 'timeline_swipe_columns.dart';
import '../repaint_props.dart';

part 'xsheet_grid/xsheet_grid_rail_scrub.dart';
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
/// horizontal grid uses — frame range, offset resolution, virtualization
/// plan, coordinate conversion, cell style/block visuals, selected exposure
/// range, playhead visibility, cut-end boundary — is reused unchanged with
/// the axes swapped; only the thin widget composition differs.
class XSheetTimelineGrid extends StatefulWidget {
  const XSheetTimelineGrid({
    super.key,
    required this.hooks,
    required this.layers,
    this.railExtent,
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
  /// column. That equality is the point: making the rail compact makes the
  /// sheet's header shallow, with nothing to remember.
  ///
  /// R10 R6 shed columns a short panel could not afford; the user's call
  /// was the opposite — "타임라인에 있는거 싹다 넣어. 뭐 빼지말고" — and
  /// R6a answered it by scaling the whole column down. Both are gone. The
  /// block is ALWAYS this tall, and a panel that cannot spend it sees a
  /// narrower WINDOW onto it (the rail-window round): the tail is cut, the
  /// splitter says where, and nothing inside rearranges.
  ///
  /// [hasOnionColumn]/[hasBlendColumn] are the HOST's answer about which
  /// optional columns exist at all — the legend beside the headers must
  /// size from the same answer or its icons stop naming the columns under
  /// them.
  static double naturalHeaderBlockExtent({
    required bool hasOnionColumn,
    required bool hasBlendColumn,
  }) =>
      _sectionBandHeight +
      (layerRailLeadingWidth - layerSectionLabelSlotWidth) +
      _naturalNameExtent +
      layerRailTrailingWidth(
        hasOnionColumn: hasOnionColumn,
        hasBlendColumn: hasBlendColumn,
      ) +
      _headerBorderExtent;

  /// The NAME's share of the rail — what the horizontal row's `Expanded`
  /// resolves to once every slot has been served.
  static const double _naturalNameExtent =
      timelineLayerControlsWidth -
      layerRailLeadingWidth -
      layerFillReferenceSlotWidth -
      layerFxSlotWidth -
      layerOnionSlotWidth -
      layerVisibilitySlotWidth -
      layerMuteSlotWidth -
      layerOpacitySlotWidth -
      layerBlendSlotWidth;

  /// The column header's own hairlines, top and bottom.
  static const double _headerBorderExtent = 2;

  @override
  State<XSheetTimelineGrid> createState() => _XSheetTimelineGridState();
}

class _XSheetTimelineGridState extends State<XSheetTimelineGrid> {
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

  // ── the rail scrub: its own object, in its own file ─────────────────
  //
  // A collaborator (timeline/xsheet_grid/xsheet_grid_rail_scrub.dart, a part of this
  // library). The State keeps the entry points its build tree calls.
  late final _XSheetGridRailScrub _railScrub = _XSheetGridRailScrub(this);

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

  late final ScrollController _frameScrollController;
  late final ScrollController _layerScrollController;

  /// Frame-axis offset + window bucket notifiers (UI-R9 #12a, the
  /// horizontal grid's structure transposed): scroll pixels move the rail
  /// translate only; cell crossings re-window the columns; the grid never
  /// rebuilds per pixel.
  final ValueNotifier<double> _frameAxisOffset = ValueNotifier<double>(0);
  final ValueNotifier<int> _frameWindowBucket = ValueNotifier<int>(0);
  double _lastEffectiveFrameScrollOffset = 0;

  /// The frame axis following its controller — the rail's follower, the
  /// same object, transposed by nothing but which controller it holds.
  late final TimelineFrameAxisFollower _frameAxis = TimelineFrameAxisFollower(
    controller: _frameScrollController,
    frameAxisOffset: _frameAxisOffset,
    frameWindowBucket: _frameWindowBucket,
    cellExtent: () => _metrics.frameCellWidth,
    baseFrameCount: () => _rangeGestures.frameRangePolicy.visibleFrameCount,
    rebuild: _rebuild,
    isMounted: () => mounted,
  );

  /// UI-R9 #9, transposed to y: the frame axis pulled to the offset the
  /// layout resolved, one frame later — the rail's object.
  late final TimelineScrollOffsetSync _frameSync = TimelineScrollOffsetSync(
    _frameScrollController,
    isMounted: () => mounted,
  );
  final GlobalKey _railScrubViewportKey = GlobalKey();
  final FrameScrubDedupe _railScrubbedFrame = FrameScrubDedupe();

  TimelineGridMetrics get _metrics => widget.metrics;

  @override
  void initState() {
    super.initState();
    // PEN-10: pen-friendly positions — while a stylus is nearby, a
    // coasting fling stops hiding the cells from hit-testing.
    _frameScrollController = PenFriendlyScrollController();
    _layerScrollController = PenFriendlyScrollController();
    _frameScrollController.addListener(_frameAxis.handleScroll);
    _frameWindowBucket.addListener(_frameScroll.handleFrameWindowBucket);
    widget.hooks.revealSelectionTick?.addListener(_reveal.handleRevealSelection);
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
    _frameAxis.dispose();
    _frameScrollController
      ..removeListener(_frameAxis.handleScroll)
      ..dispose();
    _layerScrollController.dispose();
    _frameWindowBucket.removeListener(_frameScroll.handleFrameWindowBucket);
    _frameGeometry.dispose();
    _windowedFrameGeometry.dispose();
    _frameAxisOffset.dispose();
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
        rangeMove: _rangeMoveResolver,
      );

  /// Frame cells the current viewport needs to be fully papered (UI-R12
  /// #16) — recorded by build's outer LayoutBuilder. Zero until layout.
  int _viewportFillFrameCells = 0;

  List<PropertyLaneRow> _lanesFor(Layer layer) =>
      widget.hooks.lanesForLayer?.call(layer) ?? const [];

  /// The row's fold twirl — [timelineGroupFoldFor] bound to this grid's hooks.
  TimelineGroupFold _groupFoldFor(TimelineDisplayRow row) =>
      timelineGroupFoldFor(
        row: row,
        layers: widget.layers,
        collapsedAttachBaseIds: widget.hooks.collapsedAttachBaseIds,
        onToggleLayerCollapsed: widget.hooks.onToggleLayerCollapsed,
        onToggleAttachGroup: widget.hooks.onToggleAttachGroup,
      );

  /// One column wrapped in its repaint boundary + drag-preview gate: an
  /// edge-drag step re-runs the builder with the preview layer substituted
  /// for the drag target's column only.
  /// One lane's HEADER cell — the transposed rail row.
  ///
  /// Lane headers show the value AT the cursor, so they subscribe to the
  /// cursor here and a tick rebuilds only these cells. R10 adds the drag
  /// gate for the same reason the horizontal rail has it: the blue value
  /// column must follow a key move per step, not sit on the committed
  /// track until the pointer lifts.
  /// The display entries of the pass in flight, for the drag's row → slot
  /// conversion (see [effectHeaderRowsOf]).
  List<TimelineDisplayRow> _dragRows = const [];

  /// The shared virtualization plan with the frame axis fed through the
  /// "horizontal" inputs (the axes are swapped in this grid). Read INSIDE
  /// the window-bucket subscribers (UI-R9 #12a): scroll pixels re-window
  /// nothing. Was a local function of build; two slots call it.
  TimelineVirtualizationPlan _framePlan(
    double bodyViewportHeight,
    List<TimelineDisplayRow> entries,
  ) => calculateTimelineVirtualizationPlan(
    horizontalScrollOffset: _frameScroll.effectiveFrameScrollOffset(
      requestedOffset: _frameAxisOffset.value,
      viewportExtent: bodyViewportHeight,
    ),
    verticalScrollOffset: 0,
    viewportWidth: bodyViewportHeight,
    viewportHeight: 0,
    frameCellWidth: _metrics.frameCellWidth,
    layerRowHeight: _metrics.layerRowHeight,
    frameCount: _frameScroll.renderedFrameCount,
    layerCount: entries.length,
  );

  /// Where the drawn end sits, for the rail's drawn-end mark — the same
  /// product the body stack's wash and blue line read.
  double _drawnEndOffset(TimelineDragPreview? preview) =>
      timelineDrawnEndOffset(
        preview: preview,
        cutId: widget.hooks.cutEndDrag?.cutId,
        playbackFrameCount: widget.hooks.playbackFrameCount,
        drawnFrameCount: widget.hooks.drawnFrameCount,
        frameCellExtent: _metrics.frameCellWidth,
      );

  Widget _buildRailSplitter(_SheetGeometry geometry) {
    final availableHeaderExtent = geometry.availableHeaderExtent;
    final naturalHeaderBlockExtent = geometry.naturalHeaderBlockExtent;
    return LayerRailSplitter(
      key: const ValueKey<String>('xsheet-rail-splitter'),
      axis: Axis.vertical,
      extent: _railScrub._railExtent,
      naturalExtent: naturalHeaderBlockExtent,
      availableExtent: availableHeaderExtent,
    );
  }

  Widget _buildBeatLines(ColorScheme colorScheme) {
    return CustomPaint(
      key: const ValueKey<String>('xsheet-beat-lines'),
      painter: TimelineBeatLinesPainter(
        axis: Axis.vertical,
        frameCellExtent: _metrics.frameCellWidth,
        crossCellExtent: _metrics.layerRowHeight,
        framesPerSecond: _countingFps,
        colorScheme: colorScheme,
        // D43: the sheet host's Material colour.
        ground: colorScheme.surfaceContainerHighest,
      ),
    );
  }

  Widget _buildFrameVerticalViewport(
    ColorScheme colorScheme,
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
          // Pixels scroll the real viewport; only cell crossings re-window
          // the columns (UI-R9 #12a).
          child: ValueListenableBuilder<int>(
            valueListenable: _frameWindowBucket,
            builder: (context, _, _) {
              final plan = _framePlan(bodyViewportHeight, entries);
              // The timeline's stack, turned on its side: beat lines under
              // the columns (D32), the cursor layer over them, and where the
              // film stops stated over everything (the user's layer order).
              return TimelineFrameGridStack(
                axis: Axis.vertical,
                rowsBody: _columns.buildColumns(entries, plan, bodyViewportHeight),
                beatLines: _buildBeatLines(colorScheme),
                playheadExtent: geometry.totalFrameContentHeight,
                playhead: _buildCursorLayer(entries, plan),
                cutEndDrag: widget.hooks.cutEndDrag,
                dragPreview: widget.hooks.dragPreview,
                frameCellExtent: _metrics.frameCellWidth,
                playbackFrameCount: widget.hooks.playbackFrameCount,
                drawnFrameCount: widget.hooks.drawnFrameCount,
              );
            },
          ),
        ),
      ),
    );
  }

  /// The cursor layer carries the playhead + selection visuals; ticks
  /// repaint it alone.
  Widget _buildCursorLayer(
    List<TimelineDisplayRow> entries,
    TimelineVirtualizationPlan plan,
  ) {
    final frameRange = plan.frameRange;
    return TimelineCursorLayer(
      axis: Axis.vertical,
      currentRow: widget.hooks.currentRowHooks?.currentRow,
      selectedSemanticsKey: const ValueKey<String>('xsheet-selected-cell'),
      frameRangeSelection: widget.hooks.rangeHooks?.selection,
      // R27 #14: one band for cells and lanes alike.
      laneRangeSelection: widget.hooks.laneRange?.selection,
      frameCursor: widget.hooks.frameCursor,
      dragPreview: widget.hooks.dragPreview,
      rows: entries,
      activeLayerId: widget.hooks.activeLayerId,
      frameStartIndex: frameRange.startIndex,
      frameEndIndexExclusive: frameRange.endIndexExclusive,
      leadingFrameSpacerWidth: plan.leadingFrameSpacerWidth,
      metrics: _metrics,
      exposureStateForLayer: widget.hooks.exposureStateForLayer,
      crossAxisExtent: entries.length * _metrics.layerRowHeight,
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
              LayerRailWindow(
                axis: Axis.vertical,
                rail: _railScrub._railExtent,
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
                              entries,
                              _metrics,
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
                        // 🚨The rail's bulk-drag, TURNED ON ITS SIDE. Same widget, same
                        // columns; the x-sheet is the rail transposed, so the sweep runs
                        // ACROSS the layer columns instead of down the rows.
                        RailColumnSwipe<TimelineDisplayRow>(
                          axis: Axis.horizontal,
                          columns: _columns.swipeColumns(),
                          rowAt: (along) => _columns.columnAtX(along, entries),
                          child: Row(
                            children: [
                              for (
                                var index = 0;
                                index < entries.length;
                                index += 1
                              )
                                _headers.draggableHeader(
                                  entries[index],
                                  _headers.headerFor(entries[index]),
                                ),
                            ],
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
                            rowExtent: _metrics.layerRowHeight,
                            leadingSpacer: 0,
                            crossExtent: _headers.naturalHeaderExtent,
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
                    colorScheme,
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
      width: _metrics.verticalScrollbarWidth,
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
      isFrameReady: widget.hooks.isFrameReady,
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
        _railScrub.resetRailScrubTracking();
        _railScrub.selectFrameFromRailGlobalPosition(event.position, autoPan: false);
      },
      onPointerUp: (_) => _railScrub.endRailScrub(),
      onPointerCancel: (_) => _railScrub.endRailScrub(),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragStart: (details) {
          _railScrub.selectFrameFromRailGlobalPosition(
            details.globalPosition,
            autoPan: false,
          );
        },
        onVerticalDragUpdate: (details) {
          _railScrub.selectFrameFromRailGlobalPosition(details.globalPosition);
        },
        onVerticalDragEnd: (_) => _railScrub.resetRailScrubTracking(),
        onVerticalDragCancel: _railScrub.resetRailScrubTracking,
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
            child: ValueListenableBuilder<double>(
              valueListenable: _frameAxisOffset,
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
                            // The tint lives in the
                            // overlay now.
                            currentFrameIndex: -1,
                            playbackFrameCount: widget.hooks.playbackFrameCount,
                            leadingFrameSpacerHeight: 0,
                            trailingFrameSpacerHeight: 0,
                            metrics: _metrics,
                            onSelectFrame: _railScrub.selectClampedFrameFromRail,
                            framesPerSecond: _countingFps,
                            showSeconds: widget.hooks.showSeconds,
                            windowBucket: _frameWindowBucket,
                            viewportMainExtent: bodyViewportHeight,
                          ),
                        ),
                        Positioned.fill(
                          child: _buildRailCursorOverlay(geometry),
                        ),
                        // UI-R18 #14: the rail's
                        // line follows the live
                        // trim preview so it never
                        // splits from the body's.
                        if (widget.hooks.cutEndDrag != null &&
                            widget.hooks.dragPreview != null)
                          ValueListenableBuilder<TimelineDragPreview?>(
                            valueListenable: widget.hooks.dragPreview!,
                            builder: (context, preview, _) =>
                                TimelineRulerCutEndBoundary(
                                  axis: Axis.vertical,
                                  left:
                                      timelineCutEndPreviewFrameCount(
                                        preview: preview,
                                        cutId: widget.hooks.cutEndDrag!.cutId,
                                        playbackFrameCount:
                                            widget.hooks.playbackFrameCount,
                                      ) *
                                      _metrics.frameCellWidth,
                                ),
                          )
                        else
                          TimelineRulerCutEndBoundary(
                            axis: Axis.vertical,
                            left: cutEndBoundaryOffset,
                          ),
                        // The のりしろ boundary,
                        // transposed: a length
                        // below the cut's end.
                        TimelineRulerNoriShiroBoundary(
                          axis: Axis.vertical,
                          cutEnd: cutEndBoundaryOffset,
                          drawnEnd: _drawnEndOffset(null),
                          label: widget.hooks.noriShiroLabel,
                        ),
                      ],
                    ),
                  );
                },
              ),
              // R9 #3 (transposed): the RAW scroll
              // position, overscroll included —
              // the clamp is for correcting the
              // CONTROLLER, not for paint.
              builder: (context, offset, child) {
                _lastEffectiveFrameScrollOffset = offset;
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
                return DeviceGridScrollBody(
                  controller: _frameScrollController,
                  axisDirection: AxisDirection.down,
                  child: Transform.translate(
                    offset: Offset(0, -offset),
                    child: child,
                  ),
                );
              },
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
      child: ValueListenableBuilder<double?>(
        valueListenable: _railScrub._railExtent,
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
            final headerBlockHeight = _railScrub._railExtent.windowExtent(
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
            _lastEffectiveFrameScrollOffset = _frameAxisOffset.value;
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
              lanesForLayer: _lanesFor,
              // R9 #23: the sheet's lanes open LEFTWARD — one axis rule
              // with the horizontal grid's downward one, so "further from
              // the layer means applied later" reads the same in both.
              lanesPrecedeLayer: true,
            );
            // The row drag counts COLUMNS and lands on slots; only this
            // list knows how many columns sit between two fx headers.
            _dragRows = entries;
            // The bundles are FIELDS here (the x-sheet reads them from more
            // than one builder), so the assignment stays and only the
            // construction moved.
            _rangeGesture = _rangeGestures.rangeGestureFor(entries);
            _laneRange = _rangeGestures.laneRangeFor(entries);
            final sectionRuns = timelineSectionRuns(entries);

            // The shared virtualization plan with the frame axis fed through the
            // "horizontal" inputs (the axes are swapped in this grid). Computed
            // INSIDE the window-bucket subscribers (UI-R9 #12a): scroll pixels
            // re-window nothing.
            final totalFrameContentHeight = _frameScroll._totalFrameContentHeight;
            // Every column is ONE width (`timelineDisplayRowExtent` returns
            // `layerRowHeight` unconditionally). The old note here claimed
            // collapsed sections folded to a slim strip; they never did, and
            // believing it would send someone to the height-table row
            // resolver when `uniformRowDeltaForCrossOffset` — which requires
            // this uniformity — is the right one.
            final columnsContentWidth = timelineDisplayRowsExtent(
              entries,
              _metrics,
            );
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
              columnsContentWidth: columnsContentWidth,
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
                    // the strip along the top — and the corner beside it holds
                    // the seconds toggle, off the command bar.
                    SizedBox(
                      height: layerAxisScrollbarExtent,
                      child: Row(
                        children: [
                          SizedBox(width: _metrics.layerControlsWidth),
                          TimelineSecondsToggleCorner(
                            key: const ValueKey<String>(
                              'xsheet-time-display-toggle-button',
                            ),
                            width: _metrics.verticalScrollbarWidth,
                            height: layerAxisScrollbarExtent,
                            showSeconds: widget.hooks.showSeconds,
                            onChanged: widget.hooks.onShowSecondsChanged,
                          ),
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
                                      columnsContentWidth,
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
                                  rail: _railScrub._railExtent,
                                  naturalExtent: naturalHeaderBlockExtent,
                                  availableExtent: availableHeaderExtent,
                                  child: TimelineLayerControlsHeader(
                                    axis: Axis.vertical,
                                    metrics: _metrics,
                                    railExtent: naturalHeaderBlockExtent,
                                    // The legend has no flyouts here to infer
                                    // the optional columns from, so it is told
                                    // what the ROWS carry — or its icons stop
                                    // naming the columns under them.
                                    hasOnionColumn:
                                        widget
                                            .hooks
                                            .onToggleLayerOnionSkin !=
                                        null,
                                    hasBlendColumn:
                                        widget
                                            .hooks
                                            .onLayerBlendModeSelected !=
                                        null,
                                    hiddenSections:
                                        widget.hooks.hiddenSections,
                                  ),
                                ),
                                SizedBox(height: splitterSlotExtent),
                                Expanded(
                                  child: _buildRailScrubArea(geometry),
                                ),
                              ],
                            ),
                          ),
                          // ONE 16px column, split by the splitter: the RAIL's
                          // own bar above it, the FRAME axis's below. The
                          // column was already here at 14px carrying only the
                          // frame bar — widening it and halving it is the whole
                          // change (the user saw this before I did).
                          SizedBox(
                            width: _metrics.verticalScrollbarWidth,
                            child: Column(
                              children: [
                                LayerRailScrollbar(
                                  axis: Axis.vertical,
                                  rail: _railScrub._railExtent,
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
                          Expanded(
                            child: widget.layers.isEmpty
                                ? Align(
                                    alignment: Alignment.topLeft,
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Text(
                                        AppText.strings.tlNoLayers,
                                        style: TextStyle(
                                          color:
                                              colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  )
                                : ScrollConfiguration(
                                    // The custom rails ARE the scrollbars — the
                                    // desktop auto-overlay doubled the vertical one
                                    // (UI-R10 #22).
                                    behavior: ScrollConfiguration.of(
                                      context,
                                    ).copyWith(scrollbars: false),
                                    child: _buildLayerHorizontalViewport(
                                      colorScheme,
                                      entries,
                                      sectionRuns,
                                      geometry,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // The grip floats over the 5px slot all three columns
                // reserve, so one grab spans the legend, the scrollbar
                // column and the headers. It starts after the frame-number
                // rail: that column is the FRAME axis's and the splitter
                // has nothing to say about it.
                Positioned(
                  left: _metrics.layerControlsWidth,
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
    required this.currentFrameIndex,
    required this.playbackFrameCount,
    required this.leadingFrameSpacerHeight,
    required this.trailingFrameSpacerHeight,
    required this.metrics,
    required this.onSelectFrame,
    this.framesPerSecond = 24,
    this.showSeconds = false,
    this.windowBucket,
    this.viewportMainExtent = 0,
  });

  final int frameStartIndex;
  final int frameEndIndexExclusive;
  final int currentFrameIndex;
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final height =
        leadingFrameSpacerHeight +
        (frameEndIndexExclusive - frameStartIndex) * metrics.frameCellWidth +
        trailingFrameSpacerHeight;
    // PAINTERIZED (UI-R14 #1, the ruler's UI-R13 #1 treatment — 통일화):
    // the whole rail is one CustomPaint; per-frame row widgets are gone.
    // Tests probe [XSheetFrameRailPainter.modelAt]/`rowRectFor` through
    // the 'xsheet-frame-rail-paint' key; selection stays on the rail's
    // viewport-level scrub listener.
    return SizedBox(
      key: const ValueKey<String>('xsheet-frame-number-rail'),
      width: metrics.layerControlsWidth,
      height: height,
      child: CustomPaint(
        key: const ValueKey<String>('xsheet-frame-rail-paint'),
        size: Size(metrics.layerControlsWidth, height),
        painter: XSheetFrameRailPainter(
          scale: TimelineRulerScale(
            frameStartIndex: frameStartIndex,
            frameEndIndexExclusive: frameEndIndexExclusive,
            currentFrameIndex: currentFrameIndex,
            playbackFrameCount: playbackFrameCount,
            leadingFrameSpacer: leadingFrameSpacerHeight,
            metrics: metrics,
            colorScheme: colorScheme,
            framesPerSecond: framesPerSecond,
            showSeconds: showSeconds,
            windowBucket: windowBucket,
            viewportMainExtent: viewportMainExtent,
          ),
        ),
      ),
    );
  }
}

/// The X-sheet frame rail as ONE CustomPainter (UI-R14 #1 — the shared
/// ruler's UI-R13 #1 treatment, transposed): number rows, the seconds
/// column, selection tint, playback dimming and the cached strip paint
/// in a single pass. Public for the test probe.
class XSheetFrameRailPainter extends CustomPainter with RepaintOnProps {
  XSheetFrameRailPainter({required this.scale})
    : super(repaint: scale.windowBucket);

  /// The frame scale this rail draws — the ruler's, field for field
  /// ([TimelineRulerScale]); only the rect and the paint are transposed.
  final TimelineRulerScale scale;

  /// The row's rect in the rail's local coordinates.
  Rect rowRectFor(int frameIndex) => Rect.fromLTWH(
    0,
    scale.leadingFrameSpacer +
        (frameIndex - scale.frameStartIndex) * scale.metrics.frameCellWidth,
    scale.metrics.layerControlsWidth,
    scale.metrics.frameCellWidth,
  );

  /// The resolved per-row model — the probe surface (the shared ruler's
  /// model class).
  ///
  /// R9 #4: the cadence is the SHARED one now
  /// ([TimelineGridMetrics.frameLabelEveryFrames], the paper-timesheet
  /// ladder anchored at frame 1). This painter is a transposed
  /// re-implementation of the horizontal ruler and had never called it —
  /// so zooming out crowded every row's number into the next, while the
  /// horizontal ruler thinned out correctly. A ruler is a SCALE, not cell
  /// content: the "never disappears" rule is about what a cell holds.
  TimelineRulerHeaderModel modelAt(int frameIndex) {
    final selected = frameIndex == scale.currentFrameIndex;
    final outside = frameIndex >= scale.playbackFrameCount;
    final labeled = frameIndex % scale.metrics.frameLabelEveryFrames == 0;
    return TimelineRulerHeaderModel(
      frameIndex: frameIndex,
      label: labeled ? scale.frameNumberLabel(frameIndex) : '',
      secondsLabel: timelineRulerSecondsLabel(
        frameIndex: frameIndex,
        framesPerSecond: scale.framesPerSecond,
      ),
      selected: selected,
      outsidePlaybackRange: outside,
      background: selected
          ? Color.alphaBlend(
              timelineSelectedFrameBorderColor.withValues(alpha: 0.12),
              scale.colorScheme.surface,
            )
          : outside
          ? AppColors.washUp.withValues(alpha: 0.72)
          : scale.colorScheme.surface,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final metrics = scale.metrics;
    final colorScheme = scale.colorScheme;
    final fillPaint = Paint();
    final linePaint = Paint()..strokeWidth = 1;
    // D8 (2026-08-18): the rail used to stroke a faint RECT around every
    // row — no cadence, no 6f/second strengthening, half a pixel off the
    // ruler's snap: one of the "미묘하게 다른 가이드선". It consults THE
    // boundary-line law now, exactly like the horizontal ruler's PASS 2
    // (the transposed same thing); the structural right edge still paints
    // once below.
    final boundaryPaint = Paint();

    // Self-windowing (UI-R15): only the rows under the live viewport
    // record — a scroll is a repaint of this thin pass, never a rebuild.
    final window = scale.visibleWindow();
    for (
      var frameIndex = window.startIndex;
      frameIndex < window.endIndexExclusive;
      frameIndex += 1
    ) {
      final model = modelAt(frameIndex);
      final rect = rowRectFor(frameIndex);
      canvas.drawRect(rect, fillPaint..color = model.background);
      final ink = timelineFrameBoundaryLineInk(
        frameIndex: frameIndex,
        frameCellExtent: metrics.frameCellWidth,
        framesPerSecond: scale.framesPerSecond,
        colorScheme: colorScheme,
      );
      if (ink != null) {
        final position = rect.top + timelineGridLineSnap;
        canvas.drawLine(
          Offset(rect.left, position),
          Offset(rect.right, position),
          boundaryPaint
            ..color = ink.color
            ..strokeWidth = ink.strokeWidth,
        );
      }

      // Seconds on the row's leading CORNER (UI-R10 #27): the 1-based
      // second prints bold on its boundary row.
      //
      // R10 R6: the rail narrowed 72 → 28 with the frame-number rail now
      // derived from the ruler's height, and a centred 14pt three-digit
      // number filled the whole 28px — straight through a seconds glyph
      // that sat beside it. Both numbers converge on the SHARED ruler's
      // answers instead of the sheet growing an exception: the corner
      // placement (`rect.left + 2, rect.top + 1` there) and the 11pt base.
      // ⚠️A point smaller than the horizontal ruler: the rail narrowed to
      // 28px (R10 R6). The CORNER is the shared answer, the size is not.
      paintSecondsCorner(canvas, rect, (
        text: model.secondsLabel,
        fontSize: 8,
        color: colorScheme.onSurfaceVariant,
      ));

      if (model.label.isNotEmpty) {
        // R9 #4: the number SHRINKS to fit its row before it thins out —
        // the horizontal ruler's rule, through the same helper. The 14 was
        // hard-coded, so a zoomed-out row printed a 14pt glyph into a 6px
        // slot.
        final number = timelineGlyphPainter(
          model.label,
          TextStyle(
            // 14 → 11, the SHARED ruler's base (R10 R6). The 14 was the
            // sheet's own number, affordable only while the rail was 72
            // wide.
            fontSize: timelineFittedGlyphFontSize(
              11,
              metrics.frameCellWidth,
              crossExtent: metrics.layerControlsWidth,
            ),
            color: model.outsidePlaybackRange
                ? colorScheme.onSurfaceVariant.withValues(alpha: 0.55)
                : colorScheme.onSurface,
          ),
        );
        number.paint(
          canvas,
          Offset(
            rect.center.dx - number.width / 2,
            rect.center.dy - number.height / 2,
          ),
        );
      }

      // The cached-range strip moved to [TimelineRulerCursorOverlay] (in
      // its vertical form, hugging the right edge): cached-ness is derived
      // state with no invalidation event, so it must repaint freely rather
      // than ride this gated painter.
    }

    // The structural right edge, full strength, whatever the zoom.
    canvas.drawLine(
      Offset(size.width - 0.5, 0),
      Offset(size.width - 0.5, size.height),
      linePaint..color = colorScheme.outlineVariant,
    );
  }

  // Shared laid-out-TextPainter cache (UI-R16): rail numbers repeat
  // across repaints — fresh layout per label was the debug hot spot.
  @override
  Object get props => (scale,);

  // Every row gets a node — the rail numbers every frame.
  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) =>
      frameWindowSemantics(
        window: scale.visibleWindow(),
        rectFor: rowRectFor,
        labelFor: (frameIndex) => 'frame ${frameIndex + 1}',
      );
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
    required this.columnsContentWidth,
    required this.cutEndBoundaryOffset,
  });

  /// What the sheet can spare for the header block, or null when the
  /// height is unbounded.
  final double? availableHeaderExtent;
  final double naturalHeaderBlockExtent;
  final double splitterSlotExtent;
  final double bodyViewportHeight;
  final double totalFrameContentHeight;
  final double columnsContentWidth;
  final double cutEndBoundaryOffset;
}

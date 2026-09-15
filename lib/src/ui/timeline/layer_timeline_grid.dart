import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/app_language.dart' show AppLanguage;
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/attached_layer_resolve.dart'
    show attachRowWearsBaseComposite;
import '../../models/attached_placement.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_mark.dart';
import 'held_row_pin.dart';
import 'timeline_grid_range_gestures.dart';
import 'timeline_scroll_offset_sync.dart';
import 'timeline_frame_axis_follower.dart';
import 'layer_drop_policy.dart' show rowsWithSilhouette;
import 'layer_placement_entrance.dart';
import 'layer_row_drag.dart';
import '../listenable_rebind.dart';
import 'timeline_edge_auto_pan.dart';
import 'timeline_frame_range_gesture.dart';
import 'timeline_ruler_cursor_overlay.dart';
import 'timeline_drag_preview.dart';
import 'timeline_frame_scrub.dart';
import 'timeline_frame_cursor_layer.dart';
import 'timeline_frame_grid_stack.dart';
import 'timeline_beat_lines.dart';
import 'timeline_frame_range_policy.dart';
import 'timeline_frame_scroll_viewport.dart';
import 'timeline_frame_ruler.dart';
import 'timeline_frame_rows_scroll_body.dart';
import 'layer_rail_window.dart';
import 'rail_column_swipe.dart';
import 'layer_label_controls.dart'
    show SectionBandZone, layerSectionLabelSlotWidth;
import 'timeline_grid_metrics.dart';
import 'timeline_horizontal_offset_policy.dart';
import 'timeline_horizontal_scrollbar_rail.dart';
import 'property_lane_model.dart';
import 'timeline_lane_rows.dart';
import 'timeline_layer_controls_header.dart';
import 'timeline_layer_frame_body_layout.dart';
import '../widgets/empty_state_text.dart';
import '../input/pen_friendly_scroll_controller.dart';
import 'timeline_grid_shell.dart';
import 'timeline_zoom_anchor_policy.dart';
import 'memo_token.dart';
import 'timeline_layer_controls_row.dart';
import 'timeline_row_filter.dart';
import 'timeline_section_policy.dart';
import 'timeline_section_runs.dart';
import 'timeline_selected_exposure_outline.dart' show TimelineRowSelectionBands;
import 'timeline_vertical_scrollbar_rail.dart';
import 'timeline_visible_range.dart';

import '../../models/project_frame_rate.dart';
import '../text/app_strings.dart' show AppText;
import '../layout/device_grid_scroll_controller.dart';
import 'timeline_scroll_viewport.dart';
import 'timeline_grid_hooks.dart';
import 'timeline_swipe_columns.dart';

part 'layer_grid/layer_grid_rail_rows.dart';
part 'layer_grid/layer_grid_scroll.dart';
part 'layer_grid/layer_grid_row_drags.dart';
part 'layer_grid/layer_grid_lanes.dart';

class LayerTimelineGrid extends StatefulWidget {
  const LayerTimelineGrid({
    super.key,
    required this.hooks,
    required this.layers,
    this.railExtent,
    this.frameAxisOffset,
    this.displayedOnionSkinOn = false,
    this.metrics = TimelineGridMetrics.defaults,
    this.onToggleSection,
    this.legend,
    this.visibilitySoloEnabled = false,
    this.masterOpacityValue = 1.0,
    this.memoAux = const TimelineRowMemoAux(),
  });

  final List<Layer> layers;

  /// What the session answers this grid — see [TimelineGridHooks]. The
  /// rail and the sheet read the SAME bundle, so neither can lack an
  /// answer the other has.
  final TimelineGridHooks hooks;

  /// Sparse-row memo identity tokens (UI-R20 #4) — see
  /// [TimelineFrameRowsScrollBody.memoAux].
  final TimelineRowMemoAux memoAux;

  /// The rail's window size, set by this grid's splitter and persisted by
  /// the workspace. Null = a session-local one of our own (tests, and any
  /// host that has no place to keep it).
  final LayerRailExtent? railExtent;

  /// Where the FRAME axis stands, in pixels — kept by the workspace beside
  /// [railExtent] and for the same reason: it has to outlive this grid.
  /// Null = a session-local one of our own, as with the rail.
  ///
  /// 🚨F-143 (유저 2026-09-16): 「꽤 오른쪽으로 스크롤한채로 접으면
  /// 간편오버레이는 첫 인덱스쪽을 보여주고있어서 … 타임라인 열면
  /// 스크롤바가 왼쪽으로 초기화되있는상태」. Folding the panel disposes this
  /// grid; the offset lived in it, so it went too — the folded row had
  /// nothing to read and the grid that came back started at zero.
  final ValueNotifier<double>? frameAxisOffset;

  final bool displayedOnionSkinOn;

  /// Grid geometry; the frame-axis cell width carries the panel zoom.
  final TimelineGridMetrics metrics;

  /// Folds/unfolds a hideable section (the legend corner's sections cell).
  final ValueChanged<TimelineSection>? onToggleSection;

  /// The rail legend's bulk commands; null renders a display-only legend.
  final LayerLegendCallbacks? legend;

  /// Whether the visibility solo mode is engaged (legend eye state color).
  final bool visibilitySoloEnabled;

  /// The master bar's resting value (the LAST committed sweep, UI-R6 #2).
  final double masterOpacityValue;

  @override
  State<LayerTimelineGrid> createState() => _LayerTimelineGridState();
}

/// The data snapshot a memoized RAIL row was built from (UI-R7 #1) —
/// zoom-independent by construction: nothing here reads frameCellWidth,
/// so zoom steps always hit.
typedef _RailRowMemoInputs = ({
  // What the row SHOWS gates content, not the Layer's identity: a
  // timesheet edit rebuilds the edited layer's instance while every
  // rail-visible field stays put (see the completeness contract on
  // [ControlsRowFace]).
  ControlsRowFace layer,
  bool active,
  // ㉞: the row selection wash. SESSION state like [active] and invisible to
  // the Layer comparison — ⑨ passed `selected` to the row without giving the
  // memo a way to see it change, so the wash never appeared until some other
  // fact happened to invalidate the entry. The state was right the whole
  // time; the cache answered "unchanged" (the ㉘ shape).
  bool selected,
  bool hasLanes,
  bool lanesExpanded,
  int depth,
  bool hasGroupFold,
  bool groupFoldExpanded,
  LayerFxState fxState,
  bool onionSkinEnabled,
  bool isLinked,
  bool soloed,
  AttachedPlacement? attachArrow,
  double layerRowHeight,
  double layerControlsWidth,
  double sectionLabelGutterWidth,
  ByIdentity<ValueListenable<({Set<LayerId> layerIds, double opacity})?>?>
  opacityDragPreview,
  // R27 #6: the blend chip prints a LANGUAGE-dependent name — a language
  // switch must invalidate the memo like any other visible fact. Read from
  // [AppText.language] when the token is made (F-170), not handed down.
  // ⛔MUTANT SURVIVES HERE (2026-09-23): a fixed language in this slot left
  // `a_language_that_lands_late_reaches_every_word_test` green — the chip
  // reads the theme, so it rebuilds itself when the app root rebuilds for
  // the language, memo or no memo. Kept because the memo's own rule is that
  // every visible fact is in its token, and a row word that stopped reading
  // the theme would keep the last language's without it.
  AppLanguage language,
});

/// The legend header's memo token (UI-R7 #1): every legend-visible fact.
/// A new legend-reading cell must join this record — miss one and the
/// header shows stale state.
typedef _LegendMemoInputs = ({
  double layerRowHeight,
  double layerControlsWidth,
  bool hasLegend,
  BySet<TimelineSection> hiddenSections,
  TimelineRowFilter rowFilter,
  BySet<LayerMark> marksInUse,
  BySet<LayerKind> kindsInUse,
  bool visibilitySoloEnabled,
  bool anyLanesExpanded,
  bool allSeMuted,
  BySet<LayerId> displayedIds,
  double masterOpacityValue,
  bool hasLaneToggles,
  bool displayedOnionSkinOn,
  // R27 #6: the blend column's header prints language-dependent names in
  // its flyout and gates on the bulk callback's presence.
  AppLanguage language,
  bool hasBlendBulk,
});

class _LayerTimelineGridState extends State<LayerTimelineGrid> {
  /// The integer rate the grid COUNTS with — the ruler's second marks
  /// and row labels are frame arithmetic, never real time (see
  /// [ProjectFrameRate.countingBase]).
  int get _countingFps => widget.hooks.projectFrameRate.countingBase;

  TimelineGridMetrics get _metrics => widget.metrics;

  /// Identity-gated RAIL row memo (UI-R7 #1, the frame rows' memo idiom):
  /// a zoom step re-lays-out the frame grid, but the rail's Material-heavy
  /// control rows (tooltips, ink wells, sliders) don't depend on the zoom
  /// — identical inputs hand the SAME widget instance back so Flutter
  /// skips their whole subtree rebuild. Layer identity gates content
  /// (commits swap instances); callbacks follow the R13-2 rule (host
  /// callbacks close over the stable session only).
  final Map<LayerId, ({_RailRowMemoInputs inputs, Widget row})> _railRowMemo =
      {};

  /// The legend header's memo — same idea, token-gated (R13-2): the
  /// header's ~15 tooltip/flyout cells rebuild only when a legend-visible
  /// fact changes, never on zoom steps.
  ({_LegendMemoInputs inputs, Widget header})? _legendHeaderMemo;

  late final ScrollController _horizontalScrollController;
  late final ScrollController _verticalScrollController;

  /// The frame-axis scroll offset as a NOTIFIER (UI-R9 #12a): a scroll
  /// pixel updates this value only — the ruler's translate and the window
  /// token subscribe, and the grid itself never rebuilds per pixel (the
  /// body is a real scrollable; pixels are free there).
  ///
  /// The host's when it keeps one ([LayerTimelineGrid.frameAxisOffset]).
  /// ⚠️Read ONCE: the workspace's lives as long as the workspace, and the
  /// follower below holds whichever this resolved to.
  late final ValueNotifier<double> _frameAxisOffset =
      widget.frameAxisOffset ?? _ownedFrameAxisOffset;

  /// The fallback frame-axis offset for hosts that keep none of their own.
  final ValueNotifier<double> _ownedFrameAxisOffset = ValueNotifier<double>(0);

  /// The fallback rail extent for hosts that keep none of their own.
  LayerRailExtent? _ownedRailExtent;

  // ── the rail rows: their own object, in their own file ──────────────
  //
  // A collaborator (timeline/layer_grid/layer_grid_rail_rows.dart, a part of this
  // library). The State keeps the entry points its build tree calls.
  late final _LayerGridRailRows _railRows = _LayerGridRailRows(this);

  /// The quantized frame-window token: the leading visible CELL index.
  /// Changes only on cell-boundary crossings — the rows body and the
  /// ruler content re-window from it (sub-cell movement rebuilds nothing).
  final ValueNotifier<int> _frameWindowBucket = ValueNotifier<int>(0);

  /// The LAYER-axis twin of [_frameWindowBucket]: the leading visible ROW
  /// index. Only the scroll body subscribes.
  ///
  /// 🚨It exists because the vertical axis used to answer a row crossing
  /// with `setState(() {})` on this State — which reruns [build] from the
  /// top, and the first thing at the top is `buildTimelineDisplayRows` over
  /// every layer and every open lane. Scrolling a tall stack therefore
  /// rebuilt the row MODEL once per row, to change which slice of it gets
  /// widgets. The frame axis has not done that since UI-R9 #12a; this is
  /// the same shape, on the other axis.
  final ValueNotifier<int> _rowWindowBucket = ValueNotifier<int>(0);

  double _verticalScrollOffset = 0;

  /// The frame axis following its controller (UI-R9 #11/#12a): the
  /// activity watch for the lazy endless SHRINK (never rescale the extent
  /// mid-gesture), the trailing room and the notifiers — one object, the
  /// same one the sheet and the storyboard hold.
  late final TimelineFrameAxisFollower _frameAxis = TimelineFrameAxisFollower(
    controller: _horizontalScrollController,
    frameAxisOffset: _frameAxisOffset,
    frameWindowBucket: _frameWindowBucket,
    cellExtent: () => _metrics.frameCellWidth,
    baseFrameCount: () => _visibleFrameCount,
    rebuild: _rebuild,
    isMounted: () => mounted,
  );

  /// UI-R9 #9: each axis pulled to the offset the layout resolved, one
  /// frame later — one object per axis, the same one the sheet holds.
  late final TimelineScrollOffsetSync _horizontalSync = TimelineScrollOffsetSync(
    _horizontalScrollController,
    isMounted: () => mounted,
  );
  late final TimelineScrollOffsetSync _verticalSync = TimelineScrollOffsetSync(
    _verticalScrollController,
    isMounted: () => mounted,
  );
  final GlobalKey _rulerScrubViewportKey = GlobalKey();

  /// The sweepable columns — ONE list for both grids ([timelineSwipeColumns]),
  /// laid on this rail's own width.
  List<RailToggleColumn<TimelineDisplayRow>> _swipeColumns() =>
      timelineSwipeColumns(
        hooks: widget.hooks,
        crossExtent:
            _metrics.layerControlsWidth - _metrics.sectionLabelGutterWidth,
        leadingOrigin: timelineLayerRowLeadingBorder,
      );

  @override
  void initState() {
    super.initState();
    // PEN-10: pen-friendly positions — while a stylus is nearby, a
    // coasting fling stops hiding the cells from hit-testing.
    //
    // 🚨★★BORN WHERE THE AXIS STANDS, NOT AT ZERO (F-143). Folding and
    // unfolding the panel REMOUNT this grid (measured: a new controller each
    // time). A controller born at 0 has no clients in its first layout, so
    // the sync there cannot pull it anywhere — and then the follower's
    // after-layout re-read (F-95) found the newborn 0 and recorded it as a
    // scroll, over the position the host had kept. Born at the kept offset,
    // the re-read reads back what was kept and records nothing.
    _horizontalScrollController = PenFriendlyScrollController(
      initialScrollOffset: _frameAxisOffset.value,
    );
    _verticalScrollController = PenFriendlyScrollController();
    _horizontalScrollController.addListener(_frameAxis.handleScroll);
    _verticalScrollController.addListener(_scroll.handleVerticalScroll);
    widget.hooks.revealSelectionTick?.addListener(_handleRevealSelection);
    widget.hooks.frameCursor.addListener(_handlePlaybackPage);
  }

  /// The reveal runs AFTER the frame the selection moved in: the rows this
  /// pass built are what the row index counts in, and on a row step they
  /// have not been rebuilt yet when the tick arrives.
  void _handleRevealSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _revealSelection();
      }
    });
  }

  /// F-110: the frame axis turns a PAGE when playback carries the playhead
  /// out of the window — 유저 2026-09-12: 「넘어가면 룰러가 왼쪽에 오도록
  /// 스크롤바 한번만 이동」.
  ///
  /// ⛔The cursor is what is listened to, not the playback listenable: the
  /// cursor is the frame THIS axis counts in and it is already set when it
  /// notifies, where two listeners on the playback notifier would have to
  /// fire in the order they happened to be added.
  ///
  /// ⛔And only the FRAME axis. A cut plays down one row, so there is no row
  /// for the tick to stand on — [pageToPlayhead] takes one axis for that
  /// reason and the reveal takes two.
  void _handlePlaybackPage() {
    if (widget.hooks.playbackFrame?.value == null) {
      return;
    }
    pageToPlayhead((
      controller: _horizontalScrollController,
      extent: _metrics.frameCellWidth,
      at: widget.hooks.frameCursor.value,
    ));
  }

  @override
  void didUpdateWidget(covariant LayerTimelineGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hooks.revealSelectionTick !=
        widget.hooks.revealSelectionTick) {
      oldWidget.hooks.revealSelectionTick?.removeListener(
        _handleRevealSelection,
      );
      widget.hooks.revealSelectionTick?.addListener(_handleRevealSelection);
    }
    rebindListener(
      oldWidget.hooks.frameCursor,
      widget.hooks.frameCursor,
      _handlePlaybackPage,
    );
    // Zoom-around-playhead: the playhead stays put on screen through zoom
    // when visible; otherwise the leading-edge frame anchors.
    applyZoomAnchoredScroll(
      _horizontalScrollController,
      oldPixelsPerFrame: oldWidget.metrics.frameCellWidth,
      newPixelsPerFrame: widget.metrics.frameCellWidth,
      anchorFrame: widget.hooks.frameCursor.value,
    );
  }

  @override
  void dispose() {
    widget.hooks.revealSelectionTick?.removeListener(_handleRevealSelection);
    widget.hooks.frameCursor.removeListener(_handlePlaybackPage);
    _frameAxis.dispose();
    _horizontalScrollController
      ..removeListener(_frameAxis.handleScroll)
      ..dispose();
    _verticalScrollController
      ..removeListener(_scroll.handleVerticalScroll)
      ..dispose();
    // ⛔Only our own: the host's has to outlive this grid — that is the
    // whole reason it is the host's.
    _ownedFrameAxisOffset.dispose();
    _frameWindowBucket.dispose();
    _rowWindowBucket.dispose();
    _ownedRailExtent?.dispose();
    super.dispose();
  }

  /// The layer-axis position, or null when the controller is attached to
  /// anything other than exactly one view: `hasClients` only rules out
  /// zero, and `.offset` asserts on two as well.
  ScrollPosition? get _verticalPosition {
    final positions = _verticalScrollController.positions;
    return positions.length == 1 ? positions.first : null;
  }

  // ── the scroll: its own object, in its own file ─────────────────────
  //
  // A collaborator (timeline/layer_grid/layer_grid_scroll.dart, a part of this
  // library). The State keeps the entry points its build tree calls.
  late final _LayerGridScroll _scroll = _LayerGridScroll(this);

  /// The door a collaborator rebuilds through - setState is protected,
  /// and a collaborator is not a subclass.
  void _rebuild(VoidCallback fn) => setState(fn);

  // ── the range gestures: their own object ────────────────────────────
  //
  // The ONE collaborator both grids hold (timeline_grid_range_gestures.dart).
  // The State keeps the entry points its build tree calls.
  late final TimelineGridRangeGestures _rangeGestures =
      TimelineGridRangeGestures(
        hooks: () => widget.hooks,
        metrics: () => _metrics,
        dragRows: () => _dragRows,
        rangeMove: _rangeMoveResolver,
        // D42: EVERY range drag (select or move) takes the A5 grip, and the
        // held row is PINNED in the row window while it does.
        pin: _heldRow,
      );

  int get _visibleFrameCount => _rangeGestures.frameRangePolicy.visibleFrameCount;

  /// Frame cells the current viewport needs to be fully papered (UI-R12
  /// #16) — recorded by build's outer LayoutBuilder, like the effective
  /// offsets. Zero until the first layout.
  int _viewportFillFrameCells = 0;

  /// Render extent (UI-R12 #16 contract): the cells the user has scrolled
  /// into existence PLUS whatever the viewport needs to read as one
  /// continuous sheet — never a runway beyond that. The scrollbar and
  /// scroll physics clamp here; only the ruler edge-drag overshoots (and
  /// the growth listener then materializes what the view needs).
  int get _renderedFrameCount => math.max(
    _visibleFrameCount + _frameAxis.trailingFrames,
    _viewportFillFrameCells,
  );

  // ── the ruler scrub: the SHARED object ──────────────────────────────
  //
  // [TimelineFrameScrub], the one the X-sheet's rail holds too — the same
  // six members, turned by the axis (the audit's clone scan, round 8).
  late final TimelineFrameScrub _rulerScrub = TimelineFrameScrub(
    axis: Axis.horizontal,
    viewportKey: _rulerScrubViewportKey,
    controller: _horizontalScrollController,
    hooks: () => widget.hooks,
    frameCellExtent: () => _metrics.frameCellWidth,
    renderedFrameCount: () => _renderedFrameCount,
    scrolledFrameOffset: () => _frameAxis.paintedOffset,
  );

  /// Brings the SELECTION back into view on both axes (R5, user
  /// 2026-08-09): the frame under the cursor along the frame axis, the row
  /// it stands on along the rail.
  ///
  /// Answered here rather than sent here, because "where is the selection"
  /// is a question about THIS surface's geometry — the sheet asks it of the
  /// other axis and the storyboard of a global one, off the same tick.
  ///
  /// One row/cell of margin, so a walk keeps a neighbour in sight and reads
  /// as a walk rather than as a jump to the edge.
  void _revealSelection() => revealSelectionOnBothAxes(
    (
      controller: _horizontalScrollController,
      extent: _metrics.frameCellWidth,
      at: widget.hooks.frameCursor.value,
    ),
    (
      controller: _verticalScrollController,
      extent: _metrics.layerRowHeight,
      at: indexOfDisplayRow(
        _dragRows,
        current: widget.hooks.currentRowHooks?.currentRow.value,
        activeLayerId: widget.hooks.activeLayerId,
      ),
    ),
  );

  // ── the lanes: their own object, in their own file ──────────────────
  //
  // A collaborator (timeline/layer_grid/layer_grid_lanes.dart, a part of this
  // library). The State keeps the entry points its build tree calls.
  late final _LayerGridLanes _lanes = _LayerGridLanes(this);

  /// Marks assigned across the current layer list — the mark-solo menu's
  /// "solo color X" list is built from these.
  Set<LayerMark> _marksInUse() => {
    for (final layer in widget.layers)
      if (layer.mark != LayerMark.none) layer.mark,
  };

  /// Kinds present across the current layer list — the kind-solo menu
  /// (R4 #8) is built from these.
  Set<LayerKind> _kindsInUse() => {
    for (final layer in widget.layers) layer.kind,
  };

  /// The rows the rail currently DISPLAYS (layer rows only, camera
  /// excluded) — the master opacity bar's target set (R4 #6).
  Set<LayerId> _displayedLayerIds(List<TimelineDisplayRow> rows) => {
    for (final row in rows)
      if (!row.isLane && row.layer.kind.hasPictureOpacity)
        row.layer.id,
  };

  /// Whether every SE row is muted — the legend mute cell's toggle state
  /// (no SE rows reads as unmuted, so the first tap mutes).
  bool _allSeMuted() {
    var sawSe = false;
    for (final layer in widget.layers) {
      if (layer.kind != LayerKind.se) {
        continue;
      }
      sawSe = true;
      if (!layer.muted) {
        return false;
      }
    }
    return sawSe;
  }

  /// The display rows of the pass in flight — see [_effectHeaderRows].
  List<TimelineDisplayRow> _dragRows = const [];

  /// The row, made draggable. The wrapper is built fresh every pass and the
  /// memoized row travels through it untouched — the drag state lives in a
  /// notifier the wrapper subscribes to, so a caret moving does not
  /// invalidate one cached row.
  ///
  /// A5 (2026-08-17): the row a drag gesture is HOLDING — move or select,
  /// layer row or fx header. Everything about why it exists, and why it is
  /// a plain field rather than a notifier, is on [HeldRowPin]; every drag
  /// surface of this grid takes and releases the SAME one.
  final HeldRowPin _heldRow = HeldRowPin();

  // ── the row drags: their own object ─────────────────────────────────
  //
  // A collaborator (timeline/layer_grid/layer_grid_row_drags.dart, a part of this
  // library). The State keeps the entry points its build tree calls.
  late final _LayerGridRowDrags _rowDrags = _LayerGridRowDrags(this);

  /// The section ZONES over the rail rows' reserved band slots (UI-R7 #2):
  /// one tinted zone per section run — the pre-R5 gutter bracket inside
  /// the rows (upright label centered across the run, tap = section
  /// flyout).
  ///
  /// Fed the FULL display-row list, never the window (A3 2026-08-17): a
  /// zone spans its section's first-to-last row in content coordinates, so
  /// the label sits at the section's true middle and scrolls away with the
  /// content instead of chasing the viewport, and a section scrolled out of
  /// view keeps its bracket mounted (reserve space, swap content). The
  /// x-sheet (full `entries`) and the storyboard (full group Column)
  /// already anchor their bands this way — the three surfaces share the
  /// same run functions on full lists now. Runs tile contiguously from row
  /// zero ([timelineSectionRuns] assigns every row a section), so the
  /// Column needs no leading spacer.
  Widget _sectionBandOverlay(List<TimelineDisplayRow> rows) {
    final runs = timelineSectionRuns(rows);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final run in runs)
          KeyedSubtree(
            key: ValueKey<String>('section-bracket-${run.section.name}'),
            child: SectionBandZone(
              label: timelineSectionLabel(run.section),
              extent: timelineSectionRunExtent(run, rows, _metrics),
            ),
          ),
      ],
    );
  }

  /// Resolves range-move row deltas against the rows built this pass.
  final TimelineRangeMoveRowResolver _rangeMoveResolver =
      TimelineRangeMoveRowResolver();

  /// The rows this pass builds. See [_RowWindow].
  _RowWindow _rowWindowFor(
    List<TimelineDisplayRow> rows,
    double bodyViewportHeight,
    double effectiveVerticalScrollOffset,
  ) {
    final rowWindow = bodyViewportHeight <= 0
        ? TimelineVisibleRange(startIndex: 0, endIndexExclusive: rows.length)
        : calculateVisibleIndexRange(
            scrollOffset: effectiveVerticalScrollOffset,
            viewportExtent: bodyViewportHeight,
            itemExtent: _metrics.layerRowHeight,
            itemCount: rows.length,
          );
    final windowRows = rows.sublist(
      rowWindow.startIndex,
      rowWindow.endIndexExclusive,
    );
    final leadingRowSpacerHeight =
        rowWindow.startIndex * _metrics.layerRowHeight;
    final trailingRowSpacerHeight =
        (rows.length - rowWindow.endIndexExclusive) * _metrics.layerRowHeight;
    // A5: the row a drag is holding stays
    // built when the window slides past it —
    // otherwise its State (and the pan
    // recognizer in it) is disposed and the
    // grip silently releases mid-gesture.
    // O(1): exactly one extra row, carved out
    // of the spacer it falls in.
    final heldRow = _heldRow.held;
    var pinnedIndex = -1;
    if (heldRow != null) {
      pinnedIndex = rows.indexWhere((row) => row.address == heldRow);
      if (pinnedIndex >= rowWindow.startIndex &&
          pinnedIndex < rowWindow.endIndexExclusive) {
        // Already built by the window.
        pinnedIndex = -1;
      }
    }
    final pinnedBefore = pinnedIndex >= 0 && pinnedIndex < rowWindow.startIndex;
    final pinnedAfter = pinnedIndex >= rowWindow.endIndexExclusive;
    return _RowWindow(
      range: rowWindow,
      rows: windowRows,
      leadingSpacerHeight: leadingRowSpacerHeight,
      trailingSpacerHeight: trailingRowSpacerHeight,
      pinnedIndex: pinnedIndex,
      pinnedBefore: pinnedBefore,
      pinnedAfter: pinnedAfter,
    );
  }

  /// The cells themselves: one row of frame cells per row the window
  /// builds, scrolled with the rail beside it.
  ///
  /// One of the three slots `TimelineFrameGridStack` layers. It takes the
  /// row window as one value and unpacks it under the names the tree below
  /// already uses — see [_RowWindow].
  Widget _buildFrameRowsBody(
    List<TimelineDisplayRow> rows,
    _RowWindow window,
    TimelineRangeGestureCallbacks? rangeGesture,
    TimelineLaneRangeCallbacks? laneRange,
    double totalFrameContentWidth,
    double viewportWidth,
  ) {
    final rowWindow = window.range;
    final windowRows = window.rows;
    final leadingRowSpacerHeight = window.leadingSpacerHeight;
    final trailingRowSpacerHeight = window.trailingSpacerHeight;
    final pinnedIndex = window.pinnedIndex;
    final pinnedBefore = window.pinnedBefore;
    final pinnedAfter = window.pinnedAfter;
    return TimelineFrameRowsScrollBody(
      // F-25: the lane bands light
      // with their rail halves.
      currentRow: widget.hooks.currentRowHooks?.currentRow,
      rows: windowRows,
      leadingLayerSpacerHeight: leadingRowSpacerHeight,
      trailingLayerSpacerHeight: trailingRowSpacerHeight,
      // A5/D42: the held row rides
      // the CELLS window too — its
      // gesture layer must survive a
      // vertical auto-pan sliding
      // the window past it.
      pinnedLeadingRow: pinnedBefore ? rows[pinnedIndex] : null,
      pinnedLeadingOffset: pinnedBefore
          ? pinnedIndex * _metrics.layerRowHeight
          : 0,
      pinnedTrailingRow: pinnedAfter ? rows[pinnedIndex] : null,
      pinnedTrailingOffset: pinnedAfter
          ? (pinnedIndex - rowWindow.endIndexExclusive) *
                _metrics.layerRowHeight
          : 0,
      dragPreview: widget.hooks.dragPreview,
      activeLayerId: widget.hooks.activeLayerId,
      playbackFrameCount: widget.hooks.playbackFrameCount,
      frameStartIndex: 0,
      frameEndIndexExclusive: _renderedFrameCount,
      leadingFrameSpacerWidth: 0,
      trailingFrameSpacerWidth: 0,
      totalFrameContentWidth: totalFrameContentWidth,
      windowBucket: _frameWindowBucket,
      viewportMainExtent: viewportWidth,
      metrics: _metrics,
      exposureStateForLayer: widget.hooks.exposureStateForLayer,
      frameNameForLayer: widget.hooks.frameNameForLayer,
      celContent: widget.hooks.celContent,
      onSelectLayer: widget.hooks.onSelectLayer,
      onSelectFrame: widget.hooks.onSelectFrame,
      onSettledPress: widget.hooks.onSettledPress,
      onActivateCell: widget.hooks.onActivateCell,
      instructionDefById: widget.hooks.instructionDefById,
      instructionCrossingTooltip: widget.hooks.instructionCrossingTooltip,
      audioPeaksFor: widget.hooks.audioPeaksFor,
      seClipMarkerTooltip: widget.hooks.seClipMarkerTooltip,
      projectFrameRate: widget.hooks.projectFrameRate,
      audioLane: widget.hooks.audioLane,
      onDropMediaAssetOnLayer: widget.hooks.onDropMediaAssetOnLayer,
      acceptsMediaAssetOnLayer: widget.hooks.acceptsMediaAssetOnLayer,
      onHoverMediaAssetOnLayer: widget.hooks.onHoverMediaAssetOnLayer,
      onLeaveMediaAssetOnLayer: widget.hooks.onLeaveMediaAssetOnLayer,
      showSeconds: widget.hooks.showSeconds,
      commaDrag: widget.hooks.commaDrag,
      rangeGesture: rangeGesture,
      laneRange: laneRange,
      lanesForLayer: _lanes.lanesFor,
      unionLaneForLayer: widget.hooks.unionLaneForLayer,
      runEdit: widget.hooks.runEdit,
      laneEdit: widget.hooks.laneEdit,
      seSpillInLeadFrames: widget.hooks.seSpillInLeadFrames,
      memoAux: widget.memoAux,
      substrateGeneration: widget.hooks.substrateGeneration,
    );
  }

  /// The beat lines under the cells — the grid ground D43-2 states once.
  Widget _buildBeatLines(ColorScheme colorScheme) {
    return CustomPaint(
      key: const ValueKey<String>('timeline-beat-lines'),
      painter: TimelineBeatLinesPainter(
        frameCellExtent: _metrics.frameCellWidth,
        framesPerSecond: _countingFps,
        colorScheme: colorScheme,
        // D43: the panel's own Material colour — see
        // TimelineBeatLinesPainter.ground.
        ground: colorScheme.surfaceContainerHighest,
        crossCellExtent: _metrics.layerRowHeight,
      ),
    );
  }

  /// The cursor over the cells — the playhead, the drag preview and the
  /// selection band, drawn once above every row.
  ///
  /// The third of `TimelineFrameGridStack`'s slots. It reads the rows for
  /// their count and the hooks for the band; the two extents are what the
  /// stack already sized the layer to.
  Widget _buildPlayhead(
    List<TimelineDisplayRow> rows,
    TimelineFrameRangeHooks? rangeHooks,
    double verticalContentHeight,
    double viewportWidth,
  ) {
    return TimelineCursorLayer(
      currentRow: widget.hooks.currentRowHooks?.currentRow,
      frameCursor: widget.hooks.frameCursor,
      dragPreview: widget.hooks.dragPreview,
      frameRangeSelection: rangeHooks?.selection,
      // R27 #14: the lane
      // span draws the SAME
      // band here.
      laneRangeSelection: widget.hooks.laneRange?.selection,
      rows: rows,
      activeLayerId: widget.hooks.activeLayerId,
      frameStartIndex: 0,
      frameEndIndexExclusive: _renderedFrameCount,
      leadingFrameSpacerWidth: 0,
      metrics: _metrics,
      exposureStateForLayer: widget.hooks.exposureStateForLayer,
      crossAxisExtent: verticalContentHeight,
      windowBucket: _frameWindowBucket,
      viewportMainExtent: viewportWidth,
    );
  }

  /// The frame cells and everything layered on them, in the width the rail
  /// left over.
  ///
  /// The fourth slot of `TimelineLayerFrameBodyLayout`. It is composition:
  /// it sizes the area, then hands the rows body, the beat lines and the
  /// playhead to `TimelineFrameGridStack`. ⚠️Seven parameters, and every
  /// one is passed straight through to a slot below — this method owns
  /// no logic of its own, which is why it may carry that many.
  Widget _buildFrameGridArea(
    ColorScheme colorScheme,
    List<TimelineDisplayRow> rows,
    _RowWindow window,
    TimelineFrameRangeHooks? rangeHooks,
    TimelineRangeGestureCallbacks? rangeGesture,
    TimelineLaneRangeCallbacks? laneRange,
    double verticalContentHeight,
  ) {
    return Expanded(
      child: KeyedSubtree(
        key: const ValueKey<String>('timeline-frame-grid-area'),
        // D8: the frame area's
        // LEFT edge hairline.
        // D8-2: the ruler wears
        // the SAME widget above
        // — one line, two areas.
        child: TimelineFrameAreaEdge(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final viewportWidth = constraints.hasBoundedWidth
                  ? constraints.maxWidth
                  : 0.0;
              _frameAxis.rereadAfterLayout();
              _horizontalSync.synchronize(
                _scroll.effectiveHorizontalScrollOffset(
                  requestedOffset: _frameAxisOffset.value,
                  viewportWidth: viewportWidth,
                ),
              );

              // PRO-TIMELINE scrolling
              // (UI-R15): the body builds
              // ONCE for the full frame
              // bounds — the drawing rows'
              // painters window themselves
              // off the live offset
              // (repaint-only), sparse
              // rows re-window internally
              // under the bucket, and the
              // overlays position
              // content-absolutely. A
              // scroll rebuilds NOTHING
              // here.
              final totalFrameContentWidth =
                  _renderedFrameCount * _metrics.frameCellWidth;
              return TimelineFrameScrollViewport(
                controller: _horizontalScrollController,
                contentWidth: totalFrameContentWidth,
                contentHeight: verticalContentHeight,
                child: TimelineFrameGridStack(
                  rowsBody: _buildFrameRowsBody(
                    rows,
                    window,
                    rangeGesture,
                    laneRange,
                    totalFrameContentWidth,
                    viewportWidth,
                  ),
                  // UI-R13 #7: the
                  // beat lines span
                  // EVERY row now, one
                  // grid-wide overlay.
                  beatLines: _buildBeatLines(colorScheme),
                  // UI-R18 #14: the end
                  // line grows a trim
                  // grip and follows the
                  // live preview.
                  cutEndDrag: widget.hooks.cutEndDrag,
                  dragPreview: widget.hooks.dragPreview,
                  frameCellExtent: _metrics.frameCellWidth,
                  playbackFrameCount: widget.hooks.playbackFrameCount,
                  // のりしろ: the blue
                  // line runs through
                  // the body too, and
                  // the wash starts
                  // behind it.
                  drawnFrameCount: widget.hooks.drawnFrameCount,
                  // The cursor layer decides
                  // per frame what to show —
                  // the slot itself is static
                  // so ticks rebuild nothing
                  // here.
                  playheadExtent: totalFrameContentWidth,
                  playhead: _buildPlayhead(
                    rows,
                    rangeHooks,
                    verticalContentHeight,
                    viewportWidth,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const bottomScrollbarRailHeight = timelineBottomScrollbarRailHeight;
    final rows = widget.hooks.displayRows(
      widget.layers,
      lanesForLayer: _lanes.lanesFor,
    );
    // The row drag counts ROWS and lands on SLOTS, and only this list knows
    // how many rows sit between two fx headers (their members may be
    // twirled open). Held for the wrappers built below in the same pass.
    _dragRows = rows;
    // ⚠️AFTER the line above, never before: a file held over the layer area
    // is DRAWN as a row in its gap, and the gap it stands in is counted on
    // the list that does not have it ([rowsWithSilhouette] says why).
    final drawnRows = rowsWithSilhouette(rows, widget.hooks.dragPreview?.value);
    final rangeHooks = widget.hooks.rangeHooks;
    final rangeGesture = _rangeGestures.rangeGestureFor(rows);
    final laneRange = _rangeGestures.laneRangeFor(rows);
    // ⛔The gestures above take the REAL rows: nothing can be selected,
    // dragged or edited on a row that does not exist yet.

    // The law, the glide stop and the overscroll clamp — [TimelineGridShell]
    // carries the PEN-9 / PEN-12 #7 / D43-2 decisions for both grids.
    return TimelineGridShell(
      ground: colorScheme.surfaceContainerHighest,
      framesPerSecond: _countingFps,
      controllers: [_horizontalScrollController, _verticalScrollController],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportHeight = constraints.hasBoundedHeight
              ? (constraints.maxHeight - bottomScrollbarRailHeight)
                    .clamp(0.0, double.infinity)
                    .toDouble()
              : 0.0;
          // The splitter's value is read HERE and nowhere deeper. The
          // rail itself keeps being laid out at its natural width, so a
          // drag frame re-lays-out the window box and the frame area and
          // rebuilds not one rail row — which is why the extent is a
          // listenable instead of a metrics field (a metrics field is a
          // memo key, and the frame geometry already paid that price
          // once at ~60% of a step).
          return ValueListenableBuilder<double?>(
            valueListenable: _railRows._railExtent,
            builder: (context, _, child) {
              // What the panel can spare for the rail — the ONE value
              // every part of the rail reads ([layerRailAvailableExtent]).
              final availableRailExtent = layerRailAvailableExtent(
                constraints,
                railAxis: Axis.horizontal,
                scrollbarLaneExtent: _metrics.verticalScrollbarWidth,
              );
              final railWindowExtent = _railRows._railExtent.windowExtent(
                _railRows.naturalRailWidth,
                availableExtent: availableRailExtent,
              );
              // Viewport paper fill (UI-R12 #16): however wide the cell
              // area is, cells run to its edge — recorded here so every
              // consumer of [_renderedFrameCount] below sees it
              // (build-recorded like the effective offsets).
              _viewportFillFrameCells = endlessViewportFillFrames(
                viewportExtent: constraints.hasBoundedWidth
                    ? (constraints.maxWidth -
                              _metrics.verticalScrollbarWidth -
                              railWindowExtent -
                              LayerRailSplitter.thickness)
                          .clamp(0.0, double.infinity)
                          .toDouble()
                    : 0.0,
                frameCellExtent: _metrics.frameCellWidth,
              );

              return KeyedSubtree(
                key: const ValueKey<String>('timeline-scrollbar-area'),
                child: Stack(
                  children: [
                    Column(
                      children: [
                        Expanded(
                          // 🎯The layer-axis window token gates THIS subtree
                          // and nothing above it. A row crossing rebuilds the
                          // scroll body; it no longer reruns `build`, whose
                          // first act is `buildTimelineDisplayRows` over every
                          // layer and every open lane. ⛔Keep it OUTSIDE the
                          // LayoutBuilder: inside, the token would rebuild a
                          // callback that a constraints change already
                          // rebuilds, and the model above would still be gone
                          // over per row.
                          child: ValueListenableBuilder<int>(
                            valueListenable: _rowWindowBucket,
                            builder: (context, _, _) => LayoutBuilder(
                              builder: (context, constraints) {
                                final headerHeight =
                                    _metrics.layerRowHeight;
                                final bodyViewportHeight =
                                    constraints.hasBoundedHeight
                                    ? (constraints.maxHeight - headerHeight)
                                          .clamp(0.0, double.infinity)
                                          .toDouble()
                                    : viewportHeight;
                                // Rows are no longer uniformly tall: collapsed sections
                                // fold to a slim strip.
                                //
                                // ⛔D43-2 (유저 확정, 2026-08-21): the viewport is NOT
                                // a floor on this, and a version of this file that made
                                // it one is reverted. 「레이어가 없는곳에 그리드를
                                // 만들란게아니야. 행이 없는곳은 지금까지처럼 그리드
                                // 없어도 되고」 — the report was about the empty cells
                                // INSIDE a row, and stretching the content to the
                                // viewport answered a question nobody asked while
                                // leaving the real one open.
                                //
                                // ★The real cause is one layer up: a row paints an
                                // OPAQUE full-width ground, and the line overlay sits
                                // UNDER the rows — so the overlay is covered for the
                                // whole width of every row that draws one, and shows
                                // only where no row does (lane rows, and past the last
                                // row). ⇒ the empty cells' lines are the ROW's to draw
                                // ([TimelineRowCellsPainter.rowGround]), not the
                                // overlay's to reach further.
                                final verticalContentHeight = math.max(
                                  // The DRAWN rows: a silhouette standing in
                                  // a gap makes the content one row taller,
                                  // and a scroll extent that forgot it would
                                  // clip the row it pushed down.
                                  timelineDisplayRowsExtent(
                                    drawnRows,
                                    _metrics,
                                  ),
                                  _metrics.layerRowHeight,
                                );
                                // Layer-axis window: only the rows in view (plus
                                // overscan) are built; spacers preserve the scroll
                                // geometry of the rest. The cursor and preview
                                // overlays keep the FULL row list — their offsets are
                                // absolute. Without a real viewport measurement
                                // (unbounded hosts) every row builds, like before.
                                // The offset is CLAMPED to the current content before
                                // windowing (UI-R9 #9): lane collapses shrink the rows
                                // under a stale scroll offset, and the raw value would
                                // inflate the leading spacer (sections pushed down).
                                // The clamp is read fresh off the position every build
                                // so it can never outlive the shrink that caused it
                                // (UI-R5 #3 — see [_readVerticalScrollOffset]).
                                _scroll.readVerticalScrollOffset();
                                final effectiveVerticalScrollOffset =
                                    _scroll._effectiveVerticalScrollOffset(
                                      requestedOffset:
                                          _verticalScrollOffset,
                                      viewportHeight: bodyViewportHeight,
                                      contentHeight: verticalContentHeight,
                                    );
                                _verticalSync.synchronize(
                                  effectiveVerticalScrollOffset,
                                );
                                // 🚨THE window is what the rail and the frame
                                // rows both draw from, so the silhouette
                                // enters here — once, for both — and every
                                // surface fed by it must be fed the SAME
                                // list: the window's indices (the pinned row
                                // among them) point into it.
                                final window = _rowWindowFor(
                                  drawnRows,
                                  bodyViewportHeight,
                                  effectiveVerticalScrollOffset,
                                );
                                // I-1: the toggle columns a swipe may
                                // paint down. Read once per pass — the
                                // bands are geometry, and the swipe's
                                // own callbacks index into this list.
                                final swipeColumns = _swipeColumns();

                                return Column(
                                  children: [
                                    KeyedSubtree(
                                      key: const ValueKey<String>(
                                        'timeline-sticky-header-row',
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // The corner above the layer-axis
                                          // scrollbar: the seconds toggle, moved
                                          // off the command bar and onto the axis
                                          // whose labels it rewrites.
                                          TimelineSecondsToggleCorner(
                                            width: _metrics
                                                .verticalScrollbarWidth,
                                            height: headerHeight,
                                            showSeconds:
                                                widget.hooks.showSeconds,
                                            onChanged: widget
                                                .hooks
                                                .onShowSecondsChanged,
                                          ),
                                          // The legend rides INSIDE the rail's
                                          // window: it is the rail's own top row,
                                          // not a strip beside it, so one cut and
                                          // one push serve both (the user's rule —
                                          // "the legend and the rows are one body,
                                          // like the ruler and the cells").
                                          LayerRailWindow(
                                            axis: Axis.horizontal,
                                            rail: _railRows._railExtent,
                                            naturalExtent:
                                                _railRows.naturalRailWidth,
                                            availableExtent:
                                                availableRailExtent,
                                            // Memo-gated (UI-R7 #1): zoom steps
                                            // reuse the identical header instance.
                                            child: _railRows.legendHeaderMemoized(
                                              rows,
                                            ),
                                          ),
                                          const SizedBox(
                                            width:
                                                LayerRailSplitter.thickness,
                                          ),
                                          // D8-2 (유저 2026-08-22): the ruler
                                          // takes the frame area's own leading
                                          // edge — 「프레임영역은 기본 뭔가
                                          // 바뀌면 룰러랑 통일임」. Same widget
                                          // as the body's, so this cannot fall
                                          // behind the rows again.
                                          Expanded(
                                            child: TimelineFrameAreaEdge(
                                              child: LayoutBuilder(
                                                builder: (context, constraints) {
                                                  final viewportWidth =
                                                      constraints
                                                          .hasBoundedWidth
                                                      ? constraints.maxWidth
                                                      : 0.0;
                                                  // R9 #3: the clamp answers ONE
                                                  // question — does the controller
                                                  // need correcting after a viewport
                                                  // resize. What the ruler renders
                                                  // and hit-tests at is the scroll
                                                  // position itself.
                                                  _horizontalSync.synchronize(
                                                    _scroll.effectiveHorizontalScrollOffset(
                                                      requestedOffset:
                                                          _frameAxisOffset
                                                              .value,
                                                      viewportWidth:
                                                          viewportWidth,
                                                    ),
                                                  );
                                                  final totalFrameContentWidth =
                                                      _renderedFrameCount *
                                                      _metrics
                                                          .frameCellWidth;

                                                  // PRO-TIMELINE scrolling (UI-R15):
                                                  // the strip builds ONCE at full width
                                                  // — its painter windows itself off
                                                  // the live offset (repaint-only),
                                                  // sub-cell pixels move the TRANSLATE
                                                  // alone, and the bucket re-windowing
                                                  // is gone. Ticks/warming still
                                                  // rebuild just this one host.
                                                  // The ruler is SPLIT (the storyboard's
                                                  // shape, now shared): a static strip
                                                  // that lays out a glyph per labeled
                                                  // frame, and a thin overlay carrying
                                                  // everything that moves. Keeping the
                                                  // cursor tint in the strip meant every
                                                  // SEEK re-recorded the whole O(frames)
                                                  // glyph pass; and the cached bar reads
                                                  // DERIVED state (composites
                                                  // self-validate, nothing raises an
                                                  // "invalidated" event), so it must be
                                                  // cheap to repaint rather than gated.
                                                  final rulerContent = SizedBox(
                                                    width:
                                                        totalFrameContentWidth,
                                                    height: headerHeight,
                                                    child: Stack(
                                                      children: [
                                                        RepaintBoundary(
                                                          child: TimelineFrameRuler(
                                                            frameStartIndex:
                                                                0,
                                                            frameEndIndexExclusive:
                                                                _renderedFrameCount,
                                                            // The tint lives in the
                                                            // overlay now.
                                                            currentFrameIndex:
                                                                -1,
                                                            playhead: widget
                                                                .hooks
                                                                .frameCursor,
                                                            playbackFrameCount:
                                                                widget
                                                                    .hooks
                                                                    .playbackFrameCount,
                                                            drawnFrameCount:
                                                                widget
                                                                    .hooks
                                                                    .drawnFrameCount,
                                                            noriShiroLabel:
                                                                widget
                                                                    .hooks
                                                                    .noriShiroLabel,
                                                            leadingFrameSpacerWidth:
                                                                0,
                                                            trailingFrameSpacerWidth:
                                                                0,
                                                            metrics:
                                                                _metrics,
                                                            onSelectFrame:
                                                                _rulerScrub.selectClampedFrame,
                                                            framesPerSecond:
                                                                _countingFps,
                                                            showSeconds: widget
                                                                .hooks
                                                                .showSeconds,
                                                            windowBucket:
                                                                _frameWindowBucket,
                                                            viewportMainExtent:
                                                                viewportWidth,
                                                            dragPreview: widget
                                                                .hooks
                                                                .dragPreview,
                                                            previewCutId:
                                                                widget
                                                                    .hooks
                                                                    .cutEndDrag
                                                                    ?.cutId,
                                                          ),
                                                        ),
                                                        Positioned.fill(
                                                          child: TimelineRulerCursorOverlay(
                                                            keyValue:
                                                                'timeline-ruler-cursor-overlay',
                                                            playhead: widget
                                                                .hooks
                                                                .frameCursor,
                                                            repaintSignal:
                                                                widget
                                                                    .hooks
                                                                    .frameReadySignal,
                                                            windowBucket:
                                                                _frameWindowBucket,
                                                            viewportMainExtent:
                                                                viewportWidth,
                                                            renderedFrames:
                                                                _renderedFrameCount,
                                                            cellWidth: _metrics
                                                                .frameCellWidth,
                                                            isFrameReady: widget
                                                                .hooks
                                                                .isFrameReady,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );

                                                  return Listener(
                                                    key: const ValueKey<String>(
                                                      'timeline-frame-ruler-scrub-area',
                                                    ),
                                                    behavior:
                                                        HitTestBehavior
                                                            .translucent,
                                                    onPointerDown: (event) {
                                                      _rulerScrub.resetTracking();
                                                      _rulerScrub.pressAt(
                                                        event.position,
                                                      );
                                                    },
                                                    onPointerUp: (_) =>
                                                        _rulerScrub.endScrub(),
                                                    onPointerCancel: (_) =>
                                                        _rulerScrub.endScrub(),
                                                    child: GestureDetector(
                                                      behavior:
                                                          HitTestBehavior
                                                              .translucent,
                                                      onHorizontalDragStart:
                                                          (details) {
                                                            _rulerScrub.pressAt(
                                                              details
                                                                  .globalPosition,
                                                            );
                                                          },
                                                      onHorizontalDragUpdate:
                                                          (details) {
                                                            _rulerScrub.dragTo(
                                                              details
                                                                  .globalPosition,
                                                            );
                                                          },
                                                      onHorizontalDragEnd:
                                                          (_) =>
                                                              _rulerScrub.resetTracking(),
                                                      onHorizontalDragCancel:
                                                          _rulerScrub.resetTracking,
                                                      child: SizedBox(
                                                        key:
                                                            _rulerScrubViewportKey,
                                                        width:
                                                            viewportWidth,
                                                        height:
                                                            headerHeight,
                                                        child: ClipRect(
                                                          child: OverflowBox(
                                                            alignment:
                                                                Alignment
                                                                    .topLeft,
                                                            minWidth:
                                                                totalFrameContentWidth,
                                                            maxWidth:
                                                                totalFrameContentWidth,
                                                            minHeight:
                                                                headerHeight,
                                                            maxHeight:
                                                                headerHeight,
                                                            // Per-pixel scrolls move the
                                                            // TRANSLATE only; the content
                                                            // is the stable child below.
                                                            //
                                                            // R9 #3: the RAW scroll
                                                            // position, overscroll
                                                            // included. Clamping here
                                                            // pinned the ruler at the
                                                            // end while the body kept
                                                            // sliding — this file's
                                                            // own contract, broken by
                                                            // the clamp meant for a
                                                            // different job (deciding
                                                            // whether the CONTROLLER
                                                            // needs correcting after
                                                            // a viewport resize).
                                                            //
                                                            // 🚨★★★F-32's OTHER HALF,
                                                            // and it is the SAME
                                                            // asymmetry with the
                                                            // halves swapped: here the
                                                            // CELLS land on the device
                                                            // grid and the RULER kept
                                                            // the raw fraction.
                                                            //
                                                            // 🧪Measured at ratio 1.5,
                                                            // offset 1.5: ruler 453.5
                                                            // vs cells 453.667. ⛔I had
                                                            // read this file and
                                                            // written 「both halves
                                                            // carry the raw offset, so
                                                            // they agree」 — reading
                                                            // was wrong and the
                                                            // measurement is what
                                                            // caught it.
                                                            //
                                                            // ↩️F-95: the offset came
                                                            // from a NOTIFIER a resize
                                                            // past the end never
                                                            // reached. The follower
                                                            // reads the position when
                                                            // it paints, with the
                                                            // cells' correction on it.
                                                            child: ScrollFollower(
                                                              controller:
                                                                  _horizontalScrollController,
                                                              axisDirection:
                                                                  AxisDirection.right,
                                                              child: rulerContent,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: Stack(
                                        children: [
                                          ScrollConfiguration(
                                            // The pinned rail IS the scrollbar — the
                                            // desktop auto-overlay would double it
                                            // over the cells (UI-R10 #22 unification).
                                            behavior:
                                                ScrollConfiguration.of(
                                                  context,
                                                ).copyWith(
                                                  scrollbars: false,
                                                ),
                                            child: TimelineScrollViewport(
                                              viewportKey: const ValueKey<String>(
                                                'timeline-vertical-scroll-viewport',
                                              ),
                                              controller:
                                                  _verticalScrollController,
                                              axis: Axis.vertical,
                                              child: KeyedSubtree(
                                                key: const ValueKey<String>(
                                                  'timeline-scrollable-body',
                                                ),
                                                child: TimelineLayerFrameBodyLayout(
                                                  layerAxisScrollbarSlot:
                                                      SizedBox(
                                                        width: _metrics
                                                            .verticalScrollbarWidth,
                                                        height:
                                                            verticalContentHeight,
                                                      ),
                                                  layerControlsRail:
                                                      _railRows.buildLayerControlsRail(
                                                        drawnRows,
                                                        availableRailExtent,
                                                        window,
                                                        swipeColumns,
                                                      ),
                                                  railSplitterSlot:
                                                      const SizedBox(
                                                        width:
                                                            LayerRailSplitter
                                                                .thickness,
                                                      ),
                                                  frameGridArea:
                                                      _buildFrameGridArea(
                                                        colorScheme,
                                                        drawnRows,
                                                        window,
                                                        rangeHooks,
                                                        rangeGesture,
                                                        laneRange,
                                                        verticalContentHeight,
                                                      ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          // The layer-axis bar sat between the rail
                                          // and the cells, and its opaque hit lane
                                          // owned the only gap a splitter could
                                          // have lived in. It is the grid's left
                                          // EDGE now, and the gap it vacated is
                                          // the splitter's.
                                          Positioned(
                                            left: 0,
                                            top: 0,
                                            bottom: 0,
                                            width: _metrics
                                                .verticalScrollbarWidth,
                                            child: TimelineVerticalScrollbarRail(
                                              controller:
                                                  _verticalScrollController,
                                              viewportHeight:
                                                  bodyViewportHeight,
                                              contentHeight:
                                                  verticalContentHeight,
                                              width: _metrics
                                                  .verticalScrollbarWidth,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            SizedBox(
                              key: const ValueKey<String>(
                                'timeline-vertical-scrollbar-bottom-spacer',
                              ),
                              width: _metrics.verticalScrollbarWidth,
                              height: bottomScrollbarRailHeight,
                            ),
                            // The rail's own bar — the second of the panel's
                            // three. The rail is not a Scrollable (it is a
                            // clipped box), so this one is offset-driven.
                            LayerRailScrollbar(
                              axis: Axis.horizontal,
                              rail: _railRows._railExtent,
                              naturalExtent: _railRows.naturalRailWidth,
                              availableExtent: availableRailExtent,
                              laneExtent: bottomScrollbarRailHeight,
                              keyPrefix: 'timeline',
                            ),
                            const SizedBox(
                              key: ValueKey<String>(
                                'timeline-bottom-scrollbar-splitter-spacer',
                              ),
                              width: LayerRailSplitter.thickness,
                            ),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final viewportWidth =
                                      constraints.hasBoundedWidth
                                      ? constraints.maxWidth
                                      : 0.0;
                                  final effectiveFrameCount =
                                      _renderedFrameCount;
                                  final contentWidth =
                                      effectiveFrameCount *
                                      _metrics.frameCellWidth;

                                  return TimelineHorizontalScrollbarRail(
                                    key: const ValueKey<String>(
                                      'timeline-horizontal-scrollbar',
                                    ),
                                    controller: _horizontalScrollController,
                                    viewportWidth: viewportWidth,
                                    contentWidth: contentWidth,
                                    height: bottomScrollbarRailHeight,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    // The grip FLOATS over the 5px slot the three rows
                    // reserve, so one grab spans the legend, the rows
                    // and the scrollbar line instead of three stacked
                    // stubs — the same slot-plus-overlay idiom the
                    // scrollbar rail has always used here.
                    Positioned(
                      left:
                          _metrics.verticalScrollbarWidth +
                          railWindowExtent,
                      top: 0,
                      bottom: 0,
                      width: LayerRailSplitter.thickness,
                      child: LayerRailSplitter(
                        key: const ValueKey<String>(
                          'timeline-rail-splitter',
                        ),
                        axis: Axis.horizontal,
                        extent: _railRows._railExtent,
                        naturalExtent: _railRows.naturalRailWidth,
                        availableExtent: availableRailExtent,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Which rows a build pass actually puts on screen, and what stands in
/// for the ones it does not.
///
/// Seven locals said this before it had a name, which meant anything
/// that wanted them had to take seven arguments. The window is one
/// idea: a range, the slice it selects, the spacers holding the place
/// of the rows above and below it, and the one row A5 pins outside it.
class _RowWindow {
  const _RowWindow({
    required this.range,
    required this.rows,
    required this.leadingSpacerHeight,
    required this.trailingSpacerHeight,
    required this.pinnedIndex,
    required this.pinnedBefore,
    required this.pinnedAfter,
  });

  final TimelineVisibleRange range;

  /// The slice of the grid's rows [range] selects.
  final List<TimelineDisplayRow> rows;

  final double leadingSpacerHeight;
  final double trailingSpacerHeight;

  /// The row a drag is holding, when the window has slid past it, or
  /// -1. ⛔It is built anyway and carved out of whichever spacer it
  /// falls in — see the comment where this is computed: without it the
  /// row's State goes with the window and the grip releases mid-gesture.
  final int pinnedIndex;

  final bool pinnedBefore;
  final bool pinnedAfter;
}

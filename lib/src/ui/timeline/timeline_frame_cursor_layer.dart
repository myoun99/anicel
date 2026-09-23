import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/timeline_frame_range.dart';
import '../../models/timeline_repeat.dart';
import '../../models/timeline_row_address.dart';
import '../../models/track_frame_range.dart' show frameRangesOverlap;
import 'property_lane_model.dart';
import 'selected_exposure_display_range_policy.dart';
import 'timeline_cell_exposure_state.dart';
import 'timeline_cell_style.dart';
import 'timeline_drag_preview.dart';
import 'timeline_frame_coordinate_policy.dart';
import 'axis_turn.dart';
import 'timeline_frame_window.dart';
import 'timeline_grid_metrics.dart';
import 'timeline_instruction_row_visual.dart';
import 'timeline_playhead.dart';
import 'timeline_selected_exposure_outline.dart';
import '../text/app_strings.dart' show AppText;
import 'transform_lane_policy.dart' show laneSelectionCoversBandRow;

/// Everything of a timeline grid that moves with the frame cursor — the
/// playhead tint, the active layer's selected-cell ring (carrying the
/// grid's selected-cell semantics) and the selected exposure outline — in
/// ONE widget subscribed to the cursor.
///
/// This is the heart of the playback-performance architecture: a playback
/// tick or an editing seek repaints THIS layer only. Rows and cells never
/// depend on the cursor, so the grid's hundreds of cell widgets stay
/// untouched frame to frame (the storyboard's cheap-playhead pattern,
/// generalized). One widget serves both orientations (Axis policy).
class TimelineCursorLayer extends StatelessWidget {
  const TimelineCursorLayer({
    super.key,
    required this.frameCursor,
    required this.rows,
    required this.activeLayerId,
    this.currentRow,
    required this.frameStartIndex,
    required this.frameEndIndexExclusive,
    required this.leadingFrameSpacerWidth,
    required this.metrics,
    required this.exposureStateForLayer,
    required this.crossAxisExtent,
    this.axis = Axis.horizontal,
    this.dragPreview,
    this.frameRangeSelection,
    this.laneRangeSelection,
    this.windowBucket,
    this.viewportMainExtent = 0,
    this.selectedSemanticsKey = const ValueKey<String>(
      'timeline-selected-cell',
    ),
  });

  final ValueListenable<int> frameCursor;

  /// The session's frame-range selection (UI-R8): rendered as an accent
  /// span over the selected layer's row — this layer repaints, the rows
  /// never rebuild for it (value-only channel, cursor-layer pattern).
  final ValueListenable<TimelineFrameRangeSelection?>? frameRangeSelection;

  /// R27 #14: the LANE (fx/key) selection draws here too, with the very
  /// same band as the cell selection. It used to be a flat accent
  /// rectangle painted inside each lane band — a different silhouette,
  /// a different colour, a different corner, for what is the same idea
  /// ("다른 프레임셀선택이랑 완전동일화").
  final ValueListenable<TimelineLaneSelection?>? laneRangeSelection;

  /// The session's edit-drag preview channel: while a comma drag targets
  /// the active layer, the selection visuals (the selected-exposure
  /// outline) follow the PREVIEW layer so they ride the drag live.
  final ValueListenable<TimelineDragPreview?>? dragPreview;

  /// The grid's display rows (layer rows + expanded lanes), for the active
  /// layer's cross-axis position.
  final List<TimelineDisplayRow> rows;
  final LayerId? activeLayerId;

  /// The row you are STANDING on. There is exactly one, and the standing
  /// visuals go with it — when it is a property lane the layer's row gives
  /// its ring up.
  ///
  /// 2026-08-07 settled that as "그림은 그릴 수 있을지라도 서있는건 하나";
  /// 2026-08-08 dropped the first half. A lane takes no strokes at all now,
  /// so the row you stand on and the row you draw on are the same row again
  /// — see `MainCanvasBrushHost.rowAcceptsStrokes`.
  ///
  /// Null, or a lane whose row is not on screen, falls back to the active
  /// layer's row: showing nothing at all would read as broken rather than
  /// as elsewhere.
  final ValueListenable<TimelineRowAddress?>? currentRow;
  final int frameStartIndex;
  final int frameEndIndexExclusive;
  final double leadingFrameSpacerWidth;
  final TimelineGridMetrics metrics;
  final TimelineCellExposureState Function(Layer layer, int frameIndex)
  exposureStateForLayer;

  /// Total layer-axis extent of the rows (the playhead's length).
  final double crossAxisExtent;

  /// The frame axis direction; every visual transposes, none forks.
  final Axis axis;

  /// UI-R15→R16: the quantized frame-window bucket. When provided with a
  /// positive [viewportMainExtent], visibility gating and the outline's
  /// display clamp use the bucket-derived window (shared policy) instead
  /// of the (now full) build bounds — the widget builds once in content
  /// space, follows the viewport by itself, and rebuilds once per span
  /// crossing rather than per scrolled pixel.
  final ValueListenable<int>? windowBucket;
  final double viewportMainExtent;

  /// Semantics key marking the selected cell in this grid's namespace.
  final ValueKey<String> selectedSemanticsKey;

  ({int startIndex, int endIndexExclusive}) _visibleWindow() =>
      visibleFrameWindowFor(
        bucket: windowBucket,
        viewportMainExtent: viewportMainExtent,
        cellExtent: metrics.frameCellWidth,
        frameStartIndex: frameStartIndex,
        frameEndIndexExclusive: frameEndIndexExclusive,
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        frameCursor,
        ?dragPreview,
        ?frameRangeSelection,
        ?laneRangeSelection,
        ?currentRow,
        ?windowBucket,
      ]),
      builder: (context, _) => _overlay(),
    );
  }

  /// Everything the cursor moves, bottom to top: the playhead tint, the
  /// selected-range band, the lane-range band, the standing mark on a lane,
  /// and the active layer's row (its exposure outline and cell ring).
  ///
  /// UI-R15→R16: under full bounds + the quantized bucket, visibility GATES
  /// and the outline's display clamp use the bucket-derived window, while
  /// positioning stays in the widget's own coordinate space. This thin
  /// builder re-runs once per span crossing — never per scrolled pixel.
  Widget _overlay() {
    final frame = frameCursor.value;
    final window = _visibleWindow();
    final cursorVisible = frameWindowContains(window, frame);
    final standingLaneIndex = _standingLaneIndex();
    final children = <Widget>[
      ?_playhead(frame, cursorVisible: cursorVisible),
      ?_selectedBand(window),
      ?_standingLaneMark(
        frame,
        standingLaneIndex,
        cursorVisible: cursorVisible,
      ),
      ?_activeRow(
        frame,
        window,
        standingLaneIndex,
        cursorVisible: cursorVisible,
      ),
    ];
    // Pointer-transparent (cells keep every gesture); semantics stay.
    return IgnorePointer(
      child: acrossBox(
        axis,
        crossAxisExtent,
        child: Stack(clipBehavior: Clip.none, children: children),
      ),
    );
  }

  // ── where things are ──────────────────────────────────────────────────

  /// A frame's near edge in content pixels along the axis.
  double _frameX(int frameIndex) => frameVisibleX(
    frameIndex: frameIndex,
    frameStartIndex: frameStartIndex,
    frameCellWidth: metrics.frameCellWidth,
    leadingFrameSpacerWidth: leadingFrameSpacerWidth,
  );

  int? _rowIndexWhere(bool Function(TimelineDisplayRow row) test) {
    for (var index = 0; index < rows.length; index += 1) {
      if (test(rows[index])) return index;
    }
    return null;
  }

  /// One band for a selection over the frames [span] and the rows
  /// [coversRow] answers for — the SAME band for a cell span and a lane
  /// span (R27 #14). Null when the span has no cell inside the built
  /// [window] or covers no row on screen.
  ///
  /// [span] and [window] are the same shape on purpose: this asks whether
  /// one half-open frame range reaches the other.
  ///
  /// The rows a band covers are the first covered row through the last —
  /// contiguous in display order by construction.
  Widget? _selectionBand(
    ({int startIndex, int endIndexExclusive}) window, {
    required ({int startIndex, int endIndexExclusive}) span,
    required bool Function(TimelineDisplayRow row) coversRow,
    required ({Key key, String label}) semantics,
  }) {
    if (!frameRangesOverlap(
      span.startIndex,
      span.endIndexExclusive,
      window.startIndex,
      window.endIndexExclusive,
    )) {
      return null;
    }
    int? first;
    var count = 1;
    for (var index = 0; index < rows.length; index += 1) {
      if (!coversRow(rows[index])) continue;
      first ??= index;
      count = index - first + 1;
    }
    if (first == null) return null;
    final spanStart = _frameX(span.startIndex);
    return placedAlong(
      axis,
      along: spanStart,
      across: first * metrics.layerRowHeight,
      alongExtent: _frameX(span.endIndexExclusive) - spanStart,
      acrossExtent: count * metrics.layerRowHeight,
      child: Semantics(
        key: semantics.key,
        label: semantics.label,
        container: true,
        child: DecoratedBox(
          decoration: timelineRangeSelectionBandDecorationAt(
            cellExtent: metrics.frameCellWidth,
            crossExtent: metrics.layerRowHeight,
          ),
        ),
      ),
    );
  }

  // ── the five layers ───────────────────────────────────────────────────

  /// Mounted only while the cursor is inside the built window (the widget's
  /// own out-of-range shrink is not enough — tests and semantics treat
  /// presence of the playhead key as visibility).
  Widget? _playhead(int frame, {required bool cursorVisible}) {
    if (!cursorVisible) return null;
    return TimelinePlayhead(
      currentFrameIndex: frame,
      frameStartIndex: frameStartIndex,
      frameEndIndexExclusive: frameEndIndexExclusive,
      leadingFrameSpacerWidth: leadingFrameSpacerWidth,
      metrics: metrics,
      layerCount: rows.length,
      crossAxisExtent: crossAxisExtent,
      axis: axis,
    );
  }

  /// The frame-range selection (UI-R8): an accent span over the selected
  /// layer's row — selection reads from color alone. Excel-style spans
  /// (UI-R17 #8): the band covers every spanned row.
  ///
  /// 🚨T6 (유저 2026-08-13): 「트랜스폼 헤더행, 여전히 프레임 셀 선택범위가
  /// 혼자만 규칙 이상함. **몇번이나 말할까? 통일하라고.** 헤더행에서 선택범위
  /// 시작하면 다른 행의 프레임셀 선택불가. **내부적으로 선택된 상태일지 몰라도
  /// ui는 적어도 그렇게 안 되고 있음**」 — and that last sentence was exactly
  /// right.
  ///
  /// ⛔This used to read `!isLane && coversLayer(...)`, which is two separate
  /// mistakes wearing one condition. `!isLane` skipped every lane and header
  /// the drag had swept, and `coversLayer` asked the DERIVED layer list
  /// instead of the authoritative one — a header is not a layer, so it could
  /// not be spelled in that list at all. ③ made `rows` the authority in the
  /// model; the drawing never followed.
  ///
  /// ★[TimelineFrameRangeSelection.coversRow] is the question, and the rail
  /// already knows each row's [TimelineDisplayRow.address]. Every kind, one
  /// predicate, and a new row kind joins by existing.
  ///
  /// R27 #14: the LANE (fx/key) selection is the SAME band, drawn by the
  /// same overlay across the spanned lane rows. Lane bands used to paint
  /// their own flat rectangle each, which is why a key span read as a
  /// different kind of selection than a cell span.
  ///
  /// 🚨T6: and the CELL span WINS. There is one selected state at a time
  /// ([claimSelection]) with a single exception — a mixed cell drag ends up
  /// owning lane state too — and in that one case both bands would cover
  /// the same rows and stack their fills, so the same span would read
  /// darker for having been described twice. The cell span already knows
  /// every row it swept, lanes included. That precedence is why this is one
  /// method with an early return rather than two bands with a guard between
  /// them: a guard is a thing to remember, and an early return is not.
  Widget? _selectedBand(({int startIndex, int endIndexExclusive}) window) {
    final range = frameRangeSelection?.value;
    if (range != null) {
      return _selectionBand(
        window,
        span: (
          startIndex: range.startIndex,
          endIndexExclusive: range.endIndexExclusive,
        ),
        coversRow: (row) => range.coversRow(row.address),
        semantics: (
          key: const ValueKey<String>('timeline-frame-range-selection'),
          label: AppText.strings.tlSelectedFrameRange,
        ),
      );
    }
    final laneRange = laneRangeSelection?.value;
    if (laneRange == null) return null;
    return _selectionBand(
      window,
      span: (
        startIndex: laneRange.startIndex,
        endIndexExclusive: laneRange.endIndexExclusive,
      ),
      coversRow: (row) => _laneRowInBand(row, laneRange),
      semantics: (
        key: const ValueKey<String>('timeline-lane-range-selection'),
        label: AppText.strings.tlSelectedLaneRange,
      ),
    );
  }

  /// The BAND-ROW predicate, not the raw span (R4b fix): the transform-group
  /// HEADER row counts as covered when the selection spans its whole member
  /// group — with the group COLLAPSED the header is the only lane row on
  /// screen, and the raw check left the selection with no band at all.
  bool _laneRowInBand(TimelineDisplayRow row, TimelineLaneSelection laneRange) {
    final lane = row.lane;
    return lane != null &&
        laneSelectionCoversBandRow(laneRange, row.layer.id, lane.laneId);
  }

  /// The display row of the lane the user stands on, if standing on one.
  int? _standingLaneIndex() {
    final standing = currentRow?.value;
    if (standing is! LaneRowAddress) return null;
    return _rowIndexWhere((row) => _rowIsLane(row, standing));
  }

  bool _rowIsLane(TimelineDisplayRow row, LaneRowAddress standing) {
    final lane = row.lane;
    return lane != null &&
        row.layer.id == standing.layerId &&
        lane.laneId == standing.laneId;
  }

  /// STANDING ON A LANE takes the standing visual off the layer row and puts
  /// it here — one standing place, not two.
  ///
  /// The RING, the same one the layer row wears (user, 2026-08-08: 진짜로 서
  /// 있게). It used to draw the range-selection BAND, which is what gave the
  /// game away: a filled 2px band where the layer row's is a hollow 3px ring
  /// reads as "a one-cell selection happens to be here" — and that is
  /// exactly what it was.
  ///
  /// R5 #4: a live lane SELECTION used to switch this off, and the active
  /// layer's row then took over — so dragging a span on a member lane moved
  /// the standing mark off the lane and onto the layer, which reads as "you
  /// are on the layer now" while the model has you exactly where you were
  /// (the canvas still refuses strokes, which is how the user caught it).
  /// They are two different statements: the BAND says what is selected, the
  /// RING says where you stand, and selecting something has never been a
  /// reason to stop standing anywhere.
  Widget? _standingLaneMark(
    int frame,
    int? standingLaneIndex, {
    required bool cursorVisible,
  }) {
    if (standingLaneIndex == null || !cursorVisible) return null;
    final spanStart = _frameX(frame);
    return placedAlong(
      axis,
      along: spanStart,
      across: standingLaneIndex * metrics.layerRowHeight,
      alongExtent: _frameX(frame + 1) - spanStart,
      acrossExtent: metrics.layerRowHeight,
      child: Semantics(
        key: const ValueKey<String>('timeline-lane-standing-cell'),
        label: AppText.strings.tlSelectedCell,
        container: true,
        child: DecoratedBox(decoration: timelineStandingCellDecoration),
      ),
    );
  }

  /// Otherwise the visuals follow the ACTIVE layer's row. The exposure
  /// outline stays even while the cursor itself is scrolled out of the
  /// window (its block may still intersect); only the cell ring needs the
  /// cursor on screen.
  ///
  /// R28 #12 used to need a FOLDER clause here: the header row carried its
  /// first member as a REPRESENTATIVE layer, so this search found the
  /// folder's row index first and the block outline drew one row too high.
  /// A folder row answers to its own id now, so only lanes (which share
  /// their layer's id) are skipped.
  Widget? _activeRow(
    int frame,
    ({int startIndex, int endIndexExclusive}) window,
    int? standingLaneIndex, {
    required bool cursorVisible,
  }) {
    if (standingLaneIndex != null) return null;
    final index = _rowIndexWhere(_rowIsActiveLayer);
    if (index == null) return null;
    final activeLayer = rows[index].layer;
    final layer =
        timelineDragPreviewLayerFor(dragPreview?.value, activeLayer.id) ??
        activeLayer;
    final displayRange = _selectedDisplayRange(layer, frame, window);
    // Display rows are uniformly tall (timelineDisplayRowExtent).
    return stripAcross(
      axis,
      across: index * metrics.layerRowHeight,
      acrossExtent: metrics.layerRowHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          TimelineSelectedExposureOutline(
            axis: axis,
            layerId: layer.id,
            displayRange: displayRange,
            frameStartIndex: frameStartIndex,
            leadingFrameSpacerWidth: leadingFrameSpacerWidth,
            frameCellWidth: metrics.frameCellWidth,
            rowHeight: metrics.layerRowHeight,
            borderColor: timelineSelectedFrameBorderColor,
            borderRadius: BorderRadius.all(
              timelineBlockCornerRadiusAt(
                cellExtent: metrics.frameCellWidth,
                crossExtent: metrics.layerRowHeight,
              ),
            ),
          ),
          ?_cellRing(frame, displayRange, cursorVisible: cursorVisible),
        ],
      ),
    );
  }

  bool _rowIsActiveLayer(TimelineDisplayRow row) =>
      !row.isLane && row.layer.id == activeLayerId;

  /// Ghost cells read as EMPTY here (UI-R11 #5): the selection block outline
  /// never wraps derived exposures — they show text only, no block UI of any
  /// kind.
  /// 🚨This read is what a RANGE SELECTION measures, so a row kind missing
  /// from it selects nothing at all — the transition row's symptom (user
  /// 2026-08-11: 「선택범위… 트랜지션레이어만 작동안하니까」).
  TimelineCellExposureState _exposureStateAt(Layer layer, int frameIndex) =>
      timelineIndexIsGhost(layer, frameIndex)
      ? TimelineCellExposureState.uncovered
      : bandExposureState(layer, frameIndex, ownCels: exposureStateForLayer);

  SelectedExposureDisplayRange _selectedDisplayRange(
    Layer layer,
    int frame,
    ({int startIndex, int endIndexExclusive}) window,
  ) => resolveSelectedExposureDisplayRange(
    active: true,
    currentFrameIndex: frame,
    frameStartIndex: window.startIndex,
    frameEndIndexExclusive: window.endIndexExclusive,
    exposureStateAt: (frameIndex) => _exposureStateAt(layer, frameIndex),
  );

  /// On a drawing block the BLOCK outline is the selection visual — the
  /// single-cell ring would double it up (UI-R10 #8), so the ring keeps its
  /// semantics node (probes/tests anchor on it) but paints nothing there;
  /// empty cells keep the visible ring.
  Widget? _cellRing(
    int frame,
    SelectedExposureDisplayRange displayRange, {
    required bool cursorVisible,
  }) {
    if (!cursorVisible) return null;
    final onBlock = displayRange.resolvedRange.isBlock;
    return placedAlong(
      axis,
      along: _frameX(frame),
      across: 0,
      alongExtent: metrics.frameCellWidth,
      acrossExtent: metrics.layerRowHeight,
      child: Semantics(
        key: selectedSemanticsKey,
        label: AppText.strings.tlSelectedCell,
        container: true,
        child: onBlock
            ? const SizedBox.expand()
            : DecoratedBox(decoration: timelineStandingCellDecoration),
      ),
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/layer_id.dart';
import '../../models/range_snap.dart' show StandingUnit;
import '../../models/timeline_frame_range.dart';
import '../../models/timeline_row_address.dart';
import '../../models/track_frame_range.dart' show frameRangesOverlap;
import 'property_lane_model.dart';
import 'timeline_cell_style.dart';
import 'timeline_drag_preview.dart';
import 'timeline_frame_coordinate_policy.dart';
import 'axis_turn.dart';
import 'timeline_frame_window.dart';
import 'timeline_grid_metrics.dart';
import 'timeline_playhead.dart';
import '../text/app_strings.dart' show AppText;
import '../widgets/tick_layer.dart';
import 'transform_lane_policy.dart' show laneSelectionCoversBandRow;

/// Everything of a timeline grid that moves with the frame cursor — the
/// standing wash, the playhead, the selection bands and the standing cell's
/// semantics — in ONE widget subscribed to the cursor.
///
/// This is the heart of the playback-performance architecture: a playback
/// tick or an editing seek repaints THIS layer only, and lays out this layer
/// only ([TickLayer]). Rows and cells never
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
    required this.crossAxisExtent,
    this.axis = Axis.horizontal,
    this.frameRangeSelection,
    this.laneRangeSelection,
    this.dragPreview,
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

  /// The edit-drag preview the rows below show: while a drag reshapes the
  /// row you stand on, the standing wash reads that row as previewed, so it
  /// rides the drag (H12) instead of holding the block's old seat. Null where
  /// the rows show no preview.
  final ValueListenable<TimelineDragPreview?>? dragPreview;

  /// The grid's display rows (layer rows + expanded lanes), for the active
  /// layer's cross-axis position.
  final List<TimelineDisplayRow> rows;
  final LayerId? activeLayerId;

  /// The row you are STANDING on. There is exactly one, and the standing
  /// cell goes with it — when it is a property lane the layer's row gives
  /// it up.
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
    // Pointer-transparent (cells keep every gesture); semantics stay.
    return IgnorePointer(
      child: acrossBox(
        axis,
        crossAxisExtent,
        // 🚨Laid out alone as well as painted alone (I-22 ③): rebuilt bare,
        // the listener below laid the grid's frame area out again — and the
        // panel's scroll viewport with it — on every playback frame. Tight
        // here: the box above fixes the cross axis, and every mount fixes
        // the frame axis (the grid stack's slot, the folded row's fill).
        child: TickLayer(
          child: ListenableBuilder(
            listenable: Listenable.merge([
              frameCursor,
              ?frameRangeSelection,
              ?laneRangeSelection,
              ?currentRow,
              ?dragPreview,
              ?windowBucket,
            ]),
            builder: (context, _) => _overlay(),
          ),
        ),
      ),
    );
  }

  /// Everything the cursor moves, bottom to top: the standing wash, the
  /// playhead, the selected-range band or the lane-range band, and the
  /// standing cell.
  ///
  /// UI-R15→R16: under full bounds + the quantized bucket, visibility GATES
  /// use the bucket-derived window, while positioning stays in the widget's
  /// own coordinate space. This thin builder re-runs once per span
  /// crossing — never per scrolled pixel.
  Widget _overlay() {
    final frame = frameCursor.value;
    final window = _visibleWindow();
    final cursorVisible = frameWindowContains(window, frame);
    final standing = _standingRow();
    final children = <Widget>[
      if (standing != null) ?_standingWash(standing, frame, window),
      ?_playhead(frame, cursorVisible: cursorVisible),
      ?_selectedBand(window),
      if (standing != null && cursorVisible) _standingCell(standing, frame),
    ];
    return Stack(clipBehavior: Clip.none, children: children);
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

  // ── the layers ────────────────────────────────────────────────────────

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

  /// The row you stand on, as a display row: the lane when you stand on one,
  /// the active layer's row otherwise (one standing place, not two).
  ({int index, bool lane})? _standingRow() {
    final lane = _standingLaneIndex();
    if (lane != null) return (index: lane, lane: true);
    final layer = _rowIndexWhere(_rowIsActiveLayer);
    return layer == null ? null : (index: layer, lane: false);
  }

  /// The unit the playhead stands on, on [row] — what a click on that cell
  /// selects ([standingUnitOnRow]): its block, or the one cell when it has
  /// none (F-175: 「빈 공간 한칸은 블럭으로서 한칸으로 쳐서」). A lane's keys
  /// are points, not blocks, so on a lane it is the cell.
  ///
  /// The row as the rows below show it: through a drag, previewed.
  StandingUnit _standingUnit(TimelineDisplayRow row, int frame) => row.isLane
      ? (startIndex: frame, endIndexExclusive: frame + 1, block: false)
      : standingUnitOnRow(
          timelineRowPreviewLayer(dragPreview?.value, row.layer) ?? row.layer,
          frame,
        );

  /// 🗣️F-248 (유저 2026-09-30 「외곽라인말고 블럭을 바탕색으로서 강조색
  /// 표시. 전처럼 연하게」, 10-01 「재생헤드가 선 블록」): the unit you stand on
  /// wears the standing wash — a fill and no line, under the playhead's.
  /// It stays while the playhead is scrolled out of the window and the unit
  /// still reaches into it.
  Widget? _standingWash(
    ({int index, bool lane}) standing,
    int frame,
    ({int startIndex, int endIndexExclusive}) window,
  ) {
    final unit = _standingUnit(rows[standing.index], frame);
    if (!frameRangesOverlap(
      unit.startIndex,
      unit.endIndexExclusive,
      window.startIndex,
      window.endIndexExclusive,
    )) {
      return null;
    }
    final unitStart = _frameX(unit.startIndex);
    return placedAlong(
      axis,
      along: unitStart,
      across: standing.index * metrics.layerRowHeight,
      alongExtent: _frameX(unit.endIndexExclusive) - unitStart,
      acrossExtent: metrics.layerRowHeight,
      child: DecoratedBox(
        key: const ValueKey<String>('timeline-standing-wash'),
        decoration: timelineStandingWashDecorationAt(
          cellExtent: metrics.frameCellWidth,
          crossExtent: metrics.layerRowHeight,
          block: unit.block,
        ),
      ),
    );
  }

  /// Where you STAND, said to semantics and to the probes that read it —
  /// the cell under the playhead on the row you stand on. It paints
  /// nothing; the wash under it ([_standingWash]) is what shows.
  ///
  /// 🗣️F-212 (유저 2026-09-28): 「현재 블록이나 갭 등 위치를 알리는 실루엣
  /// 라인, 초기부터 있었지만 삭제하고싶음. 현재 재생헤드의 세로 바탕색
  /// 오버레이만으로 충분하다고 판단」 — the playhead says where you stand.
  /// ↩️The active row wore a ring round the block or the gap under the
  /// playhead, and a 3px ring on an empty cell; a lane you stood on wore
  /// the 3px ring (user, 2026-08-08: 진짜로 서 있게).
  Widget _standingCell(({int index, bool lane}) standing, int frame) {
    final spanStart = _frameX(frame);
    return placedAlong(
      axis,
      along: spanStart,
      across: standing.index * metrics.layerRowHeight,
      alongExtent: _frameX(frame + 1) - spanStart,
      acrossExtent: metrics.layerRowHeight,
      child: Semantics(
        key: standing.lane
            ? const ValueKey<String>('timeline-lane-standing-cell')
            : selectedSemanticsKey,
        label: AppText.strings.tlSelectedCell,
        container: true,
        child: const SizedBox.expand(),
      ),
    );
  }

  /// R28 #12 used to need a FOLDER clause here: the header row carried its
  /// first member as a REPRESENTATIVE layer, so this search found the
  /// folder's row index first and the standing visuals drew one row too high.
  /// A folder row answers to its own id now, so only lanes (which share
  /// their layer's id) are skipped.
  bool _rowIsActiveLayer(TimelineDisplayRow row) =>
      !row.isLane && row.layer.id == activeLayerId;
}

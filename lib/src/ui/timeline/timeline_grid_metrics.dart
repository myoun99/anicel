/// Shared dimensions for the layer timeline grid.
///
/// These values mirror the current [LayerTimelineGrid] layout so calculation-
/// only virtualization helpers can use the same geometry as the rendered UI.
///
/// The constants below are the HORIZONTAL timeline's geometry, named at the
/// top level so the TRANSPOSED surface can derive from them (R10 R6).
///
/// The x-sheet is the same grid turned on its side, and until R6 it said so
/// only in a comment: it carried its own 36/164/72/92, hand-tuned and free
/// to drift. Every one of those numbers is now one of these constants
/// rotated, so when the timeline's layer area is made compact the sheet
/// follows without anyone remembering to move it.
///
/// The mapping, in one place:
///
/// | x-sheet                  | is the timeline's        |
/// |--------------------------|--------------------------|
/// | column width             | row height               |
/// | frame row height         | frame cell width         |
/// | header block height      | rail width               |
/// | frame-number rail width  | ruler height             |
library;

import 'package:flutter/widgets.dart';

import '../text/text_measure.dart';
import '../widgets/app_scrollbar_lane.dart';
import 'layer_label_controls.dart'
    show
        LayerRailColumnWidths,
        layerBlendSlotWidth,
        layerOpacitySlotWidth,
        layerRailColumnWidthsAtOne,
        layerRowNameStyle;

/// Width of one frame cell on the frame axis.
/// 48 → 24 (R-toolbar slim round, CSP/TVPaint density).
const double timelineFrameCellWidth = 24;

/// Height of one layer row on the layer axis.
/// 52 → 28 (same round).
const double timelineLayerRowHeight = 28;

/// A layer row's height where it is shown: [timelineLayerRowHeight] and
/// its name's growth under the OS text size ([timelineLayerRowGrowthIn]) —
/// 0 at 1×, so nothing drawn at 1× moves.
///
/// 🚨text-scale-rail-rows (유저 2026-09-24: 「행도 글자 크기를 따라
/// 자란다」, with its stated cost — fewer rows on screen, and every surface
/// that reads the row height follows it). The rail's row and the grid's
/// cell are ONE row, so they are one number, and it is asked here.
double timelineLayerRowHeightIn(BuildContext context) =>
    timelineLayerRowHeight + timelineLayerRowGrowthIn(context);

/// How much taller a row's NAME stands where [context] lays it out than at
/// 1× — what every row drawn around one line of it adds, whatever height
/// it was drawn at: the timeline's row above, and the storyboard's S,
/// transition and lane rows (text-scale-storyboard-rows).
///
/// Remembered against every input it reads — the text scaler, the name's
/// style and the direction — so the storyboard's rows, which each ask, lay
/// the line out once between them and not once per row. A change to any
/// input is a different key, so the answer cannot go stale.
double timelineLayerRowGrowthIn(BuildContext context) {
  final style = layerRowNameStyle(context);
  final key = (
    scaler: MediaQuery.textScalerOf(context),
    style: style,
    direction: Directionality.of(context),
  );
  final remembered = _rowGrowthMemo;
  if (remembered != null && remembered.key == key) {
    return remembered.growth;
  }
  final growth = TextMeasure(
    context,
    style,
  ).lineGrowthOf(TextMeasure.everyScript);
  _rowGrowthMemo = (key: key, growth: growth);
  return growth;
}

({Object key, double growth})? _rowGrowthMemo;

/// Width of the fixed layer rail.
/// 288 → 312 when the layer rows gained the fx switch (R3 ⑪); the row
/// controls need the width, cramming them under 288 overflowed.
/// 312 → 340 → 372: wider layer-name column (UI-R3 #8, UI-R4 #9; the
/// R4 hop also absorbs the legend's new kind cell).
/// 372 → 434 (R27 #6): the blend-mode dropdown moved from the toolbar
/// into the label's rightmost slot — the rail pays its width, as the
/// user directed ("레이어라벨 더 키워야겟지").
const double timelineLayerControlsWidth = 434;

/// [timelineLayerControlsWidth] with [columns] in place of the 1× ones —
/// the rail pays for its word-holding columns' growth
/// (text-scale-rail-columns), as it paid for the blend column (R27 #6).
double timelineLayerControlsWidthFor(LayerRailColumnWidths columns) =>
    timelineLayerControlsWidth +
    (columns.opacity - layerOpacitySlotWidth) +
    (columns.blend - layerBlendSlotWidth);

/// How thick the frame RULER is across the layer axis — exactly one row
/// (`headerHeight = _metrics.layerRowHeight` in the grid), which is why the
/// ruler's ticks line up with the rows below it.
const double timelineFrameRulerExtent = timelineLayerRowHeight;

/// The section-bracket gutter leading the rail: retired in UI-R5, section
/// labels live INSIDE their first row now.
const double timelineSectionLabelGutterWidth = 0;

/// Width of the grid's vertical scrollbar COLUMN.
///
/// 14 → 16 (rail-window round): the lane has to be comfortable to grab
/// because it stopped being a leftover gap between the rail and the cells.
/// The timeline moved it to the far left so the splitter could have that
/// gap; the x-sheet's column now carries two bars, the rail's above the
/// splitter and the frame's below it.
const double timelineVerticalScrollbarWidth = AppScrollbarLane.wide;

/// The horizontal scrollbar rail closing the bottom of a grid. Both grids
/// declared it privately (R10 R6 found the third copy while deriving the
/// x-sheet's header against it); a number two surfaces subtract from the
/// same viewport belongs to neither of them.
const double timelineBottomScrollbarRailHeight = AppScrollbarLane.wide;

/// The paper-timesheet stride LADDER a frame axis thins its marks on (user
/// rule, R-toolbar slim round): every frame, then every 3rd (1, 4, 7, …),
/// 6th (1, 7, 13, …), 12th (1, 13, 25) and 24th (1, 25), doubling on —
/// always anchored at frame 1.
///
/// ↩️I-22 (유저 2026-09-12): 「룰러 텍스트 글자가 겹칠때 생략한다는
/// 느낌으로」. The rungs are the user's; WHICH rung stood at a zoom was a
/// threshold on the cell width here (every frame from 20px, then the first
/// rung spanning 40px) that claimed "labels never crowd or overflow"
/// without measuring one, and the grid's lines followed it down. Each mark
/// now climbs the ladder on its own measure — a number by its measured
/// extent (`TimelineRulerScale.labelEveryFrames`), a line by its stroke
/// (`timelineGridLineEveryFrames`).
const List<int> timelineFrameStrideLadder = [1, 3, 6, 12, 24, 48, 96];

/// The densest rung of [timelineFrameStrideLadder] whose span, over cells of
/// [cellExtent], holds a mark of [markExtent] — the one question both marks
/// ask, each with its own extent.
int timelineStrideHolding(double markExtent, double cellExtent) {
  for (final stride in timelineFrameStrideLadder) {
    if (markExtent <= stride * cellExtent) {
      return stride;
    }
  }
  return timelineFrameStrideLadder.last;
}

class TimelineGridMetrics {
  static const int defaultMinimumVisibleFrameCells = 24;

  const TimelineGridMetrics({
    this.minimumVisibleFrameCells = defaultMinimumVisibleFrameCells,
    this.layerControlsWidth = timelineLayerControlsWidth,
    this.frameCellWidth = timelineFrameCellWidth,
    this.layerRowHeight = timelineLayerRowHeight,
    this.verticalScrollbarWidth = timelineVerticalScrollbarWidth,
    this.sectionLabelGutterWidth = timelineSectionLabelGutterWidth,
    this.railColumns = layerRailColumnWidthsAtOne,
  }) : assert(minimumVisibleFrameCells >= 0),
       assert(layerControlsWidth >= 0),
       assert(frameCellWidth > 0),
       assert(layerRowHeight > 0),
       assert(verticalScrollbarWidth >= 0),
       assert(sectionLabelGutterWidth >= 0);

  /// Default metrics matching the current [LayerTimelineGrid] behavior.
  static const TimelineGridMetrics defaults = TimelineGridMetrics();

  /// Same geometry with a different frame-axis cell extent (zoom), or a
  /// different NATURAL rail extent.
  ///
  /// The rail extent is here for hosts that state their own — the
  /// storyboard's rail, which carries the same number as this one since
  /// 2026-08-04 and is deliberately still its own constant (the user's
  /// condition: same width, independent in code). NOT for the splitter:
  /// the window size is a listenable precisely so it stays out of this
  /// memo key.
  ///
  /// And a different ROW HEIGHT, for the host that shows the grid: a row
  /// grows with its words under the OS text size
  /// ([timelineLayerRowHeightIn], text-scale-rail-rows).
  TimelineGridMetrics copyWith({
    double? frameCellWidth,
    double? layerControlsWidth,
    double? layerRowHeight,
    LayerRailColumnWidths? railColumns,
  }) {
    return TimelineGridMetrics(
      minimumVisibleFrameCells: minimumVisibleFrameCells,
      layerControlsWidth: layerControlsWidth ?? this.layerControlsWidth,
      frameCellWidth: frameCellWidth ?? this.frameCellWidth,
      layerRowHeight: layerRowHeight ?? this.layerRowHeight,
      verticalScrollbarWidth: verticalScrollbarWidth,
      sectionLabelGutterWidth: sectionLabelGutterWidth,
      railColumns: railColumns ?? this.railColumns,
    );
  }

  /// Minimum frame cells kept visible even when the cut has fewer frames.
  final int minimumVisibleFrameCells;

  /// Width of the fixed layer controls column.
  final double layerControlsWidth;

  /// Width of each frame cell and frame header.
  final double frameCellWidth;

  /// Height of each layer row and the frame header row.
  final double layerRowHeight;

  /// Width reserved for the visible vertical scrollbar between the layer rail
  /// and frame grid area.
  final double verticalScrollbarWidth;

  /// The section-bracket gutter leading the layer rail (the timesheet's
  /// ACTION/SE/CAMERA group headings wrapping their rows); included in
  /// [layerControlsWidth].
  final double sectionLabelGutterWidth;

  /// The rail's word-holding columns where the grid is shown
  /// ([layerRailColumnWidthsIn], text-scale-rail-columns). Every rail
  /// row, the legend and the sheet's stood-up headers lay their
  /// trailing run out from this one answer.
  final LayerRailColumnWidths railColumns;

  @override
  bool operator ==(Object other) {
    return other is TimelineGridMetrics &&
        other.minimumVisibleFrameCells == minimumVisibleFrameCells &&
        other.layerControlsWidth == layerControlsWidth &&
        other.frameCellWidth == frameCellWidth &&
        other.layerRowHeight == layerRowHeight &&
        other.verticalScrollbarWidth == verticalScrollbarWidth &&
        other.sectionLabelGutterWidth == sectionLabelGutterWidth &&
        other.railColumns == railColumns;
  }

  @override
  int get hashCode => Object.hash(
    minimumVisibleFrameCells,
    layerControlsWidth,
    frameCellWidth,
    layerRowHeight,
    verticalScrollbarWidth,
    sectionLabelGutterWidth,
    railColumns,
  );

  @override
  String toString() {
    return 'TimelineGridMetrics('
        'minimumVisibleFrameCells: $minimumVisibleFrameCells, '
        'layerControlsWidth: $layerControlsWidth, '
        'frameCellWidth: $frameCellWidth, '
        'layerRowHeight: $layerRowHeight, '
        'verticalScrollbarWidth: $verticalScrollbarWidth, '
        'railColumns: $railColumns)';
  }
}

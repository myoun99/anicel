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

import '../widgets/app_scrollbar_lane.dart';

/// Width of one frame cell on the frame axis.
/// 48 → 24 (R-toolbar slim round, CSP/TVPaint density).
const double timelineFrameCellWidth = 24;

/// Height of one layer row on the layer axis.
/// 52 → 28 (same round).
const double timelineLayerRowHeight = 28;

/// Width of the fixed layer rail.
/// 288 → 312 when the layer rows gained the fx switch (R3 ⑪); the row
/// controls need the width, cramming them under 288 overflowed.
/// 312 → 340 → 372: wider layer-name column (UI-R3 #8, UI-R4 #9; the
/// R4 hop also absorbs the legend's new kind cell).
/// 372 → 434 (R27 #6): the blend-mode dropdown moved from the toolbar
/// into the label's rightmost slot — the rail pays its width, as the
/// user directed ("레이어라벨 더 키워야겟지").
const double timelineLayerControlsWidth = 434;

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

class TimelineGridMetrics {
  static const int defaultMinimumVisibleFrameCells = 24;

  const TimelineGridMetrics({
    this.minimumVisibleFrameCells = defaultMinimumVisibleFrameCells,
    this.layerControlsWidth = timelineLayerControlsWidth,
    this.frameCellWidth = timelineFrameCellWidth,
    this.layerRowHeight = timelineLayerRowHeight,
    this.verticalScrollbarWidth = timelineVerticalScrollbarWidth,
    this.sectionLabelGutterWidth = timelineSectionLabelGutterWidth,
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
  TimelineGridMetrics copyWith({
    double? frameCellWidth,
    double? layerControlsWidth,
  }) {
    return TimelineGridMetrics(
      minimumVisibleFrameCells: minimumVisibleFrameCells,
      layerControlsWidth: layerControlsWidth ?? this.layerControlsWidth,
      frameCellWidth: frameCellWidth ?? this.frameCellWidth,
      layerRowHeight: layerRowHeight,
      verticalScrollbarWidth: verticalScrollbarWidth,
      sectionLabelGutterWidth: sectionLabelGutterWidth,
    );
  }

  /// Frame-number label cadence for the header/rail: every frame when cells
  /// are wide enough, then the paper-timesheet ladder anchored at frame 1
  /// (user rule): 3f (1,4,7,…) → 6f (1,7,13,…) → 12f (1,13,25) → 24f
  /// (1,25) → doubling on. Labels never crowd or overflow.
  int get frameLabelEveryFrames {
    if (frameCellWidth >= 20) {
      return 1;
    }
    const strideLadder = [3, 6, 12, 24, 48, 96];
    for (final stride in strideLadder) {
      if (frameCellWidth * stride >= 40) {
        return stride;
      }
    }
    return strideLadder.last;
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

  @override
  bool operator ==(Object other) {
    return other is TimelineGridMetrics &&
        other.minimumVisibleFrameCells == minimumVisibleFrameCells &&
        other.layerControlsWidth == layerControlsWidth &&
        other.frameCellWidth == frameCellWidth &&
        other.layerRowHeight == layerRowHeight &&
        other.verticalScrollbarWidth == verticalScrollbarWidth &&
        other.sectionLabelGutterWidth == sectionLabelGutterWidth;
  }

  @override
  int get hashCode => Object.hash(
    minimumVisibleFrameCells,
    layerControlsWidth,
    frameCellWidth,
    layerRowHeight,
    verticalScrollbarWidth,
    sectionLabelGutterWidth,
  );

  @override
  String toString() {
    return 'TimelineGridMetrics('
        'minimumVisibleFrameCells: $minimumVisibleFrameCells, '
        'layerControlsWidth: $layerControlsWidth, '
        'frameCellWidth: $frameCellWidth, '
        'layerRowHeight: $layerRowHeight, '
        'verticalScrollbarWidth: $verticalScrollbarWidth)';
  }
}

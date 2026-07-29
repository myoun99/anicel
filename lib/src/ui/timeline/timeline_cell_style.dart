import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'timeline_cell_exposure_state.dart';
import 'timeline_grid_metrics.dart';

class TimelineCellStyleColors {
  const TimelineCellStyleColors({
    required this.background,
    required this.border,
  });

  final Color background;
  final Color border;
}

/// Drawing exposure blocks read like paper timesheet cells: near-white on
/// the dark grid so held runs are unmistakable at a glance.
const Color timelineDrawingHeldColor = Color(0xFFE9E7E2);
const Color timelineDrawingStartColor = timelineDrawingHeldColor;
const Color timelineDrawingStartBorderColor = AppColors.hairlineStrong;

/// LIVE accent read (UI-R22 #5): the selection ink follows accent 1.
Color get timelineSelectedFrameBorderColor => AppColors.accent;

/// R27 #14: the ONE range-selection band — cells and property lanes draw
/// exactly this, so a key span cannot read as a different kind of
/// selection than a cell span ("다른 프레임셀선택이랑 완전동일화").
/// Non-const because the accent is live (UI-R22 #5).
BoxDecoration get timelineRangeSelectionBandDecoration => BoxDecoration(
  color: timelineSelectedFrameBorderColor.withValues(alpha: 0.18),
  border: Border.all(color: timelineSelectedFrameBorderColor, width: 2),
  borderRadius: const BorderRadius.all(Radius.circular(6)),
);

/// Ink for glyphs (frame names, marks) sitting on the near-white drawing
/// blocks; the usual light on-surface text would vanish there.
const Color timelineDrawingInkColor = Color(0xFF26282B);

/// The mirror of [timelineDrawingInkColor] for chrome that sits on a DARK
/// lane instead of on the paper — the storyboard strip's cut blocks
/// (feedback #11: "배경이 흰색일경우의 엣지랑 컷블록처럼 배경이 어두울
/// 때의 엣지"). The near-black bar vanished against them.
const Color timelineLaneInkColor = Color(0xFFF2F4F6);

/// R26 #44 / R27 #13: ACTION-section blocks whose cel holds NO picture
/// yet read as the paper at LOW OPACITY — the user's ask ("흰색에서 그냥
/// 불투명도 낮추는 느낌… 투명감나게"). Against the dark lane the alpha
/// resolves to a distinctly greyer, see-through paper, which the old
/// near-white 0xFFD7D5D0 never managed. Painting a translucent colour
/// costs the same as an opaque one, so this stays free.
const Color timelineEmptyCelBlockColor = Color(0x6EE9E7E2);

/// The PLAIN (non-block) frame grid's border alpha (UI-R14 #4): ONE
/// faint value for every surface — the painterized drawing rows, the
/// sparse widget rows (SE/camera/instruction), the frame ruler cells and
/// the storyboard's frame lines — so the 6f/24f beat lines alone carry
/// the rhythm.
const double timelineBaseGridAlpha = 0.25;

/// The base grid's line CADENCE at [frameCellExtent] (UI-R18 #8/#12, the
/// storyboard recipe adopted everywhere): instead of alpha-fading away at
/// small zooms, the per-cell lines THIN to every Nth frame (the label
/// cadence) and never disappear — "the grid is always there".
int timelineGridLineEveryFrames(double frameCellExtent) => frameCellExtent >= 16
    ? 1
    : TimelineGridMetrics(
        frameCellWidth: frameCellExtent,
      ).frameLabelEveryFrames;

/// The glyph size that FITS a cell of [frameCellExtent] (R26 #38/#4).
///
/// Text used to blank out below ~14px cells; the user's rule is "엄청
/// 작아지는 한이 있어도 절대 안 사라지도록" — so the type shrinks with the
/// cell instead, down to a hard floor that still reads as a mark.
///
/// [crossExtent] is the cell's OTHER dimension (#15's vertical half of
/// the same rule): the fit takes whichever axis is tighter, so squeezing
/// a row's height shrinks its text exactly like squeezing its cells'
/// width does. Callers pass their own axes — on the X-sheet the main
/// extent is already the height and the cross extent the width, and the
/// min makes that swap irrelevant.
double timelineFittedGlyphFontSize(
  double baseFontSize,
  double frameCellExtent, {
  double? crossExtent,
}) {
  const floor = 4.0;
  double fit(double extent) => extent >= 14
      ? baseFontSize
      : (extent * 0.78).clamp(floor, baseFontSize);
  final main = fit(frameCellExtent);
  final cross = crossExtent == null ? baseFontSize : fit(crossExtent);
  return main < cross ? main : cross;
}

/// The outline stroke width for an outlined glyph at [fontSize] (#15):
/// proportional so the floor-sized marks are not swallowed by their own
/// outline.
double timelineGlyphOutlineWidthFor(double fontSize) =>
    (fontSize / 4.5).clamp(1.0, 2.0);

/// The plain grid's border ink — FLAT faint (UI-R18 #8: the zoom fade is
/// gone; density is handled by [timelineGridLineEveryFrames]).
Color timelineBaseGridInk(
  ColorScheme colorScheme, {
  required double frameCellExtent,
}) => colorScheme.outlineVariant.withValues(alpha: timelineBaseGridAlpha);

/// Whether [exposureState] renders on the light drawing-block background
/// (and therefore needs [timelineDrawingInkColor] text).
bool timelineCellUsesDrawingInk(TimelineCellExposureState exposureState) {
  return exposureState.isCovered;
}

/// The active-row WASH — painted once per row as an underlay (UI-R21 #2),
/// never per cell: cell rasters are active-independent now, so switching
/// the active layer re-rasters nothing.
Color timelineActiveRowWashColor(ColorScheme colorScheme) =>
    colorScheme.secondaryContainer.withValues(alpha: 0.35);

/// A cut block's fill (the storyboard's V row).
///
/// These two live beside the cell colours rather than in a block widget of
/// their own: the row paints its blocks now, and a painter reaching into a
/// widget's private styling would have been a copy of it. Same vocabulary,
/// one place — the active accent, the hover lift (R27 #11: a faint surface
/// lift rather than a thicker border, so nothing reflows) and the
/// colour-only range tint.
Color storyboardCutBlockBackgroundColor(
  ColorScheme colorScheme, {
  required bool active,
  required bool hovered,
  required bool rangeSelected,
}) {
  final resting = active
      ? colorScheme.primaryContainer
      : colorScheme.surfaceContainerHighest;
  final base = hovered && !active
      ? Color.alphaBlend(
          colorScheme.onSurface.withValues(alpha: 0.10),
          resting,
        )
      : resting;
  if (!rangeSelected) {
    return base;
  }
  // 0.12 = the timeline's selected-CELL tint: the shared range-selection
  // band ([timelineRangeSelectionBandDecoration], 0.18) rides above this,
  // and the pair must sum to the timeline's look, not overshoot it.
  return Color.alphaBlend(
    timelineSelectedFrameBorderColor.withValues(alpha: 0.12),
    base,
  );
}

/// A cut block's border ink. R26 #8: the resting edge follows the lane's
/// BRIGHTNESS — a dark lane gets a light edge and a light lane a dark one;
/// the old single grey vanished against the near-black track background.
Color storyboardCutBlockEdgeColor(
  ColorScheme colorScheme,
  Brightness brightness, {
  required bool active,
  required bool hovered,
}) {
  if (active) {
    return colorScheme.primary;
  }
  if (hovered) {
    return colorScheme.onSurface.withValues(alpha: 0.95);
  }
  return colorScheme.onSurface.withValues(
    alpha: brightness == Brightness.dark ? 0.60 : 0.45,
  );
}

TimelineCellStyleColors timelineCellStyleColors({
  required ColorScheme colorScheme,
  required TimelineCellExposureState exposureState,
  required bool selected,
}) {
  // UI-R21 #2: empty cells paint NOTHING — the row-level underlay owns
  // the paper (a surface base plus the active-row wash), so the cell
  // substrate carries no per-row state at all.
  const emptyBaseColor = Colors.transparent;
  final exposureColor = switch (exposureState) {
    TimelineCellExposureState.uncovered ||
    TimelineCellExposureState.markUncovered => emptyBaseColor,
    TimelineCellExposureState.drawingStart => timelineDrawingStartColor,
    TimelineCellExposureState.held ||
    TimelineCellExposureState.markHeld => timelineDrawingHeldColor,
  };
  // UI-R18 #8: the GRID OVERLAY owns every plain per-cell line now —
  // uncovered cells draw no border of their own, and the paper blocks'
  // seams (block START included, UI-R20 #7: the dark head silhouette is
  // gone) all sit on the shared faint alpha.
  final exposureBorderColor = switch (exposureState) {
    TimelineCellExposureState.uncovered ||
    TimelineCellExposureState.markUncovered => Colors.transparent,
    TimelineCellExposureState.drawingStart ||
    TimelineCellExposureState.held ||
    TimelineCellExposureState.markHeld => colorScheme.outlineVariant.withValues(
      alpha: timelineBaseGridAlpha,
    ),
  };

  if (!selected) {
    return TimelineCellStyleColors(
      background: exposureColor,
      border: exposureBorderColor,
    );
  }

  return TimelineCellStyleColors(
    background: Color.alphaBlend(
      timelineSelectedFrameBorderColor.withValues(alpha: 0.12),
      exposureColor,
    ),
    border: timelineSelectedFrameBorderColor,
  );
}

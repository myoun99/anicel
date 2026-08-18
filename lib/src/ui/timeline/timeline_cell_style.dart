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
///
/// The DEFAULT paper — since ⑲/⑳ a block takes its layer's colour label
/// instead, and [LayerMark.none] resolves to exactly this, so a row with no
/// label is painted by the same number it always was.
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

/// The ring on the cell you are STANDING on, wherever that is: a layer's
/// row, an fx header, a property lane.
///
/// ONE decoration, because standing is ONE thing (user, 2026-08-08). A
/// lane used to borrow [timelineRangeSelectionBandDecoration] for this —
/// filled, 2px, 6px corners against this unfilled 3px 4px one — so
/// standing on a property read as a one-cell SELECTION rather than as
/// standing, and you could see the difference in the stroke weight.
BoxDecoration get timelineStandingCellDecoration => BoxDecoration(
  border: Border.all(color: timelineSelectedFrameBorderColor, width: 3),
  borderRadius: const BorderRadius.all(Radius.circular(4)),
);

/// Ink for glyphs (frame names, marks) sitting on the near-white drawing
/// blocks; the usual light on-surface text would vanish there.
const Color timelineDrawingInkColor = Color(0xFF26282B);

/// THE text-on-ground law (2026-08-17, the difference blend's successor —
/// device verdict: white ink in [BlendMode.difference] read as navy over
/// the PURPLE blocks). The blocks are painted by our own code with KNOWN
/// colors, so the writing simply picks solid BLACK or WHITE by the
/// luminance of the ground it sits on: crisp glyphs, no halo, no blend.
const Color timelineTextOnLightGroundColor = Color(0xFF000000);
const Color timelineTextOnDarkGroundColor = Color(0xFFFFFFFF);

/// The crossover luminance where black's WCAG contrast overtakes white's:
/// black wins iff (L+0.05)² > 0.05×1.05, i.e. L > √0.0525−0.05 ≈ 0.1791.
/// Sitting exactly there makes every pick the higher-contrast one by
/// construction — every layer-mark paper lands BLACK (purple, the reported
/// regression, is L≈0.22 where white manages only 3.9:1 against black's
/// 5.4:1), the dark lanes land WHITE (15:1+), and the 43%-alpha empty-cel
/// blends land WHITE for every colored mark (purple's is L≈0.07, white
/// 9.0:1) — only the plain paper's blend sits a hair ABOVE the crossover
/// (L≈0.181), where the two inks are equal anyway (4.6:1 vs 4.5:1).
const double timelineTextGroundLuminanceCrossover = 0.179;

/// Whether [ground] takes the DARK ink under the law above.
bool timelineGroundIsLight(Color ground) =>
    ground.computeLuminance() > timelineTextGroundLuminanceCrossover;

/// The block/코마 writing's ink over [ground] — ONE rule on every surface
/// (run duration labels, storyboard band text, panel writing, the edge
/// grip bars). [ground] must be the COMPOSITED color the mark actually
/// sits on: a translucent paper is blended over its backdrop first
/// (`computeLuminance` ignores alpha).
Color timelineTextOnColor(Color ground) => timelineGroundIsLight(ground)
    ? timelineTextOnLightGroundColor
    : timelineTextOnDarkGroundColor;

/// R26 #44 / R27 #13: ACTION-section blocks whose cel holds NO picture
/// yet read as the paper at LOW OPACITY — the user's ask ("흰색에서 그냥
/// 불투명도 낮추는 느낌… 투명감나게"). Against the dark lane the alpha
/// resolves to a distinctly greyer, see-through paper, which the old
/// near-white 0xFFD7D5D0 never managed. Painting a translucent colour
/// costs the same as an opaque one, so this stays free.
const Color timelineEmptyCelBlockColor = Color(0x6EE9E7E2);

/// The empty-cel look of an arbitrary [paper] — the alpha above, applied to
/// whatever colour the row's block is made of (⑲).
///
/// One statement rather than two: "no picture yet" is a TRANSPARENCY of the
/// paper, so it has to be derived from the paper and not be a second colour
/// that happens to match it.
Color timelineEmptyCelPaperColor(Color paper) =>
    paper.withValues(alpha: timelineEmptyCelBlockColor.a);

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

// ⛔The outline width rule is GONE (2026-08-17, with the outline itself).
// #15 dressed the block text in a white stroke, #1104 took the text's off,
// and the grip bars were its last wearer — until the user called the white
// silhouette out on device ("애초에 통일하기로 했잖아"): every mark on a
// block now reads through [timelineTextOnColor], and nothing wears an
// outline that could need a width.

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
  // A cut block is a PLATE on the rows body, not a chrome surface: with one
  // chrome fill it would have collapsed into the body it sits on and read
  // only by its edge.
  final resting = active ? colorScheme.primaryContainer : AppColors.washUp;
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

/// The effective ground of the strip's PANEL PICTURES (B1 2026-08-17).
///
/// While thumbnails are shown, a grip on the storyboard strip sits on a
/// PICTURE, not on the cut block's plate — and the pictures are composite
/// renders on the canvas's white paper, so a plate-ground grip resolved to
/// the light bar and vanished over them (the device report). The picture's
/// true average would cost a pixel readback per rendered thumbnail; the
/// paper dominates every real board, so the ground is the paper — a
/// CONSTANT, chosen once, on the light side of the crossover, and the
/// ground law turns it into the dark bar.
const Color storyboardPanelPictureGroundColor = Color(0xFFFFFFFF);

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
  Color paper = timelineDrawingHeldColor,
}) {
  // UI-R21 #2: empty cells paint NOTHING — the row-level underlay owns
  // the paper (a surface base plus the active-row wash), so the cell
  // substrate carries no per-row state at all.
  const emptyBaseColor = Colors.transparent;
  final exposureColor = switch (exposureState) {
    TimelineCellExposureState.uncovered ||
    TimelineCellExposureState.markUncovered => emptyBaseColor,
    // ⑲ (user, 2026-08-12): 「블록 모드의 프레임블록은 레이어 색라벨 색을
    // 그대로 따라간다 (…) 그냥 블록의 고정 하얀색을 레이어 색라벨
    // 따라가도록」. START and HELD were two names for one number and stay
    // that way — a run is one sheet of paper, and only its seams differ.
    TimelineCellExposureState.drawingStart ||
    TimelineCellExposureState.held ||
    TimelineCellExposureState.markHeld => paper,
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

/// The ONE corner radius every frame block wears — the timeline's rounded
/// block language (D30 put the storyboard panels on it too, so the strip
/// reads as frame blocks in thumbnail mode).
const Radius timelineBlockCornerRadius = Radius.circular(6);

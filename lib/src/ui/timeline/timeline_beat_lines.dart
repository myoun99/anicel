import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'timeline_cell_style.dart';

/// The frame grid's LINE system, one overlay per grid (UI-R10 #26 →
/// UI-R13 #7 → UI-R18 #2/#8/#10/#12 — the storyboard recipe unified):
/// - BASE per-cell lines: flat faint ink, cadence-THINNED at small zooms
///   (never alpha-faded away) — the grid is always there, over every row
///   and lane;
/// - ROW seams across the cross axis: full-strength hairlines every row,
///   zoom-independent (the storyboard's row borders, generalized);
/// - 6f/24f BEAT lines on top.
///
/// The painter lives in the scroll CONTENT's coordinate space (its size
/// is the full built content), so lines land on absolute frame
/// boundaries.
///
/// ⚠️ It used to say "a handful of `drawLine`s — no windowing needed",
/// and that was not true: the size is the whole content, so the count
/// scales with the timeline's LENGTH rather than with the window. An
/// audit put it at about 3% of the ops a window would remove here, so
/// the code is right to stay as it is — but for a reason it was not
/// giving. A comment that says "cheap" without saying why is how a
/// surface stops being looked at.
/// D8/D32/D38 (2026-08-18): THE grid-line law, whole. This file already
/// owned the INK (R26 #40's "one grid language"); the position and the
/// over-block treatment joined it so no drawer can restate a value:
/// - ink: the three named strengths below, dispatched per boundary;
/// - position: [timelineFrameBoundaryLinePosition] — every drawer lands
///   on boundary + [timelineGridLineSnap], the ruler's own pixel snap
///   (the overlay used to draw unsnapped, which was D8's "미묘하게 다름");
/// - over blocks: [timelineGridLineInkOnGround] — the same line
///   channel-multiplied onto the block's paper (D32: a bright opaque line
///   glowing over blue paper was the report; multiply darkens the paper
///   instead), computed in Dart so the tile bake needs no blend op;
/// - cadence: one function answers inside and outside blocks alike (D38:
///   a zoom that thins the empty-space 1f lines thins the block seams
///   too — same question, same answer).

/// The frame AREA's own leading edge — the hairline that marks where the
/// frames begin, mirroring the rail row's right border (D8, UI-R10 #20's
/// seam law: the splitter gap between them means neither line doubles the
/// other).
///
/// 🚨D8-2 (유저 2026-08-22) — **AND THE RULER WEARS IT TOO.** The user gave
/// this as a standing law, not as one instruction:
///
/// > 「프레임영역 왼쪽 선 좋은데 **룰러도 통일.** 프레임영역은 **기본 뭔가
/// > 바뀌면 룰러랑 통일**임」
///
/// ⇒ ★So it is a WIDGET, not a `BoxDecoration` written out twice. Whoever
/// changes this line changes it once, and the ruler cannot fall behind the
/// rows again — which is exactly how it fell behind this time.
///
/// ⚠️Viewport-STATIC: it marks the AREA, so it must not scroll with the
/// content. Both wearers put it on the widget that owns the viewport, never
/// on the scrolled child.
///
/// ⚠️The border is drawn in the FOREGROUND and takes no layout room, so
/// wrapping a `LayoutBuilder` in it does not change the constraints that
/// builder reads.
class TimelineFrameAreaEdge extends StatelessWidget {
  const TimelineFrameAreaEdge({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: child,
    );
  }
}

/// BASE line — the faint per-cell cadence line.
({Color color, double strokeWidth}) timelineGridBaseLineInk(
  ColorScheme colorScheme,
) => (
  color: colorScheme.outlineVariant.withValues(alpha: timelineBaseGridAlpha),
  strokeWidth: 1.0,
);

/// 6f BEAT line — the sheet convention, zoom-independent.
({Color color, double strokeWidth}) timelineGridSixLineInk(
  ColorScheme colorScheme,
) => (color: colorScheme.outline, strokeWidth: 1.0);

/// SECOND (fps) line — the strongest.
({Color color, double strokeWidth}) timelineGridSecondLineInk() =>
    (color: AppColors.beatLine, strokeWidth: 1.5);

/// ROW SEAM — the grid's CROSS-axis line, between one row and the next.
/// Full strength and zoom-independent (UI-R18 #10/#12: the rows' hairline
/// language extended into the cell area).
///
/// 🚨D43-2 재개 d (유저 2026-08-23): 「**fx행엔 그리드의 가로선 있는데
/// 레이어쪽 프레임쪽엔 없거든?** 그거 통일로 추가해주고」
///
/// ⛔The value used to be spelled out wherever a seam was drawn — an inline
/// tuple inside the overlay, a `BorderSide(outlineVariant, 0.5)` on the fx
/// band, and NOTHING at all on the frame cells rows, which paint an opaque
/// ground straight over the overlay's (D32's z-order). Three spellings, one
/// of them silence. Named here so a seam is one line however it is reached.
({Color color, double strokeWidth}) timelineGridRowSeamInk(
  ColorScheme colorScheme,
) => (color: colorScheme.outlineVariant, strokeWidth: 1.0);

/// The position convention: a boundary line's center sits half a pixel
/// past the boundary — the frame ruler's own snap, now the law's.
const double timelineGridLineSnap = 0.5;

/// Where the line at the boundary STARTING [frameIndex] is drawn, along
/// the frame axis in content coordinates.
double timelineFrameBoundaryLinePosition(
  int frameIndex,
  double frameCellExtent,
) => frameIndex * frameCellExtent + timelineGridLineSnap;

/// The grid line's ink ON a painted ground (a block's paper): the law
/// line channel-multiplied onto the ground, weighted by the line's own
/// alpha — a faint base line darkens the paper faintly, an opaque beat
/// line darkens it fully. Computed here, once, so the substrate tiles
/// bake a plain opaque colour and need no blend mode in the native ops.
Color timelineGridLineInkOnGround(
  ({Color color, double strokeWidth}) ink,
  Color ground,
) {
  final line = ink.color;
  final multiplied = Color.from(
    alpha: 1,
    red: line.r * ground.r,
    green: line.g * ground.g,
    blue: line.b * ground.b,
  );
  return Color.lerp(ground, multiplied, line.a)!;
}

/// 🚨THE GROUND [timelineGridLineInkOnGround] MUST BE HANDED — what the eye
/// actually sees at that pixel, after [painted] has gone down over [under].
///
/// ⛔The law above ends in `lerp(ground, multiplied, ink.a)`, which
/// interpolates the ALPHA as well as the colour. Hand it a TRANSLUCENT
/// colour and the result climbs toward opaque while its rgb stays where the
/// translucent colour was: the line comes out MORE opaque than everything
/// around it, which on a pale wash means a line LIGHTER than its ground.
///
/// 🧪That is not a hypothetical. An unworked block is the paper at 43%, and
/// the cell painter used to pass it straight through: ground L=0.461, line
/// L=0.471 — 유저 2026-08-22, 「블록이 회색일때 그리드선이 흰색」. The 6f and
/// second lines survived only by being dark enough to still read as darker,
/// at about half the strength the law asks for.
///
/// Every surface that paints over the grid overlay resolves through HERE.
/// The run labels already had this rule in their own words (they take a
/// `backdropColor` and resolve the translucent paper against it before
/// choosing an ink) — which is exactly why the user could see that the two
/// laws disagreed: same paper, one composited first and one did not.
Color? timelineGridGroundOver({
  required Color? under,
  required Color? painted,
}) {
  if (painted == null) {
    return under;
  }
  // Opaque paint IS what is seen; nothing under it matters.
  if (painted.a >= 1) {
    return painted;
  }
  // No known ground below (a row lying over the ARTWORK): there is nothing
  // to composite against, so the line stays the law's raw ink, source-over,
  // exactly as the folded row's overlay does.
  if (under == null) {
    return painted.a <= 0 ? null : painted;
  }
  return Color.alphaBlend(painted, under);
}

/// 🚨THE GRID'S GROUND AND CADENCE, PUBLISHED ONCE PER HOST — so a surface
/// that paints over the beat-line overlay cannot draw its own grid without
/// knowing what it is drawing on.
///
/// The overlay sits UNDER the rows (D32): whatever a row paints occludes it,
/// so every opaque or washed row owes the grid a redraw through the law. The
/// hosts genuinely sit on different colours (the timeline and X-sheet on
/// `surfaceContainerHighest`, the storyboard on `surface`, a folded row on
/// the artwork = null), which is why this is inherited rather than guessed.
///
/// ⛔Do not read the ground off `colorScheme` at the point of use. That
/// guess is right three times in four, which is the worst kind of wrong.
class TimelineGridLaw extends InheritedWidget {
  const TimelineGridLaw({
    super.key,
    required this.ground,
    required this.framesPerSecond,
    required super.child,
  });

  /// The host's own Material colour under the overlay; null where the grid
  /// lies over the artwork and there is nothing to multiply against.
  final Color? ground;

  /// The counting fps — which boundaries are SECOND boundaries.
  final int framesPerSecond;

  static TimelineGridLaw? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TimelineGridLaw>();

  @override
  bool updateShouldNotify(TimelineGridLaw oldWidget) =>
      oldWidget.ground != ground ||
      oldWidget.framesPerSecond != framesPerSecond;
}

/// The ink of the grid line at the boundary STARTING frame [frameIndex]
/// — the one grid language shared by the cell grid overlay and the frame
/// ruler (R26 #40: "룰러도 프레임 셀 그리드랑 통일감").
///
/// Null when the base cadence thins this boundary out at the current
/// zoom. 6f boundaries read slightly stronger, second (fps) boundaries
/// strongest — the sheet convention, zoom-independent.
({Color color, double strokeWidth})? timelineFrameBoundaryLineInk({
  required int frameIndex,
  required double frameCellExtent,
  required int framesPerSecond,
  required ColorScheme colorScheme,
}) {
  if (frameIndex <= 0 || frameCellExtent <= 0) {
    return null;
  }
  if (frameIndex % 6 == 0) {
    return framesPerSecond > 0 && frameIndex % framesPerSecond == 0
        ? timelineGridSecondLineInk()
        : timelineGridSixLineInk(colorScheme);
  }
  final cadence = timelineGridLineEveryFrames(frameCellExtent);
  if (frameIndex % cadence != 0) {
    return null;
  }
  return timelineGridBaseLineInk(colorScheme);
}

/// The OUT-OF-CUT wash: everything past the cut's last frame, greyed.
///
/// One rect over the whole grid, in the same content coordinate space the
/// line overlay uses — it used to be blended into every cell, inside the
/// baked substrate tiles, which is what tied those tiles to the cut's
/// LENGTH. A length that moved therefore could not be drawn without
/// re-rastering the row, so the drag showed the committed shading for its
/// whole duration and snapped on release. Lifted out, it costs one
/// `drawRect` and follows the drag for free (user's layering 2026-08-02).
///
/// The blend is the same colour and alpha the per-cell version used, and
/// over an already-painted cell it composites to the same pixels. Block
/// BORDERS differ slightly: they had their own dim ink, and one rect cannot
/// tell a border from its cell — accepted by the user, and the wash reads
/// as one region rather than as a run of separately shaded cells.
class TimelineOutsideCutWashPainter extends CustomPainter {
  const TimelineOutsideCutWashPainter({
    required this.outsideStart,
    required this.colorScheme,
    this.axis = Axis.horizontal,
  });

  /// Where the cut ends, in content pixels along the frame axis.
  final double outsideStart;
  final ColorScheme colorScheme;
  final Axis axis;

  @override
  void paint(Canvas canvas, Size size) {
    final mainExtent = axis == Axis.horizontal ? size.width : size.height;
    if (outsideStart >= mainExtent) {
      return;
    }
    final start = outsideStart < 0 ? 0.0 : outsideStart;
    canvas.drawRect(
      axis == Axis.horizontal
          ? Rect.fromLTWH(start, 0, size.width - start, size.height)
          : Rect.fromLTWH(0, start, size.width, size.height - start),
      Paint()..color = AppColors.washUp.withValues(alpha: 0.54),
    );
  }

  @override
  bool shouldRepaint(covariant TimelineOutsideCutWashPainter oldDelegate) =>
      oldDelegate.outsideStart != outsideStart ||
      oldDelegate.colorScheme != colorScheme ||
      oldDelegate.axis != axis;
}

class TimelineBeatLinesPainter extends CustomPainter {
  TimelineBeatLinesPainter({
    required this.frameCellExtent,
    required this.framesPerSecond,
    required this.colorScheme,
    required this.ground,
    this.axis = Axis.horizontal,
    this.crossCellExtent = 0,
    this.frameStartIndex = 0,
  });

  final double frameCellExtent;
  final int framesPerSecond;
  final ColorScheme colorScheme;

  /// The surface this overlay is painted ON, so its lines take the SAME
  /// treatment the block-interior seams take (유저, 2026-08-21: 「그리드
  /// 오버레이랑 블록 내부 이음매같은게 색이나 생긴게 달라서 통일하고싶다」).
  ///
  /// 🚨The two differed by OPERATION, not by value. Over empty ground the
  /// line was source-over — `lerp(ground, line, line.a)`, which in a dark
  /// theme is LIGHTER than its ground — while over a block the tile
  /// multiplied: `lerp(paper, line×paper, line.a)`, always DARKER. Same
  /// ink, same position, same cadence, two composites, so one grid changed
  /// character wherever paper began. The ground here puts both through
  /// [timelineGridLineInkOnGround].
  ///
  /// ⛔Passed IN rather than read off [colorScheme]: the hosts genuinely
  /// sit on different surfaces — the timeline panel and the X-sheet on
  /// `surfaceContainerHighest`, the storyboard on `surface`. Guessing one
  /// here would have been right three times out of four, which is the
  /// worst kind of wrong.
  ///
  /// ⚠️Null = "the ground is not a single known colour". The folded row's
  /// overlay lies over the ARTWORK at 70%, so there is nothing to multiply
  /// against and its lines stay source-over.
  final Color? ground;

  /// The FRAME axis' direction: horizontal (timeline, storyboard) draws
  /// vertical lines; vertical (X-sheet) draws horizontal ones.
  final Axis axis;

  /// The uniform row height (timeline) / column width (X-sheet) for the
  /// cross-axis ROW seam lines; 0 skips them (hosts that draw their own).
  final double crossCellExtent;

  /// The ABSOLUTE frame at this canvas' origin — so a windowed surface (a
  /// single lane band inside a virtualised row) draws the boundaries that
  /// actually fall in its window rather than counting from its own left
  /// edge. 0 is the whole-panel overlay and changes nothing.
  final int frameStartIndex;

  /// [ink] as it must land on this overlay's ground — the block-interior
  /// treatment, applied to the empty-space lines too.
  Color _inkOnGround(({Color color, double strokeWidth}) ink) {
    final ground = this.ground;
    return ground == null
        ? ink.color
        : timelineGridLineInkOnGround(ink, ground);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (frameCellExtent <= 0) {
      return;
    }
    final mainExtent = axis == Axis.horizontal ? size.width : size.height;
    final crossExtent = axis == Axis.horizontal ? size.height : size.width;

    void mainAxisLine(double position, Paint paint) {
      if (axis == Axis.horizontal) {
        canvas.drawLine(
          Offset(position, 0),
          Offset(position, crossExtent),
          paint,
        );
      } else {
        canvas.drawLine(
          Offset(0, position),
          Offset(crossExtent, position),
          paint,
        );
      }
    }

    // BASE grid: flat faint, cadence-thinned (UI-R18 #8 — the storyboard
    // look; beat frames skip, the beat pass draws them stronger). The
    // ink comes from the LAW's named functions and the position from its
    // snap — the stride loops below are the law's own cadence hoisted,
    // so no per-boundary allocation happens on this content-length walk.
    // The first boundary of period [period] at or after the window start —
    // the hoisted form of "which absolute frames does this canvas show".
    int firstBoundary(int period) => frameStartIndex <= 0
        ? period
        : ((frameStartIndex + period - 1) ~/ period) * period;
    double positionOf(int frame) => timelineFrameBoundaryLinePosition(
      frame - frameStartIndex,
      frameCellExtent,
    );

    final baseInk = timelineGridBaseLineInk(colorScheme);
    final basePaint = Paint()
      ..color = _inkOnGround(baseInk)
      ..strokeWidth = baseInk.strokeWidth;
    final cadence = timelineGridLineEveryFrames(frameCellExtent);
    for (
      var frame = firstBoundary(cadence);
      (frame - frameStartIndex) * frameCellExtent <= mainExtent;
      frame += cadence
    ) {
      if (frame % 6 == 0) {
        continue;
      }
      mainAxisLine(positionOf(frame), basePaint);
    }

    // ROW seams (UI-R18 #10/#12): full-strength, zoom-independent — the
    // rows' own hairline language extended into the cell area.
    if (crossCellExtent > 0) {
      final seamInk = timelineGridRowSeamInk(colorScheme);
      final seamPaint = Paint()
        ..color = _inkOnGround(seamInk)
        ..strokeWidth = seamInk.strokeWidth;
      for (
        var seam = crossCellExtent;
        seam < crossExtent;
        seam += crossCellExtent
      ) {
        if (axis == Axis.horizontal) {
          canvas.drawLine(Offset(0, seam), Offset(mainExtent, seam), seamPaint);
        } else {
          canvas.drawLine(Offset(seam, 0), Offset(seam, mainExtent), seamPaint);
        }
      }
    }

    final sixInk = timelineGridSixLineInk(colorScheme);
    final sixPaint = Paint()
      ..color = _inkOnGround(sixInk)
      ..strokeWidth = sixInk.strokeWidth;
    final secondInk = timelineGridSecondLineInk();
    final secondPaint = Paint()
      ..color = _inkOnGround(secondInk)
      ..strokeWidth = secondInk.strokeWidth;
    // 6f is the sheet convention regardless of fps.
    const beatPeriod = 6;
    for (
      var frame = firstBoundary(beatPeriod);
      (frame - frameStartIndex) * frameCellExtent <= mainExtent;
      frame += beatPeriod
    ) {
      final paint = framesPerSecond > 0 && frame % framesPerSecond == 0
          ? secondPaint
          : sixPaint;
      mainAxisLine(positionOf(frame), paint);
    }
  }

  @override
  bool shouldRepaint(covariant TimelineBeatLinesPainter oldDelegate) =>
      oldDelegate.frameCellExtent != frameCellExtent ||
      oldDelegate.framesPerSecond != framesPerSecond ||
      oldDelegate.colorScheme != colorScheme ||
      oldDelegate.ground != ground ||
      oldDelegate.axis != axis ||
      oldDelegate.frameStartIndex != frameStartIndex ||
      oldDelegate.crossCellExtent != crossCellExtent;
}

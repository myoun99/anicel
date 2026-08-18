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
      Paint()
        ..color = AppColors.washUp.withValues(alpha: 0.54),
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
    this.axis = Axis.horizontal,
    this.crossCellExtent = 0,
  });

  final double frameCellExtent;
  final int framesPerSecond;
  final ColorScheme colorScheme;

  /// The FRAME axis' direction: horizontal (timeline, storyboard) draws
  /// vertical lines; vertical (X-sheet) draws horizontal ones.
  final Axis axis;

  /// The uniform row height (timeline) / column width (X-sheet) for the
  /// cross-axis ROW seam lines; 0 skips them (hosts that draw their own).
  final double crossCellExtent;

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
    final baseInk = timelineGridBaseLineInk(colorScheme);
    final basePaint = Paint()
      ..color = baseInk.color
      ..strokeWidth = baseInk.strokeWidth;
    final cadence = timelineGridLineEveryFrames(frameCellExtent);
    for (
      var frame = cadence;
      frame * frameCellExtent <= mainExtent;
      frame += cadence
    ) {
      if (frame % 6 == 0) {
        continue;
      }
      mainAxisLine(
        timelineFrameBoundaryLinePosition(frame, frameCellExtent),
        basePaint,
      );
    }

    // ROW seams (UI-R18 #10/#12): full-strength, zoom-independent — the
    // rows' own hairline language extended into the cell area.
    if (crossCellExtent > 0) {
      final seamPaint = Paint()
        ..color = colorScheme.outlineVariant
        ..strokeWidth = 1;
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
      ..color = sixInk.color
      ..strokeWidth = sixInk.strokeWidth;
    final secondInk = timelineGridSecondLineInk();
    final secondPaint = Paint()
      ..color = secondInk.color
      ..strokeWidth = secondInk.strokeWidth;
    // 6f is the sheet convention regardless of fps.
    const beatPeriod = 6;
    for (
      var frame = beatPeriod;
      frame * frameCellExtent <= mainExtent;
      frame += beatPeriod
    ) {
      final paint = framesPerSecond > 0 && frame % framesPerSecond == 0
          ? secondPaint
          : sixPaint;
      mainAxisLine(
        timelineFrameBoundaryLinePosition(frame, frameCellExtent),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant TimelineBeatLinesPainter oldDelegate) =>
      oldDelegate.frameCellExtent != frameCellExtent ||
      oldDelegate.framesPerSecond != framesPerSecond ||
      oldDelegate.colorScheme != colorScheme ||
      oldDelegate.axis != axis ||
      oldDelegate.crossCellExtent != crossCellExtent;
}

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
/// boundaries; painting is a handful of `drawLine`s — no windowing
/// needed.
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
        ? (color: AppColors.beatLine, strokeWidth: 1.5)
        : (color: colorScheme.outline, strokeWidth: 1.0);
  }
  final cadence = timelineGridLineEveryFrames(frameCellExtent);
  if (frameIndex % cadence != 0) {
    return null;
  }
  return (
    color: colorScheme.outlineVariant.withValues(alpha: timelineBaseGridAlpha),
    strokeWidth: 1.0,
  );
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
    // look; beat frames skip, the beat pass draws them stronger).
    final basePaint = Paint()
      ..color = colorScheme.outlineVariant.withValues(
        alpha: timelineBaseGridAlpha,
      )
      ..strokeWidth = 1;
    final cadence = timelineGridLineEveryFrames(frameCellExtent);
    for (
      var frame = cadence;
      frame * frameCellExtent <= mainExtent;
      frame += cadence
    ) {
      if (frame % 6 == 0) {
        continue;
      }
      mainAxisLine(frame * frameCellExtent, basePaint);
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

    final sixPaint = Paint()
      ..color = colorScheme.outline
      ..strokeWidth = 1;
    final secondPaint = Paint()
      ..color = AppColors.beatLine
      ..strokeWidth = 1.5;
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
      mainAxisLine(frame * frameCellExtent, paint);
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

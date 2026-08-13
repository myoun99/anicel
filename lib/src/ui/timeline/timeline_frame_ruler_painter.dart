import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsProperties;

import 'timeline_beat_lines.dart';
import 'timeline_cell_style.dart';
import 'timeline_frame_window.dart';
import 'timeline_glyph_cache.dart';
import 'timeline_grid_metrics.dart';

/// The ruler's top-line SECOND mark at [frameIndex], or '' off a boundary.
///
/// 🚨COUNTED FROM 0, because a ruler mark is a POSITION on the time axis and
/// what has elapsed at the first frame is nothing (유저 2026-08-13: 「초
/// 표시하는곳. 1부터 시작하는데 그게아니라 0부터 시작하도록」). At 24fps the
/// mark on frame 25 is where exactly one second has passed, so `1` belongs
/// there and `0` belongs at the head.
///
/// ⛔This is NOT the `s+ff` notation of a cut's LENGTH
/// ([ProjectFrameRate]'s formatter, the conte sheet's totals). A length is a
/// count and 24 frames is `1+0`; the two look alike and answer different
/// questions, so they stay separate functions.
///
/// One function because the timeline, the storyboard and the x-sheet all ask
/// it: the expression used to be written out twice, letter for letter, and
/// fixing one would have left the sheet counting from 1.
String timelineRulerSecondsLabel({
  required int frameIndex,
  required int framesPerSecond,
}) {
  final safeFps = framesPerSecond > 0 ? framesPerSecond : 24;
  return frameIndex % safeFps == 0 ? '${frameIndex ~/ safeFps}' : '';
}

/// The resolved per-header model — THE probe surface for ruler tests
/// (labels, states and colors live here, not in widget trees), the ruler
/// counterpart of the cells painter's model (UI-R9 #12b → UI-R13 #1).
class TimelineRulerHeaderModel {
  const TimelineRulerHeaderModel({
    required this.frameIndex,
    required this.label,
    required this.secondsLabel,
    required this.selected,
    required this.outsidePlaybackRange,
    required this.background,
  });

  final int frameIndex;

  /// The bottom-line number ('' when the cell is unlabeled at this zoom).
  final String label;

  /// The top-line second index ('' off second boundaries).
  final String secondsLabel;

  final bool selected;
  final bool outsidePlaybackRange;
  final Color background;
}

/// The frame ruler strip as ONE CustomPainter (UI-R13 #1 — the same
/// painterization the drawing rows got in UI-R9 #12b): header cell
/// backgrounds/borders, the two-line labels (UI-R10 #27) and the cached
/// green strip paint in a single pass; the per-frame header widgets are
/// gone. Shared by the timeline header and the storyboard ruler (which
/// already share [TimelineFrameHeaderRow]); scrubbing stays on the
/// viewport-level listeners (G8) — the strip itself is passive.
class TimelineFrameRulerPainter extends CustomPainter {
  TimelineFrameRulerPainter({
    required this.frameStartIndex,
    required this.frameEndIndexExclusive,
    required this.currentFrameIndex,
    required this.playbackFrameCount,
    required this.leadingFrameSpacerWidth,
    required this.metrics,
    required this.colorScheme,
    this.framesPerSecond = 24,
    this.showSeconds = false,
    this.windowBucket,
    this.viewportMainExtent = 0,
  }) : super(repaint: windowBucket);

  final int frameStartIndex;
  final int frameEndIndexExclusive;
  final int currentFrameIndex;
  final int playbackFrameCount;
  final double leadingFrameSpacerWidth;
  final TimelineGridMetrics metrics;
  final ColorScheme colorScheme;
  final int framesPerSecond;
  final bool showSeconds;

  /// PRO-TIMELINE scrolling (UI-R15→R16): with these set the strip
  /// windows ITSELF off the quantized bucket (repaint once per span
  /// crossing, pure translation between) — the header row builds once
  /// for the full bounds. Null keeps the classic pre-windowed contract.
  final ValueListenable<int>? windowBucket;
  final double viewportMainExtent;

  /// The header window paint() actually draws (probe surface).
  ({int startIndex, int endIndexExclusive}) visibleHeaderWindow() {
    final bucket = windowBucket;
    if (bucket == null ||
        viewportMainExtent <= 0 ||
        metrics.frameCellWidth <= 0) {
      return (
        startIndex: frameStartIndex,
        endIndexExclusive: frameEndIndexExclusive,
      );
    }
    final window = timelineFrameWindowFor(
      bucket: bucket.value,
      cellExtent: metrics.frameCellWidth,
      viewportExtent: viewportMainExtent,
    );
    return (
      startIndex: math.max(frameStartIndex, window.startIndex),
      endIndexExclusive: math.min(
        frameEndIndexExclusive,
        window.endIndexExclusive,
      ),
    );
  }

  /// The header cell's rect in the strip's local coordinates (the probe
  /// geometry tests and taps share).
  Rect headerRectFor(int frameIndex) => Rect.fromLTWH(
    leadingFrameSpacerWidth +
        (frameIndex - frameStartIndex) * metrics.frameCellWidth,
    0,
    metrics.frameCellWidth,
    metrics.layerRowHeight,
  );

  String _frameNumberLabel(int frameIndex) {
    if (!showSeconds) {
      return '${frameIndex + 1}';
    }
    final safeFps = framesPerSecond > 0 ? framesPerSecond : 24;
    return '${frameIndex % safeFps + 1}';
  }

  /// The resolved per-header model — the probe surface.
  TimelineRulerHeaderModel headerModelAt(int frameIndex) {
    final selected = frameIndex == currentFrameIndex;
    final outside = frameIndex >= playbackFrameCount;
    final labeled = frameIndex % metrics.frameLabelEveryFrames == 0;
    final safeFps = framesPerSecond > 0 ? framesPerSecond : 24;
    return TimelineRulerHeaderModel(
      frameIndex: frameIndex,
      label: labeled ? _frameNumberLabel(frameIndex) : '',
      secondsLabel: timelineRulerSecondsLabel(
        frameIndex: frameIndex,
        framesPerSecond: safeFps,
      ),
      selected: selected,
      outsidePlaybackRange: outside,
      // No past-playback graying on the RULER (UI-R18 #9): small zooms
      // made the strip read broken from the right; the cut-end boundary
      // line marks the end, the BODY cells keep their own dim wash.
      background: selected
          ? Color.alphaBlend(
              timelineSelectedFrameBorderColor.withValues(alpha: 0.12),
              colorScheme.surface,
            )
          : colorScheme.surface,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final labelEveryFrames = metrics.frameLabelEveryFrames;
    final fillPaint = Paint();
    final linePaint = Paint()..strokeWidth = 1;

    // Self-windowing (UI-R15): only the headers under the live viewport
    // record — a scroll is a repaint of this thin pass, never a rebuild.
    final window = visibleHeaderWindow();

    // PASS 1 — paper. Painting every background BEFORE any label is what
    // keeps a narrow cell's label alive: the old single pass let the next
    // cell's fill erase the half that overflowed (R26 #39, "텍스트 절반이
    // 사라짐"). The cached-range strip is NOT here — it moved to
    // [TimelineRulerCursorOverlay] with the cursor tint, because its
    // truth is derived state that no gate can compare.
    for (
      var frameIndex = window.startIndex;
      frameIndex < window.endIndexExclusive;
      frameIndex += 1
    ) {
      final model = headerModelAt(frameIndex);
      canvas.drawRect(
        headerRectFor(frameIndex),
        fillPaint..color = model.background,
      );
    }

    // PASS 2 — the SAME grid the cells use (R26 #40): base cadence lines,
    // 6f stronger, second boundaries strongest.
    for (
      var frameIndex = window.startIndex;
      frameIndex < window.endIndexExclusive;
      frameIndex += 1
    ) {
      final ink = timelineFrameBoundaryLineInk(
        frameIndex: frameIndex,
        frameCellExtent: metrics.frameCellWidth,
        framesPerSecond: framesPerSecond,
        colorScheme: colorScheme,
      );
      if (ink == null) {
        continue;
      }
      final rect = headerRectFor(frameIndex);
      canvas.drawLine(
        Offset(rect.left + 0.5, rect.top),
        Offset(rect.left + 0.5, rect.bottom),
        linePaint
          ..color = ink.color
          ..strokeWidth = ink.strokeWidth,
      );
    }
    linePaint.strokeWidth = 1;

    // PASS 3 — labels last, so nothing can paint over them.
    for (
      var frameIndex = window.startIndex;
      frameIndex < window.endIndexExclusive;
      frameIndex += 1
    ) {
      final model = headerModelAt(frameIndex);
      final rect = headerRectFor(frameIndex);
      // Bottom line: in-cell centered when every cell labels itself, the
      // every-Nth overlay style (left-anchored) otherwise (UI-R10 #27).
      if (model.label.isNotEmpty) {
        // Labels keep one ink whatever the playhead range (UI-R18 #9),
        // and SHRINK rather than vanish at deep zoom-outs (R26 #38).
        final style = labelEveryFrames == 1
            ? TextStyle(
                fontSize: timelineFittedGlyphFontSize(
                  11,
                  metrics.frameCellWidth,
                  crossExtent: metrics.layerRowHeight,
                ),
                color: colorScheme.onSurface,
              )
            : TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant);
        final painter = _label(model.label, style);
        if (labelEveryFrames == 1) {
          painter.paint(
            canvas,
            Offset(
              rect.center.dx - painter.width / 2,
              rect.bottom - painter.height - 1,
            ),
          );
        } else {
          painter.paint(
            canvas,
            Offset(rect.left + 2, rect.bottom - painter.height - 1),
          );
        }
      }

      // Top line: the second index on fps boundaries (UI-R10 #27).
      if (model.secondsLabel.isNotEmpty) {
        final painter = _label(
          model.secondsLabel,
          TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurfaceVariant,
          ),
        );
        painter.paint(canvas, Offset(rect.left + 2, rect.top + 1));
      }
    }

    // The strip's structural BASELINE (the ruler/body divider) — full
    // strength, once, whatever the zoom; per-cell borders above stay
    // faint (UI-R14 #4).
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      linePaint..color = colorScheme.outlineVariant,
    );

    // And the strip's TOP edge, drawn the same way. The ruler is the grid's
    // first row, and the command bar above it is now the SAME chrome fill,
    // so the seam between the panel's toolbar and its content has to be a
    // line — without it the row of frame numbers reads as the bottom half of
    // the toolbar. It lands collinear with the legend header's own top
    // border beside it, so the grid keeps one continuous top edge.
    canvas.drawLine(
      const Offset(0, 0.5),
      Offset(size.width, 0.5),
      linePaint..color = colorScheme.outlineVariant,
    );
  }

  // Labels come from the shared laid-out-TextPainter cache (UI-R16):
  // fresh layout per label per repaint was the priciest slice of a
  // scroll-time repaint in debug.
  TextPainter _label(String text, TextStyle style) =>
      timelineGlyphPainter(text, style);

  @override
  bool shouldRepaint(covariant TimelineFrameRulerPainter oldDelegate) =>
      oldDelegate.frameStartIndex != frameStartIndex ||
      oldDelegate.frameEndIndexExclusive != frameEndIndexExclusive ||
      oldDelegate.currentFrameIndex != currentFrameIndex ||
      oldDelegate.playbackFrameCount != playbackFrameCount ||
      oldDelegate.leadingFrameSpacerWidth != leadingFrameSpacerWidth ||
      oldDelegate.metrics != metrics ||
      oldDelegate.framesPerSecond != framesPerSecond ||
      oldDelegate.showSeconds != showSeconds ||
      !identical(oldDelegate.windowBucket, windowBucket) ||
      oldDelegate.viewportMainExtent != viewportMainExtent ||
      // Value-compared, never `identical`: Theme.of(context).colorScheme
      // hands back a fresh instance every build (AnimatedTheme), so an
      // identity check re-recorded this whole strip on every rebuild.
      oldDelegate.colorScheme != colorScheme;

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
    // One node per labeled header (the old per-cell widgets' surface),
    // windowed with the paint pass.
    final nodes = <CustomPainterSemantics>[];
    final window = visibleHeaderWindow();
    for (
      var frameIndex = window.startIndex;
      frameIndex < window.endIndexExclusive;
      frameIndex += 1
    ) {
      final model = headerModelAt(frameIndex);
      if (model.label.isEmpty) {
        continue;
      }
      nodes.add(
        CustomPainterSemantics(
          rect: headerRectFor(frameIndex),
          properties: SemanticsProperties(
            label: 'frame ${frameIndex + 1}',
            textDirection: TextDirection.ltr,
          ),
        ),
      );
    }
    return nodes;
  };
}

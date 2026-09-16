import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import 'timeline_frame_coordinate_policy.dart' show frameRangeVisibleWidth;
import 'timeline_frame_ruler_painter.dart';
import 'timeline_ruler_playhead_writing.dart';
import 'timeline_grid_metrics.dart';

/// The frame ruler's header strip (UI-R10 #27, CSP/OpenToonz style): TWO
/// text lines — SECONDS on top (a plain second index at each second
/// boundary, nothing else), frame numbers below. The seconds display
/// toggle changes the BOTTOM line only: seconds mode repeats 1..fps per
/// second, frame mode counts absolute frame numbers.
///
/// PAINTERIZED (UI-R13 #1, the drawing rows' UI-R9 #12b treatment): the
/// whole strip is one CustomPaint — per-frame header widgets are gone,
/// so zoom steps and window shifts rebuild nothing here. Tests probe
/// [TimelineRulerScale.modelAt] / `cellRectFor` through
/// the 'timeline-frame-ruler-paint' key; selection stays on the
/// viewport-level scrub listeners (G8 — the strip is passive, and
/// [onSelectFrame] is accepted only for call-site stability).
class TimelineFrameHeaderRow extends StatelessWidget {
  const TimelineFrameHeaderRow({
    super.key,
    required this.frameStartIndex,
    required this.frameEndIndexExclusive,
    required this.currentFrameIndex,
    required this.playbackFrameCount,
    required this.leadingFrameSpacerWidth,
    required this.trailingFrameSpacerWidth,
    required this.metrics,
    required this.onSelectFrame,
    this.framesPerSecond = 24,
    this.showSeconds = false,
    this.windowBucket,
    this.viewportMainExtent = 0,
    this.playhead,
  });

  /// PRO-TIMELINE scrolling (UI-R15→R16): with these set the painter
  /// windows itself off the quantized bucket — pass the FULL frame
  /// bounds; repaints land once per span crossing.
  final ValueListenable<int>? windowBucket;
  final double viewportMainExtent;

  final int frameStartIndex;
  final int frameEndIndexExclusive;
  final int currentFrameIndex;
  final int playbackFrameCount;
  final double leadingFrameSpacerWidth;
  final double trailingFrameSpacerWidth;
  final TimelineGridMetrics metrics;

  /// Unused since G8 (the viewport-level scrub listener owns selection);
  /// kept so the hosts' call sites stay stable.
  final ValueChanged<int> onSelectFrame;

  /// The project fps — the seconds line ticks on its boundaries.
  final int framesPerSecond;

  /// Seconds display mode: the bottom line repeats 1..fps per second
  /// instead of counting absolute frames.
  final bool showSeconds;

  /// The playhead the strip writes its own pair at (I-16), on a layer of
  /// its own above the strip — a null VALUE writes none; a strip without
  /// one (null) never mounts the writing.
  final ValueListenable<int?>? playhead;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final width =
        leadingFrameSpacerWidth +
        frameRangeVisibleWidth(
          startFrameIndex: frameStartIndex,
          endFrameIndexExclusive: frameEndIndexExclusive,
          frameCellWidth: metrics.frameCellWidth,
        ) +
        trailingFrameSpacerWidth;
    final scale = TimelineRulerScale(
      axis: Axis.horizontal,
      frameStartIndex: frameStartIndex,
      frameEndIndexExclusive: frameEndIndexExclusive,
      currentFrameIndex: currentFrameIndex,
      playbackFrameCount: playbackFrameCount,
      leadingFrameSpacer: leadingFrameSpacerWidth,
      crossExtent: metrics.layerRowHeight,
      metrics: metrics,
      colorScheme: colorScheme,
      numberType: TimelineFrameRulerPainter.numberType,
      framesPerSecond: framesPerSecond,
      showSeconds: showSeconds,
      windowBucket: windowBucket,
      viewportMainExtent: viewportMainExtent,
    );
    return SizedBox(
      width: width,
      height: metrics.layerRowHeight,
      child: timelineRulerStripWithWriting(
        strip: CustomPaint(
          key: const ValueKey<String>('timeline-frame-ruler-paint'),
          size: Size(width, metrics.layerRowHeight),
          painter: TimelineFrameRulerPainter(scale: scale),
        ),
        writingKey: const ValueKey<String>('timeline-ruler-playhead-writing'),
        playhead: playhead,
        writing: (held) => TimelineRulerPlayheadWritingPainter(
          scale: scale,
          playhead: held,
          layout: TimelineFrameRulerPainter.glyphsAt,
        ),
      ),
    );
  }
}

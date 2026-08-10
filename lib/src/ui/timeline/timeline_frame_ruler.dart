import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/cut_id.dart';
import 'timeline_cut_end_handle.dart';
import 'timeline_drag_preview.dart';
import 'timeline_frame_header_row.dart';
import 'timeline_frame_range_policy.dart';
import 'timeline_grid_metrics.dart';
import 'timeline_ruler_cut_end_boundary.dart';
import 'timeline_ruler_norishiro_boundary.dart';

class TimelineFrameRuler extends StatelessWidget {
  const TimelineFrameRuler({
    super.key = const ValueKey<String>('timeline-frame-ruler'),
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
    this.dragPreview,
    this.previewCutId,
    this.drawnFrameCount,
    this.noriShiroLabel = '',
    this.axis = Axis.horizontal,
  });

  final int frameStartIndex;
  final int frameEndIndexExclusive;
  final int currentFrameIndex;
  final int playbackFrameCount;
  final double leadingFrameSpacerWidth;
  final double trailingFrameSpacerWidth;
  final TimelineGridMetrics metrics;
  final ValueChanged<int> onSelectFrame;
  final int framesPerSecond;
  final bool showSeconds;
  /// PRO-TIMELINE scrolling (UI-R15→R16): the strip windows itself off
  /// the quantized bucket — pass the full bounds, repaint per crossing.
  final ValueListenable<int>? windowBucket;
  final double viewportMainExtent;

  /// End-line live follow (UI-R18 #14): while a trim drag targets
  /// [previewCutId], the ruler's boundary line rides the previewed
  /// duration so it never splits from the body's line. Null = static.
  final ValueListenable<TimelineDragPreview?>? dragPreview;
  final CutId? previewCutId;

  /// How many frames the cut is DRAWN for — its 尺 plus the のりしろ a
  /// transition span crossing one of its boundaries asks for. Null (or equal
  /// to [playbackFrameCount]) draws no handle at all, which is every cut
  /// nothing crosses.
  final int? drawnFrameCount;

  /// The word spelled across the handle. Empty keeps the line alone.
  final String noriShiroLabel;

  /// The frame axis direction — horizontal for the timeline ruler, vertical
  /// for the X-sheet's frame-number rail.
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final dragPreview = this.dragPreview;
    return Stack(
      children: [
        TimelineFrameHeaderRow(
          frameStartIndex: frameStartIndex,
          frameEndIndexExclusive: frameEndIndexExclusive,
          currentFrameIndex: currentFrameIndex,
          playbackFrameCount: playbackFrameCount,
          leadingFrameSpacerWidth: leadingFrameSpacerWidth,
          trailingFrameSpacerWidth: trailingFrameSpacerWidth,
          metrics: metrics,
          onSelectFrame: onSelectFrame,
          framesPerSecond: framesPerSecond,
          showSeconds: showSeconds,
          windowBucket: windowBucket,
          viewportMainExtent: viewportMainExtent,
        ),
        // The のりしろ boundary UNDER the red line: it marks how much is
        // DRAWN, which is a length, while the red line marks where the cut
        // ends. Both, so the two questions stay two answers.
        //
        // The handle is a LENGTH past the boundary, so it RIDES a live trim
        // rather than standing still — `timelineDrawnEndPreviewFrameCount` is
        // the one function the wash edge and the body's line read too, which is
        // what keeps the three from splitting apart mid-drag.
        if (dragPreview != null && previewCutId != null)
          ValueListenableBuilder<TimelineDragPreview?>(
            valueListenable: dragPreview,
            builder: (context, preview, _) => TimelineRulerNoriShiroBoundary(
              cutEnd: timelineCutEndBoundaryX(
                playbackFrameCount: timelineCutEndPreviewFrameCount(
                  preview: preview,
                  cutId: previewCutId,
                  playbackFrameCount: playbackFrameCount,
                ),
                metrics: metrics,
              ),
              drawnEnd: timelineCutEndBoundaryX(
                playbackFrameCount: timelineDrawnEndPreviewFrameCount(
                  preview: preview,
                  cutId: previewCutId,
                  playbackFrameCount: playbackFrameCount,
                  drawnFrameCount: drawnFrameCount,
                ),
                metrics: metrics,
              ),
              label: noriShiroLabel,
              axis: axis,
            ),
          )
        else
          TimelineRulerNoriShiroBoundary(
            cutEnd: timelineCutEndBoundaryX(
              playbackFrameCount: playbackFrameCount,
              metrics: metrics,
            ),
            drawnEnd: timelineCutEndBoundaryX(
              playbackFrameCount: drawnFrameCount ?? playbackFrameCount,
              metrics: metrics,
            ),
            label: noriShiroLabel,
            axis: axis,
          ),
        if (dragPreview != null && previewCutId != null)
          ValueListenableBuilder<TimelineDragPreview?>(
            valueListenable: dragPreview,
            builder: (context, preview, _) => TimelineRulerCutEndBoundary(
              left: timelineCutEndBoundaryX(
                playbackFrameCount: timelineCutEndPreviewFrameCount(
                  preview: preview,
                  cutId: previewCutId,
                  playbackFrameCount: playbackFrameCount,
                ),
                metrics: metrics,
              ),
            ),
          )
        else
          TimelineRulerCutEndBoundary(
            left: timelineCutEndBoundaryX(
              playbackFrameCount: playbackFrameCount,
              metrics: metrics,
            ),
          ),
      ],
    );
  }
}

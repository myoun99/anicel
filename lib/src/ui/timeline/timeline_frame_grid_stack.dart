import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import 'timeline_beat_lines.dart';
import 'timeline_body_cut_end_boundary.dart';
import 'timeline_cut_end_handle.dart';
import 'timeline_drag_preview.dart';

class TimelineFrameGridStack extends StatelessWidget {
  const TimelineFrameGridStack({
    super.key,
    required this.rowsBody,
    required this.cutEndBoundaryLeft,
    required this.showPlayhead,
    required this.playheadWidth,
    required this.playhead,
    this.beatLines,
    this.cutEndDrag,
    this.dragPreview,
    this.frameCellExtent = 0,
    this.playbackFrameCount = 0,
  });

  final Widget rowsBody;
  final double cutEndBoundaryLeft;
  final bool showPlayhead;
  final double playheadWidth;
  final Widget playhead;

  /// The 6f/24f beat-line overlay (UI-R13 #7): spans EVERY row — SE,
  /// camera, lanes — over the cells, under the cursor layer.
  final Widget? beatLines;

  /// End-line drag hooks (UI-R18 #14): with these set (plus
  /// [frameCellExtent]/[playbackFrameCount]) the boundary grows a grip
  /// that end-trims the active cut, and the LINE follows the live trim
  /// preview through [dragPreview]; null keeps the static line.
  final TimelineCutEndDragCallbacks? cutEndDrag;
  final ValueListenable<TimelineDragPreview?>? dragPreview;
  final double frameCellExtent;
  final int playbackFrameCount;

  @override
  Widget build(BuildContext context) {
    final cutEndDrag = this.cutEndDrag;
    final dragPreview = this.dragPreview;
    return Stack(
      children: [
        rowsBody,
        if (beatLines != null)
          Positioned.fill(child: IgnorePointer(child: beatLines)),
        if (showPlayhead)
          Positioned(
            left: 0,
            top: 0,
            width: playheadWidth,
            child: RepaintBoundary(child: playhead),
          ),
        // The out-of-cut wash and the cut-end line are the TOP layers (the
        // user's layer order 2026-08-02): where the film stops is stated over
        // everything, cursor and selection included. The wash being its own
        // layer at all is what lets a cut-length drag repaint one rect
        // instead of re-baking every row's tiles.
        if (frameCellExtent > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: dragPreview == null || cutEndDrag == null
                    ? CustomPaint(
                        painter: TimelineOutsideCutWashPainter(
                          outsideStart: playbackFrameCount * frameCellExtent,
                          colorScheme: Theme.of(context).colorScheme,
                        ),
                      )
                    : ValueListenableBuilder<TimelineDragPreview?>(
                        valueListenable: dragPreview,
                        builder: (context, preview, _) => CustomPaint(
                          painter: TimelineOutsideCutWashPainter(
                            outsideStart:
                                timelineCutEndPreviewFrameCount(
                                  preview: preview,
                                  cutId: cutEndDrag.cutId,
                                  playbackFrameCount: playbackFrameCount,
                                ) *
                                frameCellExtent,
                            colorScheme: Theme.of(context).colorScheme,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        if (cutEndDrag != null && dragPreview != null && frameCellExtent > 0)
          ValueListenableBuilder<TimelineDragPreview?>(
            valueListenable: dragPreview,
            builder: (context, preview, _) => TimelineBodyCutEndBoundary(
              left:
                  timelineCutEndPreviewFrameCount(
                    preview: preview,
                    cutId: cutEndDrag.cutId,
                    playbackFrameCount: playbackFrameCount,
                  ) *
                  frameCellExtent,
            ),
          )
        else
          TimelineBodyCutEndBoundary(left: cutEndBoundaryLeft),
        if (cutEndDrag != null && frameCellExtent > 0)
          TimelineCutEndDragHandle(
            cellExtent: frameCellExtent,
            playbackFrameCount: playbackFrameCount,
            callbacks: cutEndDrag,
            dragPreview: dragPreview,
          ),
      ],
    );
  }
}

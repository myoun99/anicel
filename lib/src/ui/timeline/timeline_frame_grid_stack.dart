import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import 'timeline_beat_lines.dart';
import 'timeline_body_cut_end_boundary.dart';
import 'timeline_body_norishiro_boundary.dart';
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
    this.drawnFrameCount,
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

  /// How many frames the cut is DRAWN for — its 尺 plus the のりしろ a
  /// transition span crossing one of its boundaries asks for. Null (or equal to
  /// [playbackFrameCount]) is every cut nothing crosses: no blue line, and the
  /// wash starts at the cut end exactly as it always did.
  final int? drawnFrameCount;

  /// Where the DRAWN end sits in content pixels, following a live trim so the
  /// blue line and the wash edge never split from the red line mid-drag.
  double _drawnEnd(TimelineDragPreview? preview) =>
      timelineDrawnEndPreviewFrameCount(
        preview: preview,
        cutId: cutEndDrag?.cutId,
        playbackFrameCount: playbackFrameCount,
        drawnFrameCount: drawnFrameCount,
      ) *
      frameCellExtent;

  @override
  Widget build(BuildContext context) {
    final cutEndDrag = this.cutEndDrag;
    final dragPreview = this.dragPreview;
    return Stack(
      children: [
        // D32 (2026-08-18): the line overlay sits UNDER the rows now — an
        // opaque beat line glowing over a blue paper block was the
        // report. Blocks occlude the empty-space lines and draw their own
        // interior seams through the same law (heldSeamLineFor: identical
        // cadence and snap, ink multiplied onto the paper), so the grid
        // reads as one line running through paper and dark ground alike.
        // This is also the z-order the storyboard always had — three
        // panels, one stacking. Empty cells paint nothing (UI-R21 #2), so
        // the lines still show wherever there is no paper.
        if (beatLines != null)
          Positioned.fill(child: IgnorePointer(child: beatLines)),
        rowsBody,
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
        //
        // 🚨It starts at the DRAWN end, not the cut end (user 2026-08-11):
        // のりしろ frames are drawn material, so shading them as "outside the
        // cut" was the wash claiming territory it does not own. Without a
        // handle the two are the same number and nothing changes.
        if (frameCellExtent > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: dragPreview == null || cutEndDrag == null
                    ? CustomPaint(
                        painter: TimelineOutsideCutWashPainter(
                          outsideStart: _drawnEnd(null),
                          colorScheme: Theme.of(context).colorScheme,
                        ),
                      )
                    : ValueListenableBuilder<TimelineDragPreview?>(
                        valueListenable: dragPreview,
                        builder: (context, preview, _) => CustomPaint(
                          painter: TimelineOutsideCutWashPainter(
                            outsideStart: _drawnEnd(preview),
                            colorScheme: Theme.of(context).colorScheme,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        // Over the wash, under nothing: one continuous mark with the ruler's.
        if (frameCellExtent > 0)
          if (cutEndDrag != null && dragPreview != null)
            ValueListenableBuilder<TimelineDragPreview?>(
              valueListenable: dragPreview,
              builder: (context, preview, _) => TimelineBodyNoriShiroBoundary(
                left: _drawnEnd(preview),
                cutEnd:
                    timelineCutEndPreviewFrameCount(
                      preview: preview,
                      cutId: cutEndDrag.cutId,
                      playbackFrameCount: playbackFrameCount,
                    ) *
                    frameCellExtent,
              ),
            )
          else
            TimelineBodyNoriShiroBoundary(
              left: _drawnEnd(null),
              cutEnd: playbackFrameCount * frameCellExtent,
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

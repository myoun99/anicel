import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import 'timeline_beat_lines.dart';
import 'timeline_body_cut_end_boundary.dart';
import 'timeline_body_norishiro_boundary.dart';
import 'timeline_cut_end_handle.dart';
import 'timeline_drag_preview.dart';

/// A trim in flight: both hooks present. The four cut-end overlays split on
/// THIS, once — static when there is none, following the preview otherwise.
typedef _LiveTrim = ({
  TimelineCutEndDragCallbacks drag,
  ValueListenable<TimelineDragPreview?> preview,
});

/// The frame cells and everything layered on them, in z-order: the beat
/// lines under the rows, the playhead over them, and where the film stops
/// stated over everything — the out-of-cut wash, the のりしろ mark, the
/// cut-end line and, while a cut is being trimmed, its grip.
///
/// Both grids mount this. The x-sheet is the timeline turned on its side, so
/// it passes [axis] and every overlay turns with it — it used to carry the
/// four overlays of its own, transposed by hand, and `one_cut_end_stack_test`
/// is what keeps that copy from growing back.
class TimelineFrameGridStack extends StatelessWidget {
  const TimelineFrameGridStack({
    super.key,
    this.axis = Axis.horizontal,
    required this.rowsBody,
    this.beatLines,
    required this.playheadExtent,
    required this.playhead,
    this.cutEndDrag,
    this.dragPreview,
    required this.frameCellExtent,
    required this.playbackFrameCount,
    this.drawnFrameCount,
  });

  /// The FRAME axis: horizontal in the timeline, vertical in the x-sheet.
  final Axis axis;
  final Widget rowsBody;

  /// The 6f/24f beat-line overlay (UI-R13 #7): spans EVERY row — SE,
  /// camera, lanes — under the rows, over the ground.
  final Widget? beatLines;

  /// The playhead's extent along the frame axis — the content's. Its cross
  /// extent is the layer's own.
  final double playheadExtent;
  final Widget playhead;

  /// End-line drag hooks (UI-R18 #14): with these set the boundary grows a
  /// grip that end-trims the active cut, and the LINE follows the live trim
  /// preview through [dragPreview]; null keeps the static line.
  final TimelineCutEndDragCallbacks? cutEndDrag;
  final ValueListenable<TimelineDragPreview?>? dragPreview;

  /// One frame along the frame axis, in content pixels. Every offset the
  /// overlays draw at is a frame count times this — the cut end included,
  /// which the stack once also took as a second parameter and trusted to
  /// agree.
  final double frameCellExtent;
  final int playbackFrameCount;

  /// How many frames the cut is DRAWN for — its 尺 plus the のりしろ a
  /// transition span crossing one of its boundaries asks for. Null (or equal to
  /// [playbackFrameCount]) is every cut nothing crosses: no blue line, and the
  /// wash starts at the cut end exactly as it always did.
  final int? drawnFrameCount;

  _LiveTrim? get _liveTrim {
    final drag = cutEndDrag;
    final preview = dragPreview;
    if (drag == null || preview == null) return null;
    return (drag: drag, preview: preview);
  }

  /// Where the cut ends in content pixels, following a live trim.
  double _cutEndOffset(TimelineDragPreview? preview) =>
      timelineCutEndPreviewFrameCount(
        preview: preview,
        cutId: cutEndDrag?.cutId,
        playbackFrameCount: playbackFrameCount,
      ) *
      frameCellExtent;

  /// Where the DRAWN end sits in content pixels, following a live trim so the
  /// blue line and the wash edge never split from the red line mid-drag.
  double _drawnEndOffset(TimelineDragPreview? preview) =>
      timelineDrawnEndOffset(
        preview: preview,
        cutId: cutEndDrag?.cutId,
        playbackFrameCount: playbackFrameCount,
        drawnFrameCount: drawnFrameCount,
        frameCellExtent: frameCellExtent,
      );

  @override
  Widget build(BuildContext context) {
    final beatLines = this.beatLines;
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
          Positioned.fill(
            child: IgnorePointer(child: RepaintBoundary(child: beatLines)),
          ),
        rowsBody,
        _playheadSlot(),
        // The out-of-cut wash and the cut-end line are the TOP layers (the
        // user's layer order 2026-08-02): where the film stops is stated over
        // everything, cursor and selection included. The wash being its own
        // layer at all is what lets a cut-length drag repaint one rect
        // instead of re-baking every row's tiles.
        _wash(context),
        // Over the wash, under nothing: one continuous mark with the ruler's.
        _noriShiro(),
        _cutEndLine(),
        ?_grip(),
      ],
    );
  }

  /// The playhead rides its OWN RepaintBoundary: a cursor move repaints just
  /// that layer instead of re-rasterizing the whole grid.
  Widget _playheadSlot() {
    final horizontal = axis == Axis.horizontal;
    return Positioned(
      left: 0,
      top: 0,
      width: horizontal ? playheadExtent : null,
      height: horizontal ? null : playheadExtent,
      child: RepaintBoundary(child: playhead),
    );
  }

  /// 🚨The wash starts at the DRAWN end, not the cut end (user 2026-08-11):
  /// のりしろ frames are drawn material, so shading them as "outside the
  /// cut" was the wash claiming territory it does not own. Without a handle
  /// the two are the same number and nothing changes.
  Widget _wash(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final live = _liveTrim;
    return Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: live == null
              ? CustomPaint(
                  painter: TimelineOutsideCutWashPainter(
                    axis: axis,
                    outsideStart: _drawnEndOffset(null),
                    colorScheme: colorScheme,
                  ),
                )
              : ValueListenableBuilder<TimelineDragPreview?>(
                  valueListenable: live.preview,
                  builder: (context, preview, _) => CustomPaint(
                    painter: TimelineOutsideCutWashPainter(
                      axis: axis,
                      outsideStart: _drawnEndOffset(preview),
                      colorScheme: colorScheme,
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _noriShiro() {
    final live = _liveTrim;
    if (live == null) {
      return TimelineBodyNoriShiroBoundary(
        axis: axis,
        left: _drawnEndOffset(null),
        cutEnd: _cutEndOffset(null),
      );
    }
    return ValueListenableBuilder<TimelineDragPreview?>(
      valueListenable: live.preview,
      builder: (context, preview, _) => TimelineBodyNoriShiroBoundary(
        axis: axis,
        left: _drawnEndOffset(preview),
        cutEnd: _cutEndOffset(preview),
      ),
    );
  }

  Widget _cutEndLine() {
    final live = _liveTrim;
    if (live == null) {
      return TimelineBodyCutEndBoundary(axis: axis, left: _cutEndOffset(null));
    }
    return ValueListenableBuilder<TimelineDragPreview?>(
      valueListenable: live.preview,
      builder: (context, preview, _) =>
          TimelineBodyCutEndBoundary(axis: axis, left: _cutEndOffset(preview)),
    );
  }

  /// The grip needs only the hooks: it repositions from the preview itself
  /// while its own drag runs, and stands at the static end otherwise.
  Widget? _grip() {
    final drag = cutEndDrag;
    if (drag == null) return null;
    return TimelineCutEndDragHandle(
      axis: axis,
      cellExtent: frameCellExtent,
      playbackFrameCount: playbackFrameCount,
      callbacks: drag,
      dragPreview: dragPreview,
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../input/app_input_settings.dart' show AppInput;

import '../../models/cut_id.dart';
import 'timeline_drag_preview.dart';

/// The timeline end-line drag's session hooks (UI-R18 #14): the red
/// cut-end boundary line grows a grip that end-trims the ACTIVE cut —
/// the storyboard end-grip's timeline sibling, riding the same session
/// channel (live preview, ONE undo on release).
class TimelineCutEndDragCallbacks {
  const TimelineCutEndDragCallbacks({
    required this.cutId,
    required this.onBegin,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  /// The cut whose end the boundary marks (the active cut) — the live
  /// boundary position resolves its previewed duration by this id.
  final CutId cutId;

  final bool Function() onBegin;

  /// Reports the cumulative whole-frame delta since drag start.
  final ValueChanged<int> onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onCancel;
}

/// The playbackFrameCount a boundary consumer should DISPLAY: the live
/// trim preview's duration while a drag targets [cutId], the committed
/// count otherwise.
int timelineCutEndPreviewFrameCount({
  required TimelineDragPreview? preview,
  required CutId? cutId,
  required int playbackFrameCount,
}) {
  if (preview is CutTrimDragPreview && cutId != null) {
    return preview.previewDurations[cutId] ?? playbackFrameCount;
  }
  return playbackFrameCount;
}

/// The DRAWN-end frame count a boundary consumer should display: the same
/// answer as [timelineCutEndPreviewFrameCount] plus the のりしろ handle.
///
/// 🚨The handle is a LENGTH, so it rides the cut end instead of standing
/// still: a transition span crossing this boundary still crosses it after a
/// trim, and asks for the same number of frames on the far side. Computing it
/// as `cutEnd + handle` is what keeps the blue line, the wash edge and the
/// ruler's letters from splitting apart mid-drag — three surfaces reading one
/// function. [drawnFrameCount] null (or not past the cut) means no handle, and
/// then this is just the cut end.
int timelineDrawnEndPreviewFrameCount({
  required TimelineDragPreview? preview,
  required CutId? cutId,
  required int playbackFrameCount,
  required int? drawnFrameCount,
}) {
  final handle = (drawnFrameCount ?? playbackFrameCount) - playbackFrameCount;
  final cutEnd = timelineCutEndPreviewFrameCount(
    preview: preview,
    cutId: cutId,
    playbackFrameCount: playbackFrameCount,
  );
  return handle <= 0 ? cutEnd : cutEnd + handle;
}

/// The draggable layer over a cut-end boundary line (UI-R18 #14): a
/// 12px grip strip centered on the line, axis-aware (vertical line in
/// the horizontal timeline, horizontal line in the X-sheet). Hosts mount
/// it as a Stack sibling OVER the static boundary widget; while a trim
/// drag is live the grip follows the previewed duration through
/// [dragPreview] (value-only — nothing else rebuilds).
class TimelineCutEndDragHandle extends StatefulWidget {
  const TimelineCutEndDragHandle({
    super.key = const ValueKey<String>('timeline-cut-end-handle'),
    required this.cellExtent,
    required this.playbackFrameCount,
    required this.callbacks,
    this.dragPreview,
    this.axis = Axis.horizontal,
  });

  /// Frame cell extent along the frame axis (px/frame) — both the grip's
  /// position and the drag's px→frame conversion.
  final double cellExtent;
  final int playbackFrameCount;
  final TimelineCutEndDragCallbacks callbacks;

  /// The session's scoped drag channel; the grip repositions live from
  /// the trim preview during its own drag.
  final ValueListenable<TimelineDragPreview?>? dragPreview;

  final Axis axis;

  @override
  State<TimelineCutEndDragHandle> createState() =>
      _TimelineCutEndDragHandleState();
}

class _TimelineCutEndDragHandleState extends State<TimelineCutEndDragHandle> {
  double _delta = 0;
  bool _dragging = false;

  void _start() {
    if (!widget.callbacks.onBegin()) {
      return;
    }
    _dragging = true;
    _delta = 0;
  }

  void _update(double delta) {
    if (!_dragging) {
      return;
    }
    _delta += delta;
    widget.callbacks.onUpdate((_delta / widget.cellExtent).round());
  }

  void _end() {
    if (!_dragging) {
      return;
    }
    _dragging = false;
    widget.callbacks.onEnd();
  }

  void _cancel() {
    if (!_dragging) {
      return;
    }
    _dragging = false;
    widget.callbacks.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.axis == Axis.horizontal;
    final grip = MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Drag-only grip: touch follows the timeline input policy
        // (UI-R22F — when touch scrolls the timeline, a finger pan
        // starting on the end grip must scroll too, not trim).
        supportedDevices: AppInput.timelineEditPanDevices,
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: horizontal ? (_) => _start() : null,
        onHorizontalDragUpdate: horizontal
            ? (details) => _update(details.delta.dx)
            : null,
        onHorizontalDragEnd: horizontal ? (_) => _end() : null,
        onHorizontalDragCancel: horizontal ? _cancel : null,
        onVerticalDragStart: horizontal ? null : (_) => _start(),
        onVerticalDragUpdate: horizontal
            ? null
            : (details) => _update(details.delta.dy),
        onVerticalDragEnd: horizontal ? null : (_) => _end(),
        onVerticalDragCancel: horizontal ? null : _cancel,
      ),
    );

    final dragPreview = widget.dragPreview;
    Widget positioned(int frameCount) {
      final main = frameCount * widget.cellExtent - 5;
      return horizontal
          ? Positioned(top: 0, bottom: 0, left: main, width: 12, child: grip)
          : Positioned(left: 0, right: 0, top: main, height: 12, child: grip);
    }

    if (dragPreview == null) {
      return positioned(widget.playbackFrameCount);
    }
    return ValueListenableBuilder<TimelineDragPreview?>(
      valueListenable: dragPreview,
      builder: (context, preview, _) => positioned(
        timelineCutEndPreviewFrameCount(
          preview: preview,
          cutId: widget.callbacks.cutId,
          playbackFrameCount: widget.playbackFrameCount,
        ),
      ),
    );
  }
}

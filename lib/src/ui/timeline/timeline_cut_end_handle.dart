import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/cut_id.dart';
import 'timeline_drag_preview.dart';
import 'timeline_frame_coordinate_policy.dart' show timelineFrameEdge;
import 'axis_turn.dart';
import '../widgets/owning_axis_grip.dart';

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

/// How many frames a cut is DRAWN for — its 尺 plus the のりしろ a transition
/// span crossing one of its boundaries asks for — and the word the ruler
/// spells across that margin.
typedef TimelineNoriShiro = ({int drawnFrameCount, String label});

/// The playbackFrameCount a boundary consumer should DISPLAY: the live
/// trim preview's duration while a drag targets [cutId]; on a surface whose
/// end is the MOVIE's (the storyboard), whatever [movieEndUnder] says the
/// drag in flight leaves; the committed count otherwise.
///
/// 🚨F-18 (유저 2026-08-28): 「프레임영역은 라이브로 따라가는데 룰러에 있는
/// 엔드라인은 라이브로 안보임. 이걸 통일이라고 한거냐?」 — the storyboard's
/// strip read the movie-end drag through a function of its own and its ruler
/// read none, so one end line kept two laws. Every end line reads this one.
///
/// ↩️That function was `movieEndPreviewTotalFrames` (F-18, 유저 2026-08-24:
/// 「스토리보드패널의 엔드라인 드래그시 라이브로 안보임. 어떤 다른 규칙을
/// 만든거지? 타임라인패널이랑 통일」). Its reason stays true: the storyboard's
/// body builds from the committed project once, on purpose, so an end line
/// reads the preview itself rather than the panel re-reading the project.
///
/// 🚨F-119 (유저 2026-09-12): 「마지막에 있던 컷 블록을 앞으로 당기면 최종
/// 영상 엔드라인이 움직이면서 룰러랑 프레임영역이랑 어긋남」. ↩️The movie's
/// end used to be read off a MOVIE-END drag's preview alone — the trailing
/// gap — so pulling or trimming the last cut moved its blocks while every
/// end line stood still until the release. The movie end under a drag is
/// the end of the project the BLOCKS are drawn from, whichever drag it is:
/// [movieEndUnder] is that one reading, and the surface hands it in.
int timelineCutEndPreviewFrameCount({
  required TimelineDragPreview? preview,
  required CutId? cutId,
  required int playbackFrameCount,
  int Function(TimelineDragPreview preview)? movieEndUnder,
}) {
  if (movieEndUnder != null) {
    return preview == null ? playbackFrameCount : movieEndUnder(preview);
  }
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
  int Function(TimelineDragPreview preview)? movieEndUnder,
}) {
  final handle = (drawnFrameCount ?? playbackFrameCount) - playbackFrameCount;
  final cutEnd = timelineCutEndPreviewFrameCount(
    preview: preview,
    cutId: cutId,
    playbackFrameCount: playbackFrameCount,
    movieEndUnder: movieEndUnder,
  );
  return handle <= 0 ? cutEnd : cutEnd + handle;
}

/// [timelineDrawnEndPreviewFrameCount] in content pixels along the frame
/// axis. The body stack's wash edge and blue line and the x-sheet rail's
/// drawn-end mark read this ONE product — no surface multiplies on its own.
double timelineDrawnEndOffset({
  required TimelineDragPreview? preview,
  required CutId? cutId,
  required int playbackFrameCount,
  required int? drawnFrameCount,
  required double frameCellExtent,
}) => timelineFrameEdge(
  timelineDrawnEndPreviewFrameCount(
    preview: preview,
    cutId: cutId,
    playbackFrameCount: playbackFrameCount,
    drawnFrameCount: drawnFrameCount,
  ),
  frameCellExtent,
);

/// The draggable layer over a cut-end boundary line (UI-R18 #14): a
/// 12px grip strip centered on the line, axis-aware (vertical line in
/// the horizontal timeline, horizontal line in the X-sheet). Hosts mount
/// it as a Stack sibling OVER the static boundary widget; while a trim
/// drag is live the grip follows the previewed duration through
/// [dragPreview] (value-only — nothing else rebuilds).
class TimelineCutEndDragHandle extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final grip = EndLineGrip(
      axis: axis,
      cellExtent: cellExtent,
      onBegin: callbacks.onBegin,
      onUpdate: callbacks.onUpdate,
      onEnd: callbacks.onEnd,
      onCancel: callbacks.onCancel,
    );

    final dragPreview = this.dragPreview;
    Widget positioned(int frameCount) {
      final main = timelineFrameEdge(frameCount, cellExtent) - 5;
      return stripAlong(axis, along: main, alongExtent: 12, child: grip);
    }

    if (dragPreview == null) {
      return positioned(playbackFrameCount);
    }
    return ValueListenableBuilder<TimelineDragPreview?>(
      valueListenable: dragPreview,
      builder: (context, preview, _) => positioned(
        timelineCutEndPreviewFrameCount(
          preview: preview,
          cutId: callbacks.cutId,
          playbackFrameCount: playbackFrameCount,
        ),
      ),
    );
  }
}

/// The grip an END LINE is dragged by — the timeline's cut end and the conte
/// panel's movie end, each placing it over its own line: the press is the
/// line's, and [onUpdate] hears the whole frames the hand has moved along
/// [axis] since it went down (frames of [cellExtent] px). [onBegin] refusing
/// leaves the rest of the gesture unheard.
///
/// 🗣️F-445 (유저 2026-10-23): 「엔드라인 손으로 드래그할때 가끔 프레임영역
/// 가로 스크롤 작동함. 엔드라인은 조작 위젯이니까 작동안하게 제대로 다른위젯처럼
/// 강한클레임으로 법 통일」 — ↩️the conte panel's end line kept a grip of its
/// own, a plain one-axis drag, after the timeline's had been given the strong
/// claim below; the frame area's two-axis touch scroll beat it to a finger
/// that left a little off its axis. Both lines are dragged by this one now.
class EndLineGrip extends StatefulWidget {
  const EndLineGrip({
    super.key,
    required this.axis,
    required this.cellExtent,
    required this.onBegin,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  final Axis axis;
  final double cellExtent;
  final bool Function() onBegin;

  /// Reports the cumulative whole-frame delta since drag start.
  final ValueChanged<int> onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onCancel;

  @override
  State<EndLineGrip> createState() => _EndLineGripState();
}

class _EndLineGripState extends State<EndLineGrip> {
  double _delta = 0;
  bool _dragging = false;

  void _start() {
    if (!widget.onBegin()) {
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
    widget.onUpdate((_delta / widget.cellExtent).round());
  }

  void _end() {
    if (!_dragging) {
      return;
    }
    _dragging = false;
    widget.onEnd();
  }

  void _cancel() {
    if (!_dragging) {
      return;
    }
    _dragging = false;
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.axis == Axis.horizontal;
    return MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      // 🚨THE THIRD GRIP OF ONE LAW (F-163 재발, 유저 2026-09-23: 「버튼은
      // 무조건 강한클레임이라는거 감안해서 같은법 적용해줘」). ↩️A plain
      // one-axis drag, so a pull across it walked over to the scroller, and
      // it took no finger while touch scrolls the timeline (UI-R22F) — the
      // comma grips' two faults exactly, fixed the way they were.
      child: OwningAxisGrip(
        axis: widget.axis,
        configure: (recognizer) => recognizer
          ..dragStartBehavior = DragStartBehavior.down
          ..onStart = ((_) => _start())
          ..onUpdate = ((details) => _update(details.primaryDelta!))
          ..onEnd = ((_) => _end())
          ..onCancel = _cancel,
      ),
    );
  }
}

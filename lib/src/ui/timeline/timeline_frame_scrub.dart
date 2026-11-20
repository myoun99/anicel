/// THE FRAME SCRUB — a press or a drag on a frame-axis strip picking the
/// frame under it, the clamp, the auto-pan at the edge and the tracking that
/// ends with the scrub.
library;

import 'package:flutter/widgets.dart';

import '../canvas/canvas_press.dart' show canvasPressButtons, canvasPressPans;
import '../input/value_control_pointers.dart' show valueControlOwnsPointer;
import '../widgets/axis_gesture_detector.dart';
import 'axis_turn.dart' show extentAlong, partAlong;
import 'timeline_edge_auto_pan.dart';
import 'timeline_frame_coordinate_policy.dart';

/// Where a scrub's frames go ([TimelineFrameScrub]): each move's to
/// [scrubbed] — the cursor alone — and the one commit to [ended] as the
/// pointer lets go; where a host has no [scrubbed], each move's to
/// [selected]. A grid hands its hooks' (`TimelineGridHooks.scrubSinks`), in
/// its cut's frames; the conte's ruler its panel's, in the track's.
typedef FrameScrubSinks = ({
  ValueChanged<int>? selected,
  ValueChanged<int>? scrubbed,
  VoidCallback? ended,
});

/// Whether a press on a ruler strip is the strip's to scrub by — ONE answer
/// for the ruler across, the X-sheet's rail down and the conte panel's
/// ruler.
///
/// Not a press that pans (R26 #34: a press that pans is the pan's), and not
/// one a control standing on the strip has taken — a marker, which holds
/// the strong claim by the time the strip hears the press. 🗣️I-169-Q1 (유저
/// 2026-11-13): 「룰러 한 칸에서 위쪽절반은 마크위젯, 아래는 기존처럼
/// 룰러위젯으로 대응하도록」.
bool rulerPressScrubs(PointerDownEvent event) =>
    !canvasPressPans(canvasPressButtons(event)) &&
    !valueControlOwnsPointer(event.pointer);

/// The scrub on a strip whose frames run along [axis].
///
/// 🚨ONE object for both grids. The timeline's ruler runs the frame axis
/// ACROSS the top and the X-sheet's rail runs it DOWN the side, and each
/// carried its own copy of all six members — the same six sentences, once
/// with `.dx` and `viewport.size.width` and once with `.dy` and
/// `viewport.size.height` (the audit's clone scan, round 8). The axis is a
/// VALUE here, the way Flutter's own `Axis` serves Flex and ListView, so
/// there is one body and no side can lag the other.
///
/// 🚨AND FOR THE CONTE'S RULER, the third (board
/// the-conte-ruler-scrubs-through-the-one-area, 11-18): it called the same
/// policy functions and assembled the press, the drag and the release of
/// its own — and so it panned on a press near its edge, which the grids
/// stopped doing (R10 R6, [pressAt]), and counted its frames from an
/// offset other than the one its ruler is painted at.
///
/// Everything a scrub needs from its host arrives as a getter, because the
/// metrics, the sinks and the rendered extent all change under it between
/// gestures; the controller and the viewport key are fixed for the host's
/// life and arrive as themselves.
class TimelineFrameScrub {
  TimelineFrameScrub({
    required this.axis,
    required this.viewportKey,
    required this.controller,
    required this.sinks,
    required this.frameCellExtent,
    required this.renderedFrameCount,
    required this.scrolledFrameOffset,
    required this.hold,
    required this.letGo,
  });

  /// The axis the FRAMES run along: horizontal on the timeline's ruler,
  /// vertical on the X-sheet's rail.
  final Axis axis;

  /// The strip's scroll VIEWPORT — the box a global position is read in.
  final GlobalKey viewportKey;

  /// The frame axis's scroll controller, the one an edge pan moves.
  final ScrollController controller;

  final FrameScrubSinks Function() sinks;
  final double Function() frameCellExtent;

  /// The BUILT extent the clamp answers against (UI-R12 #16).
  final int Function() renderedFrameCount;

  /// The effective frame-axis offset the last layout resolved.
  final double Function() scrolledFrameOffset;

  /// The axis's own [TimelineFrameAxisFollower.hold]: a drag holds the axis
  /// by this strip, and pushed past the end it grows a runway ahead.
  final VoidCallback hold;

  /// The axis's own [TimelineFrameAxisFollower.letGo]: a scrub that let go
  /// has carried the axis as far as it goes, and a runway it grew past the
  /// end shrinks as a settled scroll's does.
  final VoidCallback letGo;

  /// A scrub's per-gesture frame dedupe — see [FrameScrubDedupe] for why a
  /// scrub cannot report the same frame twice.
  final FrameScrubDedupe _scrubbedFrame = FrameScrubDedupe();

  int? _frameIndexAt(double alongLocal) => frameIndexFromLocalX(
    localX: alongLocal,
    horizontalScrollOffset: scrolledFrameOffset(),
    frameCellWidth: frameCellExtent(),
    visibleFrameCount: renderedFrameCount(),
  );

  void _selectClampedFrame(int frameIndex) {
    // The endless runway IS the selectable tail now (UI-R10 #23 retired
    // the fixed safety frames): clamp against the BUILT extent.
    final frame = _scrubbedFrame.next(
      clampFrameIndex(
        frameIndex: frameIndex,
        visibleFrameCount: renderedFrameCount(),
      ),
    );
    if (frame == null) {
      return;
    }
    final host = sinks();
    (host.scrubbed ?? host.selected)?.call(frame);
  }

  /// The scrub gesture's release (raw pointer up/cancel — fires for taps
  /// AND drags, wherever the pointer ends up). Tracking is NOT reset here
  /// so a strip's trailing onTap stays deduplicated.
  void endScrub() {
    letGo();
    sinks().ended?.call();
  }

  void resetTracking() => _scrubbedFrame.reset();

  /// A PRESS on the strip: the frame under the pointer, and nothing else.
  ///
  /// 🚨LANDING NEAR AN END OF THE STRIP IS NOT A PUSH TOWARD IT. R10 R6
  /// found this the expensive way — the rail runs this from `onPointerDown`
  /// as well as from drag updates, so a plain tap inside the edge band
  /// scrolled the sheet under the finger before the frame was even
  /// resolved. The band is a fraction of the viewport, so the shorter the
  /// rail the larger the share of it that was untappable.
  ///
  /// ⚠️The horizontal ruler used to pan on its press too, and only its
  /// width hid it: same code, same law, both strips (round 8's unification
  /// of the two scrubs).
  void pressAt(Offset globalPosition) {
    final viewport = _viewport();
    if (viewport == null) {
      return;
    }
    _selectFrameAt(viewport, globalPosition);
  }

  /// A DRAG across the strip: the frame under the pointer, and the edge pan
  /// that reaches for the frames past the viewport.
  void dragTo(Offset globalPosition) {
    final viewport = _viewport();
    if (viewport == null) {
      return;
    }
    hold();
    _autoPanEdge(viewport, _alongLocal(viewport, globalPosition));
    _selectFrameAt(viewport, globalPosition);
  }

  RenderBox? _viewport() {
    final renderObject = viewportKey.currentContext?.findRenderObject();
    return renderObject is RenderBox ? renderObject : null;
  }

  /// The pointer's position ALONG the strip, in the viewport's own frame.
  double _alongLocal(RenderBox viewport, Offset globalPosition) {
    return partAlong(axis, viewport.globalToLocal(globalPosition));
  }

  void _selectFrameAt(RenderBox viewport, Offset globalPosition) {
    final frameIndex = _frameIndexAt(_alongLocal(viewport, globalPosition));
    if (frameIndex == null) {
      return;
    }
    _selectClampedFrame(frameIndex);
  }

  /// Edge auto-pan (UI-R10 #24, the pro-standard ruler drag): a scrub
  /// pointer past the viewport edge scrolls the frame axis under it. Toward
  /// the end it deliberately OVERSHOOTS the built extent (UI-R12 #16): the
  /// strip drag is THE way past the last built cell — the growth listener
  /// materializes the frames the overshot view needs, while the scrollbar
  /// and scroll physics stay clamped at the built cells. With the endless
  /// growth feeding cells ahead, the strip drag alone reaches ANY frame.
  void _autoPanEdge(RenderBox viewport, double alongLocal) {
    if (!viewport.hasSize) {
      return;
    }
    edgeAutoPanOvershoot(
      controller,
      edgeAutoPanDelta(alongLocal, extentAlong(axis, viewport.size)),
    );
  }
}

/// Where a press on a frame strip scrubs [scrub] — the timeline's ruler
/// across and the X-sheet's rail down, ONE body turned by the scrub's axis.
///
/// The pointer layer scrubs on the press itself, so the playhead comes to
/// the finger at once, taps included, and ends the scrub on the raw up or
/// cancel wherever the pointer ends up; the drag along the strip only feeds
/// the moves. R26 #34: a press that pans is the pan's, not a scrub — and a
/// marker's is the marker's (I-169, [rulerPressScrubs]).
///
/// ↩️Each grid carried this body of its own, once with horizontal drags and
/// once with vertical ones; the clone scan saw the pair when the ruler left
/// the grid's build (card an-eye-toggle-holds-the-ui-thread, 11-18).
class TimelineFrameScrubArea extends StatelessWidget {
  const TimelineFrameScrubArea({
    super.key,
    required this.scrub,
    required this.child,
  });

  final TimelineFrameScrub scrub;
  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (event) {
      if (!rulerPressScrubs(event)) {
        return;
      }
      scrub.resetTracking();
      scrub.pressAt(event.position);
    },
    onPointerUp: (_) => scrub.endScrub(),
    onPointerCancel: (_) => scrub.endScrub(),
    child: AxisGestureDetector(
      axis: scrub.axis,
      behavior: HitTestBehavior.translucent,
      onDragStart: (details) => scrub.pressAt(details.globalPosition),
      onDragUpdate: (details) => scrub.dragTo(details.globalPosition),
      onDragEnd: (_) => scrub.resetTracking(),
      onDragCancel: scrub.resetTracking,
      child: child,
    ),
  );
}

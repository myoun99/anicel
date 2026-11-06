import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../input/two_axis_drag.dart' show TwoAxisScrollController;
import 'axis_turn.dart' show partAlong;
import 'timeline_edge_auto_pan.dart' show scrollableIsShown;
import 'timeline_frame_coordinate_policy.dart'
    show timelineFrameAt, timelineFrameEdge;

/// Where the frame axis should sit after a zoom step (Premiere-style
/// zoom-around-playhead), shared by every frame-axis surface — the
/// horizontal timeline, the X-sheet (transposed) and the storyboard.
///
/// The playhead frame anchors when it is inside the viewport: its on-screen
/// position stays put while the cells stretch around it. When the playhead
/// is off screen (or the surface has none) the viewport's leading-edge
/// content anchors instead — the previous behavior — so zooming far away
/// from the playhead never yanks the view across the track.
///
/// 🗣️I-155-Q1 b (유저 2026-11-04): 「휠 줌만 커서 기준」 — a step a notch
/// asked for anchors the point it was turned at ([anchorAt], along the
/// axis from the viewport's leading edge) in the playhead's place: the
/// frame under it stays under it, as far across its cell.
/// 🗣️F-565 (유저 2026-11-04): 「프레임 영역을 손가락2개로 줌하는것, 휠로
/// 줌하는거랑 똑같이 커서(손가락위치?) 기준으로」 — a pinch's step anchors the
/// middle of its fingers the same way. The keys and the bar have no point,
/// and hold the playhead.
double zoomAnchoredScrollOffset({
  required double oldOffset,
  required double oldPixelsPerFrame,
  required double newPixelsPerFrame,
  required double viewportExtent,
  int? anchorFrame,
  double? anchorAt,
}) {
  // Anchor on the frame CELL's center, matching the playhead tint — the
  // cell the frame axis' one law lays out at each zoom.
  final at =
      anchorAt ??
      switch (anchorFrame) {
        final frame? => _stretched(frame + 0.5, oldPixelsPerFrame) - oldOffset,
        null => null,
      };
  if (at != null && viewportExtent > 0 && at >= 0 && at <= viewportExtent) {
    final frames = _framesAt(oldOffset + at, oldPixelsPerFrame);
    return math.max(0, _stretched(frames, newPixelsPerFrame) - at);
  }
  return math.max(0, oldOffset * (newPixelsPerFrame / oldPixelsPerFrame));
}

/// How many frames along the axis [offset] stands: the frame whose cell
/// holds it, and how far across that cell.
double _framesAt(double offset, double pixelsPerFrame) {
  final frame = timelineFrameAt(offset, pixelsPerFrame);
  final start = timelineFrameEdge(frame, pixelsPerFrame);
  final span = timelineFrameEdge(frame + 1, pixelsPerFrame) - start;
  return frame + (span > 0 ? (offset - start) / span : 0);
}

/// Where [frames] stands along the axis at [pixelsPerFrame] — [_framesAt]
/// read back, in the cell the law lays.
double _stretched(double frames, double pixelsPerFrame) {
  final frame = frames.floor();
  final start = timelineFrameEdge(frame, pixelsPerFrame);
  final end = timelineFrameEdge(frame + 1, pixelsPerFrame);
  return start + (frames - frame) * (end - start);
}

/// Re-anchors [controller] after the frame cell changed size, if it did.
///
/// ⛔BOTH GRIDS DID THIS IN `didUpdateWidget` — the horizontal timeline and
/// the transposed x-sheet — down to reading the viewport extent off the
/// controller's own position. The AXIS is the only difference, and an axis
/// is not a reason to write a policy twice: the x-sheet's copy already
/// carried a comment saying it was the same policy.
///
/// 🚨Not in a folded panel ([scrollableIsShown]): the row it folded into
/// anchors the shared axis on its own window (유저 2026-09-27,
/// folded-row-playhead-during-playback-Q1). The grid folded away anchored
/// it from a scroll position no page had moved, and from the middle of a
/// build, which dirtied the folded row mid-build — measured, a debug
/// assertion on every zoom step with the axis scrolled.
///
/// The point a notch or a pinch held ([TwoAxisScrollController.zoomHold])
/// is taken here whether or not this is its step: it anchors the step it
/// asked for and no later one.
void applyZoomAnchoredScroll(
  TwoAxisScrollController controller, {
  required double oldPixelsPerFrame,
  required double newPixelsPerFrame,
  int? anchorFrame,
}) {
  final hold = controller.zoomHold;
  controller.zoomHold = null;
  if (oldPixelsPerFrame == newPixelsPerFrame ||
      !controller.hasClients ||
      !scrollableIsShown(controller.position)) {
    return;
  }
  final position = controller.position;
  controller.jumpTo(
    zoomAnchoredScrollOffset(
      oldOffset: controller.offset,
      oldPixelsPerFrame: oldPixelsPerFrame,
      newPixelsPerFrame: newPixelsPerFrame,
      viewportExtent: position.viewportDimension,
      anchorFrame: anchorFrame,
      anchorAt: switch (hold) {
        (:final at, :final to) when to == newPixelsPerFrame => _along(
          position,
          at,
        ),
        _ => null,
      },
    ),
  );
}

/// How far along [position]'s axis the global point [at] stands from its
/// viewport's leading edge — the viewport-local offset every press on the
/// frame axis is read at (`frameIndexFromLocalX`).
double? _along(ScrollPosition position, Offset at) {
  final viewport = position.context.notificationContext?.findRenderObject();
  if (viewport is! RenderBox || !viewport.hasSize) {
    return null;
  }
  return partAlong(position.axis, viewport.globalToLocal(at));
}

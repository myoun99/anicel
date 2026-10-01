import 'dart:math' as math;

import 'timeline_frame_coordinate_policy.dart'
    show timelineFrameAt, timelineFrameEdge;

/// Converts timeline frame positions and durations into visual pixel sizes.
///
/// This is a UI helper only. It does not know about or mutate project models.
///
/// Every position it answers is the frame axis' one law
/// ([timelineFrameEdge]), and every width is the distance between two of
/// its boundaries — ⛔never a frame count times [pixelsPerFrame]: once a cell
/// is not a whole number of pixels (F-220), a span's own product drifts off
/// the boundaries every other surface draws.
class TimelineScale {
  const TimelineScale({this.pixelsPerFrame = 8.0, this.minBlockWidth = 96.0});

  final double pixelsPerFrame;
  final double minBlockWidth;

  double leftForFrame(int frame) => timelineFrameEdge(frame, pixelsPerFrame);

  /// The frame whose cell holds [x] — [leftForFrame] read backwards.
  int frameAt(double x) => timelineFrameAt(x, pixelsPerFrame);

  /// How many frames from frame 0 reach into the first [extent] pixels.
  int framesCovering(double extent) => pixelsPerFrame <= 0 || extent <= 0
      ? 0
      : frameAt(extent - _insideEdge) + 1;

  /// How far inside an extent's far end its last covered frame is asked
  /// for — a far end ON a boundary covers the frame before it, not after.
  static const double _insideEdge = 1e-6;

  /// The width of the frames [startFrame, endFrameExclusive).
  double spanWidth(int startFrame, int endFrameExclusive) =>
      leftForFrame(endFrameExclusive) - leftForFrame(startFrame);

  /// Where a block of [duration] frames from [startFrame] ENDS: at its last
  /// frame's far boundary, or [minBlockWidth] on from its start when that
  /// is further.
  double blockEndFor(int startFrame, int duration) => math.max(
    leftForFrame(startFrame + duration),
    leftForFrame(startFrame) + minBlockWidth,
  );
}

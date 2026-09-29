/// Resolves pure frame index / x-position conversion for timeline UI code.
///
/// Local x to frame index conversion must use the effective horizontal offset,
/// not a raw out-of-bounds scroll offset. These helpers are shared by ruler hit
/// testing and timeline overlay positioning.
///
/// This policy must not know about playback duration, authored extent, or
/// `Cut.duration` semantics.

library;

import 'dart:math' as math;

/// Where the boundary BEFORE frame [frameIndex] lands along the frame axis,
/// counted from frame 0's — THE frame→pixel law. Every frame-axis position
/// on every panel is read through it, and [timelineFrameAt] reads it back.
///
/// 🗣️F-220 (유저 2026-09-29): the zoom follows every percent now, so a cell
/// is seldom a whole number of pixels. From a pixel a cell up, a boundary
/// lands on the whole pixel nearest it: a frame line stays one crisp
/// column at any zoom, as it was on the whole-pixel zooms the old grid
/// allowed, and every surface puts the same boundary on the same column —
/// a cell is then its zoom's width give or take one pixel. Under a pixel a
/// cell is left where it falls: rounding there would stack boundaries on
/// one pixel and leave a one-frame block no width at all.
double timelineFrameEdge(int frameIndex, double cellExtent) {
  final exact = frameIndex * cellExtent;
  return cellExtent >= 1 ? exact.roundToDouble() : exact;
}

/// The frame whose cell holds [offset] — [timelineFrameEdge] read
/// backwards: the last frame whose leading boundary is at or before it.
/// Unclamped; the caller holds it to its own frames.
///
/// A boundary within [_boundarySlack] counts as reached: an offset built
/// by adding a span's width to its start's boundary lands on the far
/// boundary give or take a rounding error, and must name that frame.
int timelineFrameAt(double offset, double cellExtent) {
  if (cellExtent <= 0) {
    return 0;
  }
  // The boundaries sit within half a pixel of the plain quotient's, so it
  // is at most one frame off either way.
  final reach = offset + _boundarySlack;
  var frame = (reach / cellExtent).floor();
  if (timelineFrameEdge(frame + 1, cellExtent) <= reach) {
    frame += 1;
  } else if (timelineFrameEdge(frame, cellExtent) > reach) {
    frame -= 1;
  }
  return frame;
}

/// Far under any pixel, far over a double's error at a timeline's extent.
const double _boundarySlack = 1e-9;

int? frameIndexFromLocalX({
  required double localX,
  required double horizontalScrollOffset,
  required double frameCellWidth,
  required int visibleFrameCount,
}) {
  if (visibleFrameCount <= 0 || frameCellWidth <= 0) {
    return null;
  }

  final frameIndex = timelineFrameAt(
    localX + horizontalScrollOffset,
    frameCellWidth,
  );

  return clampFrameIndex(
    frameIndex: frameIndex,
    visibleFrameCount: visibleFrameCount,
  );
}

int? clampFrameIndex({
  required int frameIndex,
  required int visibleFrameCount,
}) {
  if (visibleFrameCount <= 0) {
    return null;
  }

  return frameIndex.clamp(0, visibleFrameCount - 1).toInt();
}

/// [frameIndex]'s leading boundary in a surface whose [frameStartIndex]
/// stands at [leadingFrameSpacerWidth] — the law's boundaries, moved as one.
double frameVisibleX({
  required int frameIndex,
  required int frameStartIndex,
  required double frameCellWidth,
  required double leadingFrameSpacerWidth,
}) {
  return leadingFrameSpacerWidth +
      timelineFrameEdge(frameIndex, frameCellWidth) -
      timelineFrameEdge(frameStartIndex, frameCellWidth);
}

double frameRangeVisibleWidth({
  required int startFrameIndex,
  required int endFrameIndexExclusive,
  required double frameCellWidth,
}) {
  return math.max(
    0.0,
    timelineFrameEdge(endFrameIndexExclusive, frameCellWidth) -
        timelineFrameEdge(startFrameIndex, frameCellWidth),
  );
}

/// A scrub's per-gesture frame dedupe.
///
/// ⛔THE DEDUPE IS THE LAW, AND THE USER NAMED IT (feedback #13:
/// 「로직도 똑같이 통일하라는거니까」). A scrub reports per POINTER MOVE,
/// so without it the same frame is re-selected dozens of times a second
/// and every listener downstream — the composite warmer included — re-runs
/// on a selection that did not change.
///
/// Three scrubs kept their own `int?` field and their own `== last` line:
/// the timeline ruler, the X-sheet rail and the storyboard strip.
class FrameScrubDedupe {
  int? _last;

  /// [frame] when it differs from the last one reported, remembering it —
  /// else null, a null [frame] included.
  int? next(int? frame) {
    if (frame == null || frame == _last) {
      return null;
    }
    _last = frame;
    return frame;
  }

  /// Forgets the last frame, so the next gesture reports from scratch.
  ///
  /// ⚠️NOT called on a scrub's release: the ruler's trailing `onTap` fires
  /// after the pointer is up, and resetting there would let it report the
  /// frame the drag just reported.
  void reset() => _last = null;
}

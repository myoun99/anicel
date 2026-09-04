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

int? frameIndexFromLocalX({
  required double localX,
  required double horizontalScrollOffset,
  required double frameCellWidth,
  required int visibleFrameCount,
}) {
  if (visibleFrameCount <= 0 || frameCellWidth <= 0) {
    return null;
  }

  final frameIndex = ((localX + horizontalScrollOffset) / frameCellWidth)
      .floor();

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

double frameVisibleX({
  required int frameIndex,
  required int frameStartIndex,
  required double frameCellWidth,
  required double leadingFrameSpacerWidth,
}) {
  return leadingFrameSpacerWidth +
      (frameIndex - frameStartIndex) * frameCellWidth;
}

double frameRangeVisibleWidth({
  required int startFrameIndex,
  required int endFrameIndexExclusive,
  required double frameCellWidth,
}) {
  return math.max(0, endFrameIndexExclusive - startFrameIndex) * frameCellWidth;
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

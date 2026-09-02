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

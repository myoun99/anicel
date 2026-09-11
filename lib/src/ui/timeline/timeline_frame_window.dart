import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;

/// UI-R16: the SHARED frame-axis window policy — one quantization every
/// self-windowing consumer agrees on (row/ruler/rail painters, the
/// cursor layer, sparse widget rows, lane strips; all three panels).
///
/// The scroll offset quantizes to BUCKETS spanning several cells (never
/// finer than [timelineFrameWindowMinSpanPx]): the bucket notifier fires
/// only on a span crossing, so painters listening to it repaint once per
/// span instead of once per pixel — between crossings a scroll frame is
/// pure translation of already-painted layers (the storyboard-block
/// behavior, generalized; stable pictures also become raster-cacheable).
/// The window covering a bucket includes everything the viewport can
/// reveal across the WHOLE span, plus overscan on both sides.
///
/// Consumers treat the returned window as CONTENT-SPACE frame indices
/// (the UI-R15 full-bounds contract: frame 0 at offset 0) and clamp to
/// their own bounds.

/// Cells per bucket span (the repaint cadence in cells).
const int timelineFrameWindowSpanCells = 4;

/// Spans never get finer than this many pixels — tiny cells (storyboard
/// zoom levels) would otherwise re-approach per-pixel repainting.
const double timelineFrameWindowMinSpanPx = 96;

/// Safety cells painted beyond the span's reach on both sides.
const int timelineFrameWindowOverscanCells = 2;

/// The bucket span in CELLS for [cellExtent] (≥ [timelineFrameWindowSpanCells],
/// grown to honor [timelineFrameWindowMinSpanPx]).
int timelineFrameWindowSpanFor(double cellExtent) {
  if (cellExtent <= 0) {
    return timelineFrameWindowSpanCells;
  }
  return math.max(
    timelineFrameWindowSpanCells,
    (timelineFrameWindowMinSpanPx / cellExtent).ceil(),
  );
}

/// The bucket index for [offset] — panel scroll handlers feed their
/// bucket notifier with this.
int timelineFrameWindowBucketOf({
  required double offset,
  required double cellExtent,
}) {
  final spanPx = timelineFrameWindowSpanFor(cellExtent) * cellExtent;
  if (spanPx <= 0) {
    return 0;
  }
  return (offset / spanPx).floor();
}

/// The frame window a consumer must keep materialized for [bucket]:
/// every cell the viewport can reveal while the offset stays anywhere in
/// the bucket's span, plus overscan. Unclamped — callers intersect with
/// their own frame bounds.
({int startIndex, int endIndexExclusive}) timelineFrameWindowFor({
  required int bucket,
  required double cellExtent,
  required double viewportExtent,
}) {
  final span = timelineFrameWindowSpanFor(cellExtent);
  final viewportCells = cellExtent <= 0
      ? 0
      : (viewportExtent / cellExtent).ceil();
  return (
    startIndex: bucket * span - timelineFrameWindowOverscanCells,
    endIndexExclusive:
        (bucket + 1) * span + viewportCells + timelineFrameWindowOverscanCells,
  );
}

/// The frame window a painter actually draws: the bucket's window clipped
/// to the painter's own [frameStartIndex, frameEndIndexExclusive), or the
/// full bounds when there is no bucket (the classic pre-windowed contract).
///
/// 🚨One law for the ruler and the sheet's frame rail — the two painters
/// each spelled it (the audit's clone scan, 2026-09-03).
({int startIndex, int endIndexExclusive}) visibleFrameWindowFor({
  required ValueListenable<int>? bucket,
  required double viewportMainExtent,
  required double cellExtent,
  required int frameStartIndex,
  required int frameEndIndexExclusive,
}) {
  if (bucket == null || viewportMainExtent <= 0 || cellExtent <= 0) {
    return (
      startIndex: frameStartIndex,
      endIndexExclusive: frameEndIndexExclusive,
    );
  }
  final window = timelineFrameWindowFor(
    bucket: bucket.value,
    cellExtent: cellExtent,
    viewportExtent: viewportMainExtent,
  );
  return (
    startIndex: math.max(frameStartIndex, window.startIndex),
    endIndexExclusive: math.min(
      frameEndIndexExclusive,
      window.endIndexExclusive,
    ),
  );
}

/// Whether [frame] lies in [window] — what every playhead-driven layer asks
/// before it marks a frame: the body's cursor, the ruler's tint and the
/// playhead's writing (I-16). One answer, so the three cannot mark
/// different frames.
bool frameWindowContains(
  ({int startIndex, int endIndexExclusive}) window,
  int frame,
) => frame >= window.startIndex && frame < window.endIndexExclusive;

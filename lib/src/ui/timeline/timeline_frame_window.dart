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
///
/// 🚨Every painter that follows the bucket stands on a layer of its own:
/// a crossing repaints it, and whatever shares its layer is recorded again
/// with it. The row edit chrome did not, and every page turn re-recorded
/// every row whole (2026-10-11).

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
/// the bucket's span, plus overscan, out to the edge of the span it ends
/// in ([_spansReached]). Unclamped — callers intersect with their own frame
/// bounds.
({int startIndex, int endIndexExclusive}) timelineFrameWindowFor({
  required int bucket,
  required double cellExtent,
  required double viewportExtent,
}) {
  final span = timelineFrameWindowSpanFor(cellExtent);
  return (
    startIndex: bucket * span - timelineFrameWindowOverscanCells,
    endIndexExclusive:
        (bucket + _spansReached(cellExtent, viewportExtent)) * span,
  );
}

/// How many spans a window covers from its bucket's first cell: the bucket's
/// own, the viewport's cells and the overscan past them — rounded UP to a
/// whole span.
///
/// 🚨Rounded so a view a pixel wider or narrower keeps its window, as an
/// offset a pixel on keeps its bucket (storyboard-strips-build-on-every-
/// view-pixel, 2026-10-30): the storyboard's strips build their pieces for
/// the window, and every pixel of a rail splitter's drag built them all
/// again. A window now ends on a span's edge, where the cells' tiles are cut
/// (`timelineFrameWindowSpanFor`) — so a row bakes the tiles it baked.
int _spansReached(double cellExtent, double viewportExtent) {
  final span = timelineFrameWindowSpanFor(cellExtent);
  final viewportCells = cellExtent <= 0
      ? 0
      : (viewportExtent / cellExtent).ceil();
  final cells = span + viewportCells + timelineFrameWindowOverscanCells;
  return (cells + span - 1) ~/ span;
}

/// What a piece built for the window keys on in place of the view's breadth
/// ([visibleFrameWindowFor]): the spans the window reaches, and 0 where
/// there is no window — two breadths with one reach give one window.
int timelineFrameWindowReachFor({
  required double viewportExtent,
  required double cellExtent,
}) => viewportExtent <= 0 || cellExtent <= 0
    ? 0
    : _spansReached(cellExtent, viewportExtent);

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
  return frameWindowAtBucket(
    bucket.value,
    viewportMainExtent: viewportMainExtent,
    cellExtent: cellExtent,
    frames: (
      startIndex: frameStartIndex,
      endIndexExclusive: frameEndIndexExclusive,
    ),
  );
}

/// The window a painter draws while the offset stands in [bucket]
/// ([timelineFrameWindowFor]), clipped to its [frames] — the one a scroll
/// there gives it ([visibleFrameWindowFor]).
({int startIndex, int endIndexExclusive}) frameWindowAtBucket(
  int bucket, {
  required double viewportMainExtent,
  required double cellExtent,
  required ({int startIndex, int endIndexExclusive}) frames,
}) {
  final window = timelineFrameWindowFor(
    bucket: bucket,
    cellExtent: cellExtent,
    viewportExtent: viewportMainExtent,
  );
  return (
    startIndex: math.max(frames.startIndex, window.startIndex),
    endIndexExclusive: math.min(
      frames.endIndexExclusive,
      window.endIndexExclusive,
    ),
  );
}

/// Where a run's next page turn stands a frame axis: the bucket its windows
/// are cut by there ([frameWindowAtBucket]), and the frames the axis is
/// built for there — where a row's spans end
/// ([TimelineFrameAxisFollower.nextPage]).
typedef TimelineNextPage = ({int bucket, int builtFrames});

/// Whether [frame] lies in [window] — what every playhead-driven layer asks
/// before it marks a frame: the body's cursor, the ruler's tint and the
/// playhead's writing (I-16). One answer, so the three cannot mark
/// different frames.
bool frameWindowContains(
  ({int startIndex, int endIndexExclusive}) window,
  int frame,
) => frame >= window.startIndex && frame < window.endIndexExclusive;

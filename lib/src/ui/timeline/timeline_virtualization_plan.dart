import 'dart:math' as math;

import 'timeline_frame_coordinate_policy.dart' show timelineFrameEdge;
import 'timeline_visible_range.dart';

/// Calculation-only render plan for a future virtualized timeline viewport.
///
/// The plan preserves full scroll geometry through leading/trailing spacer
/// dimensions while exposing only the frame and layer ranges that should be
/// rendered by a viewport-aware UI.
class TimelineVirtualizationPlan {
  const TimelineVirtualizationPlan({
    required this.frameRange,
    required this.layerRange,
    required this.leadingFrameSpacerWidth,
    required this.trailingFrameSpacerWidth,
    required this.leadingLayerSpacerHeight,
    required this.trailingLayerSpacerHeight,
    required this.totalFrameContentWidth,
    required this.totalLayerContentHeight,
    required this.visibleFrameContentWidth,
    required this.visibleLayerContentHeight,
  });

  /// Visible frame index range for the horizontal timeline axis.
  final TimelineVisibleRange frameRange;

  /// Visible layer index range for the vertical timeline axis.
  final TimelineVisibleRange layerRange;

  /// Width before [frameRange] in the full virtual frame content.
  final double leadingFrameSpacerWidth;

  /// Width after [frameRange] in the full virtual frame content.
  final double trailingFrameSpacerWidth;

  /// Height before [layerRange] in the full virtual layer content.
  final double leadingLayerSpacerHeight;

  /// Height after [layerRange] in the full virtual layer content.
  final double trailingLayerSpacerHeight;

  /// Total virtual width represented by all timeline frames.
  final double totalFrameContentWidth;

  /// Total virtual height represented by all timeline layers.
  final double totalLayerContentHeight;

  /// Width represented by the visible frame range only.
  final double visibleFrameContentWidth;

  /// Height represented by the visible layer range only.
  final double visibleLayerContentHeight;

  @override
  bool operator ==(Object other) {
    return other is TimelineVirtualizationPlan &&
        other.frameRange == frameRange &&
        other.layerRange == layerRange &&
        other.leadingFrameSpacerWidth == leadingFrameSpacerWidth &&
        other.trailingFrameSpacerWidth == trailingFrameSpacerWidth &&
        other.leadingLayerSpacerHeight == leadingLayerSpacerHeight &&
        other.trailingLayerSpacerHeight == trailingLayerSpacerHeight &&
        other.totalFrameContentWidth == totalFrameContentWidth &&
        other.totalLayerContentHeight == totalLayerContentHeight &&
        other.visibleFrameContentWidth == visibleFrameContentWidth &&
        other.visibleLayerContentHeight == visibleLayerContentHeight;
  }

  @override
  int get hashCode => Object.hash(
    frameRange,
    layerRange,
    leadingFrameSpacerWidth,
    trailingFrameSpacerWidth,
    leadingLayerSpacerHeight,
    trailingLayerSpacerHeight,
    totalFrameContentWidth,
    totalLayerContentHeight,
    visibleFrameContentWidth,
    visibleLayerContentHeight,
  );

  @override
  String toString() {
    return 'TimelineVirtualizationPlan('
        'frameRange: $frameRange, '
        'layerRange: $layerRange, '
        'leadingFrameSpacerWidth: $leadingFrameSpacerWidth, '
        'trailingFrameSpacerWidth: $trailingFrameSpacerWidth, '
        'leadingLayerSpacerHeight: $leadingLayerSpacerHeight, '
        'trailingLayerSpacerHeight: $trailingLayerSpacerHeight, '
        'totalFrameContentWidth: $totalFrameContentWidth, '
        'totalLayerContentHeight: $totalLayerContentHeight, '
        'visibleFrameContentWidth: $visibleFrameContentWidth, '
        'visibleLayerContentHeight: $visibleLayerContentHeight)';
  }
}

/// Calculates the virtualized timeline render plan for both timeline axes.
///
/// This is pure Dart calculation logic. It does not build widgets and does not
/// depend on project domain models.
TimelineVirtualizationPlan calculateTimelineVirtualizationPlan({
  required double horizontalScrollOffset,
  required double verticalScrollOffset,
  required double viewportWidth,
  required double viewportHeight,
  required double frameCellWidth,
  required double layerRowHeight,
  required int frameCount,
  required int layerCount,
  int frameOverscanBefore = 2,
  int frameOverscanAfter = 2,
  int layerOverscanBefore = 2,
  int layerOverscanAfter = 2,
}) {
  final ranges = calculateTimelineVisibleRanges(
    horizontalScrollOffset: horizontalScrollOffset,
    verticalScrollOffset: verticalScrollOffset,
    viewportWidth: viewportWidth,
    viewportHeight: viewportHeight,
    frameCellWidth: frameCellWidth,
    layerRowHeight: layerRowHeight,
    frameCount: frameCount,
    layerCount: layerCount,
    frameOverscanBefore: frameOverscanBefore,
    frameOverscanAfter: frameOverscanAfter,
    layerOverscanBefore: layerOverscanBefore,
    layerOverscanAfter: layerOverscanAfter,
  );

  final safeFrameCount = math.max(0, frameCount);
  final safeLayerCount = math.max(0, layerCount);
  // The frame axis' boundaries, by its one law — a spacer is the stretch up
  // to a boundary, so the rendered frames land where the law puts them.
  double edge(int frame) => timelineFrameEdge(frame, frameCellWidth);
  final totalFrameContentWidth = edge(safeFrameCount);
  final totalLayerContentHeight = safeLayerCount * layerRowHeight;

  return TimelineVirtualizationPlan(
    frameRange: ranges.frames,
    layerRange: ranges.layers,
    leadingFrameSpacerWidth: math.max(0.0, edge(ranges.frames.startIndex)),
    trailingFrameSpacerWidth: math.max(
      0.0,
      totalFrameContentWidth - edge(ranges.frames.endIndexExclusive),
    ),
    leadingLayerSpacerHeight: math.max(
      0.0,
      ranges.layers.startIndex * layerRowHeight,
    ),
    trailingLayerSpacerHeight: math.max(
      0.0,
      (safeLayerCount - ranges.layers.endIndexExclusive) * layerRowHeight,
    ),
    totalFrameContentWidth: totalFrameContentWidth,
    totalLayerContentHeight: totalLayerContentHeight,
    visibleFrameContentWidth: math.max(
      0.0,
      edge(ranges.frames.endIndexExclusive) - edge(ranges.frames.startIndex),
    ),
    visibleLayerContentHeight: math.max(
      0.0,
      ranges.layers.count * layerRowHeight,
    ),
  );
}

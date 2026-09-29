import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'timeline_frame_coordinate_policy.dart' show frameVisibleX;
import 'timeline_grid_metrics.dart';

/// The playhead tint color, exported so tests can assert against it —
/// a LIVE accent read (UI-R22 #5).
Color get timelinePlayheadColor => AppColors.accent;

class TimelinePlayhead extends StatelessWidget {
  const TimelinePlayhead({
    super.key = const ValueKey<String>('timeline-playhead'),
    required this.currentFrameIndex,
    required this.frameStartIndex,
    required this.frameEndIndexExclusive,
    required this.leadingFrameSpacerWidth,
    required this.metrics,
    required this.layerCount,
    this.crossAxisExtent,
    this.axis = Axis.horizontal,
  });

  final int currentFrameIndex;
  final int frameStartIndex;
  final int frameEndIndexExclusive;
  final double leadingFrameSpacerWidth;
  final TimelineGridMetrics metrics;
  final int layerCount;

  /// Explicit cross-axis extent (rows are no longer uniformly tall once a
  /// section collapses to its slim strip); falls back to the uniform
  /// [layerCount]-based height.
  final double? crossAxisExtent;

  /// The frame axis direction: a column tint in the horizontal timeline, a
  /// row tint in the X-sheet. The offset math is shared.
  final Axis axis;

  bool get _isCurrentFrameBuilt {
    return currentFrameIndex >= frameStartIndex &&
        currentFrameIndex < frameEndIndexExclusive;
  }

  double get _mainAxisOffset => _edge(currentFrameIndex);

  /// The current cell's extent along the axis, by the same law.
  double get _mainAxisExtent =>
      _edge(currentFrameIndex + 1) - _edge(currentFrameIndex);

  double _edge(int frame) => frameVisibleX(
    frameIndex: frame,
    frameStartIndex: frameStartIndex,
    frameCellWidth: metrics.frameCellWidth,
    leadingFrameSpacerWidth: leadingFrameSpacerWidth,
  );

  double get _height {
    return crossAxisExtent ??
        metrics.layerRowHeight * (1 + (layerCount > 0 ? layerCount : 1));
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCurrentFrameBuilt) {
      return const SizedBox.shrink();
    }

    final playheadColor = timelinePlayheadColor;

    if (axis == Axis.vertical) {
      return IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              top: _mainAxisOffset,
              left: 0,
              right: 0,
              child: Container(
                key: const ValueKey<String>('timeline-playhead-column'),
                height: _mainAxisExtent,
                color: playheadColor.withValues(alpha: 0.18),
              ),
            ),
          ],
        ),
      );
    }

    return IgnorePointer(
      child: SizedBox(
        height: _height,
        child: Stack(
          children: [
            Positioned(
              left: _mainAxisOffset,
              top: 0,
              bottom: 0,
              child: Container(
                key: const ValueKey<String>('timeline-playhead-column'),
                width: _mainAxisExtent,
                color: playheadColor.withValues(alpha: 0.18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

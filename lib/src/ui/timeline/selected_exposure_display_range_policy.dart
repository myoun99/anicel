/// Resolves the selected exposure outline visual range for timeline rendering.
///
/// This policy is display-range based: it intentionally does not accept
/// `playbackFrameCount`, `Cut.duration`, or
/// `cutAuthoredExtent`. It resolves the selected exposure block
/// and clamps only the visible intersection needed for rendering in the current
/// virtualized frame window.
///
/// Do not use this policy as a timeline data extent. Its result is a visual
/// display effect only and must not imply that timeline data exists, or should
/// be created, deleted, or resized, across the outlined span.

library;

import 'dart:math' as math;

import 'timeline_cell_exposure_state.dart';
import 'timeline_exposure_range_resolver.dart';

class SelectedExposureDisplayRange {
  const SelectedExposureDisplayRange({
    required this.resolvedRange,
    required this.visibleStartFrameIndex,
    required this.visibleEndFrameIndexExclusive,
  });

  final TimelineExposureRange resolvedRange;
  final int visibleStartFrameIndex;
  final int visibleEndFrameIndexExclusive;

  bool get hasVisibleIntersection =>
      visibleStartFrameIndex < visibleEndFrameIndexExclusive;
}

SelectedExposureDisplayRange resolveSelectedExposureDisplayRange({
  required bool active,
  required int currentFrameIndex,
  required int frameStartIndex,
  required int frameEndIndexExclusive,
  required TimelineCellExposureState Function(int frameIndex) exposureStateAt,
}) {
  if (!active) {
    return const SelectedExposureDisplayRange(
      resolvedRange: TimelineExposureRange(
        kind: TimelineExposureRangeKind.none,
        startFrameIndex: 0,
        endFrameIndexExclusive: 0,
        selectedFrameIndex: 0,
      ),
      visibleStartFrameIndex: 0,
      visibleEndFrameIndexExclusive: 0,
    );
  }

  final resolvedRange = resolveTimelineExposureRange(
    selectedFrameIndex: currentFrameIndex,
    minFrameIndex: 0,
    maxFrameIndexExclusive: math.max(
      frameEndIndexExclusive,
      currentFrameIndex + 1,
    ),
    exposureStateAt: exposureStateAt,
  );

  if (!resolvedRange.isBlock) {
    return SelectedExposureDisplayRange(
      resolvedRange: resolvedRange,
      visibleStartFrameIndex: 0,
      visibleEndFrameIndexExclusive: 0,
    );
  }

  final visibleStartFrameIndex = math.max(
    resolvedRange.startFrameIndex,
    frameStartIndex,
  );
  final visibleEndFrameIndexExclusive = math.min(
    resolvedRange.endFrameIndexExclusive,
    frameEndIndexExclusive,
  );

  return SelectedExposureDisplayRange(
    resolvedRange: resolvedRange,
    visibleStartFrameIndex: visibleStartFrameIndex,
    visibleEndFrameIndexExclusive: visibleEndFrameIndexExclusive,
  );
}

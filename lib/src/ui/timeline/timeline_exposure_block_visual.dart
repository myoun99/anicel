import 'package:flutter/material.dart';
import 'timeline_cell_style.dart';
import '../../models/frame.dart' show celNumberOf;
import '../../models/layer_kind.dart';
import 'timeline_cell_exposure_state.dart';

enum TimelineExposureBlockKind { none, drawing }

class TimelineExposureBlockVisualSegment {
  const TimelineExposureBlockVisualSegment({
    required this.kind,
    required this.continuesFromPrevious,
    required this.continuesToNext,
  });

  static const TimelineExposureBlockVisualSegment none =
      TimelineExposureBlockVisualSegment(
        kind: TimelineExposureBlockKind.none,
        continuesFromPrevious: false,
        continuesToNext: false,
      );

  final TimelineExposureBlockKind kind;
  final bool continuesFromPrevious;
  final bool continuesToNext;

  bool get isBlock => kind != TimelineExposureBlockKind.none;
}

/// How one cell participates in its drawing block's rounded visual: block
/// bodies are covered runs (start + holds + marks inside the hold); a new
/// drawing start always begins a fresh block even when glued to the
/// previous one.
TimelineExposureBlockVisualSegment calculateTimelineExposureBlockVisualSegment({
  required TimelineCellExposureState? previous,
  required TimelineCellExposureState current,
  required TimelineCellExposureState? next,
}) {
  if (!current.isCovered) {
    return TimelineExposureBlockVisualSegment.none;
  }

  return TimelineExposureBlockVisualSegment(
    kind: TimelineExposureBlockKind.drawing,
    continuesFromPrevious:
        current != TimelineCellExposureState.drawingStart &&
        (previous?.isCovered ?? false),
    continuesToNext:
        next != null &&
        next != TimelineCellExposureState.drawingStart &&
        next.isCovered,
  );
}

/// The state of the cell before [frameIndex], or null at the first cell —
/// the ONE place the "cell 0 has no previous" edge is written.
///
/// The painted rows (twice: the block segment and the empty-run start) and
/// the instance-edit preview each spelled it (the audit's clone scan,
/// 2026-09-06); the preview shows "exactly what the timeline will" only
/// while both read the same edge.
TimelineCellExposureState? timelineCellStateBefore({
  required int frameIndex,
  required TimelineCellExposureState Function(int frameIndex) stateAt,
}) => frameIndex == 0 ? null : stateAt(frameIndex - 1);

/// The block segment of the cell at [frameIndex], read from [stateAt] with
/// its two neighbours — [calculateTimelineExposureBlockVisualSegment] over
/// the neighbour window, the first cell having no previous.
TimelineExposureBlockVisualSegment timelineExposureBlockSegmentAt({
  required int frameIndex,
  required TimelineCellExposureState Function(int frameIndex) stateAt,
}) => calculateTimelineExposureBlockVisualSegment(
  previous: timelineCellStateBefore(frameIndex: frameIndex, stateAt: stateAt),
  current: stateAt(frameIndex),
  next: stateAt(frameIndex + 1),
);

/// What one timeline cell announces to a screen reader — null when it
/// announces nothing.
///
/// 🚨ONE SENTENCE, ONE PLACE. The widget rows (SE, camera, instruction)
/// and the PAINTED drawing rows both answer this, and they were answering
/// it in two identical spellings (the audit's clone scan, 2026-09-04). A
/// divergence there is a row that says something different depending on
/// which kind of row it is, which is exactly what a reader cannot see.
///
/// Instruction spans carry their own semantics on the row overlay, so a
/// band that is instructions-only announces nothing here.
String? timelineCellSemanticsLabel({
  required LayerKind layerKind,
  required TimelineCellExposureState exposureState,
  String? frameName,
}) {
  if (layerKind.bandIsInstructionsOnly) {
    return null;
  }
  return switch (exposureState) {
    TimelineCellExposureState.uncovered => null,
    TimelineCellExposureState.drawingStart
        when layerKind == LayerKind.camera =>
      'camera keyframe',
    TimelineCellExposureState.drawingStart =>
      switch (celNumberOf(frameName)) {
        null => 'drawing start',
        final celNumber => 'drawing start $celNumber',
      },
    TimelineCellExposureState.held => 'held exposure',
    TimelineCellExposureState.markHeld ||
    TimelineCellExposureState.markUncovered => 'inbetween mark',
  };
}

/// The corner a cell wears in a block run — null when the cell is not a
/// block at all.
///
/// 🚨ONE CORNER RULE, ONE PLACE. Like the label above, the widget rows and
/// the painted rows each carried this, and they had already started to
/// drift: one read the named radius, the other spelled the number 6 in
/// place, so moving the constant would have rounded one kind of row and
/// not the other.
///
/// ⛔And the radius is the block corner LAW, not the bare constant
/// ([timelineBlockCornerRadiusAt]). The bare 6 left the tiles' rasterizer
/// clamping it to half a cell on its own while the classic pass and the
/// widget cells drew it whole — so below a 12px cell the same block wore a
/// 6px round until its tile arrived and a 4px one after.
BorderRadius? timelineCellBorderRadius(
  TimelineExposureBlockVisualSegment segment,
  Axis axis, {
  required double cellExtent,
  required double crossExtent,
}) {
  if (!segment.isBlock) {
    return null;
  }
  final corner = timelineBlockCornerRadiusAt(
    cellExtent: cellExtent,
    crossExtent: crossExtent,
  );
  final startRadius = segment.continuesFromPrevious ? Radius.zero : corner;
  final endRadius = segment.continuesToNext ? Radius.zero : corner;
  return switch (axis) {
    Axis.horizontal => BorderRadius.horizontal(
      left: startRadius,
      right: endRadius,
    ),
    Axis.vertical => BorderRadius.vertical(top: startRadius, bottom: endRadius),
  };
}

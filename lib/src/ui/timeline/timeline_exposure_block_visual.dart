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

import '../../models/layer.dart';
import '../../models/timeline_coverage.dart'
    show coveringDrawingBlockAt, hasBreakdownDotAt;

/// What one timeline cell shows under the unified timeline model.
///
/// `uncovered` cells are empty timesheet cells (rendered with the "X"
/// glyph on cel layers); marks keep the visual of the space they sit in
/// (block body or empty cell) plus the ● glyph, and never form blocks.
enum TimelineCellExposureState {
  uncovered,
  drawingStart,
  held,
  markHeld,
  markUncovered;

  /// Part of a drawing block's covered run (start, hold, or a mark inside
  /// the hold).
  bool get isCovered =>
      this == TimelineCellExposureState.drawingStart ||
      this == TimelineCellExposureState.held ||
      this == TimelineCellExposureState.markHeld;

  bool get isMark =>
      this == TimelineCellExposureState.markHeld ||
      this == TimelineCellExposureState.markUncovered;
}

/// Whether an empty run STARTS at a cell in [current] state, given the
/// [previous] cell's state (null at frame 0). Japanese timesheets mark only
/// the first cell of each empty run with the X glyph; a mark inside the run
/// continues it rather than starting a new one.
bool timelineEmptyRunStartsAt({
  required TimelineCellExposureState current,
  TimelineCellExposureState? previous,
}) {
  if (current != TimelineCellExposureState.uncovered) {
    return false;
  }
  return previous == null || previous.isCovered;
}

/// What a cell of [layer]'s OWN blocks shows at [frameIndex], read off the
/// row alone: a block's first cell, a cell it holds — with the in-between
/// dot the block carries there — or nothing.
///
/// THE reading for every row whose cells are its own blocks. The session
/// asks it for a cut's rows once a folder's band and the camera's keys have
/// answered for themselves (`ExposureVerbs.exposureStateForLayer`), and the
/// storyboard's conte row asks it of a row no session holds — the cuts'
/// conte layers laid on the track's axis (I-73).
///
/// ↩️The session spelled it out of three timeline-controller questions,
/// which made the answer the session's to give: a row drawn outside a cut
/// had nobody to ask.
TimelineCellExposureState timelineOwnCelsStateAt(Layer layer, int frameIndex) {
  if (frameIndex < 0) {
    return TimelineCellExposureState.uncovered;
  }
  if (layer.timeline[frameIndex]?.isDrawing ?? false) {
    return TimelineCellExposureState.drawingStart;
  }
  if (coveringDrawingBlockAt(layer.timeline, frameIndex) == null) {
    return TimelineCellExposureState.uncovered;
  }
  // Block-owned dots live on held cells only (offsets 1..length-1), so
  // markUncovered is never produced anymore — the enum value survives
  // solely for exhaustive switches over legacy-visual states.
  return hasBreakdownDotAt(layer.timeline, frameIndex)
      ? TimelineCellExposureState.markHeld
      : TimelineCellExposureState.held;
}

/// The name of the cel [layer]'s own block shows at [frameIndex] — the
/// block covering it — or null where none covers it or the cel is unnamed.
/// [timelineOwnCelsStateAt]'s twin, for the same rows.
String? timelineOwnCelNameAt(Layer layer, int frameIndex) {
  if (frameIndex < 0) {
    return null;
  }
  final cel = coveringDrawingBlockAt(layer.timeline, frameIndex)?.frameId;
  return cel == null ? null : layer.frameById(cel)?.name;
}

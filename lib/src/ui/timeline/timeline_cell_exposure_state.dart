import '../../models/frame.dart' show InbetweenMark;
import '../../models/layer.dart';
import '../../models/timeline_coverage.dart'
    show breakdownMarkAt, coveringDrawingBlockAt;

/// What one timeline cell shows under the unified timeline model.
///
/// `uncovered` cells are empty timesheet cells (rendered with the "X"
/// glyph on cel layers); a held cell carrying a block's in-between dot
/// keeps the block's paper and wears the dot's mark ([mark]).
///
/// ↩️A `markUncovered` stood beside them for the free-floating dots the
/// block-owned ones retired (UI-R9 #8); nothing made it any more.
enum TimelineCellExposureState {
  uncovered,
  drawingStart,
  held,

  /// A held cell whose dot wears mark 1, the hollow ○ (I-130).
  markOneHeld,

  /// A held cell whose dot wears mark 2, the filled ●.
  markTwoHeld;

  /// A held cell carrying [mark].
  static TimelineCellExposureState markHeld(InbetweenMark mark) =>
      switch (mark) {
        InbetweenMark.one => markOneHeld,
        InbetweenMark.two => markTwoHeld,
      };

  /// The in-between mark the cell wears, or null.
  InbetweenMark? get mark => switch (this) {
    markOneHeld => InbetweenMark.one,
    markTwoHeld => InbetweenMark.two,
    uncovered || drawingStart || held => null,
  };

  /// Part of a drawing block's covered run (start, hold, or a mark inside
  /// the hold).
  bool get isCovered => this != TimelineCellExposureState.uncovered;

  bool get isMark => mark != null;
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
  if (layer.timeline[frameIndex]?.isDrawing ?? false) {
    return TimelineCellExposureState.drawingStart;
  }
  if (coveringDrawingBlockAt(layer.timeline, frameIndex) == null) {
    return TimelineCellExposureState.uncovered;
  }
  // Block-owned dots live on held cells only (offsets 1..length-1).
  return switch (breakdownMarkAt(layer.timeline, frameIndex)) {
    final mark? => TimelineCellExposureState.markHeld(mark),
    null => TimelineCellExposureState.held,
  };
}

/// The name of the cel [layer]'s own block shows at [frameIndex] — the
/// block covering it — or null where none covers it or the cel is unnamed.
/// [timelineOwnCelsStateAt]'s twin, for the same rows.
String? timelineOwnCelNameAt(Layer layer, int frameIndex) {
  final cel = coveringDrawingBlockAt(layer.timeline, frameIndex)?.frameId;
  return cel == null ? null : layer.frameById(cel)?.name;
}

import '../../models/cut_id.dart';
import '../../models/timeline_row_address.dart';
import '../../models/track_id.dart';
import 'session_roles.dart';
import 'project_settings.dart';

/// The STORYBOARD ROWS — the rail rows it shows, the cut selection swept
/// across them, and the next cut in storyboard order — as their own
/// object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). It names the roles it needs in its constructor.
///
/// ⛔It holds NO row of its own. WHERE THE USER STANDS on the rail is the
/// third of [Standing]'s panel rows, beside the verb row and the
/// timeline's — parked here it made [Standing] and this object need each
/// other to be built at all (G0-2, 2026-09-06).
class StoryboardRows {
  StoryboardRows({
    required ProjectAccess project,
    required SelectionAccess selection,
    required TimelineAccess timeline,
    required ProjectSettings projectSettings,
  }) : _project = project,
       _selection = selection,
       _timeline = timeline,
       _projectSettings = projectSettings;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final TimelineAccess _timeline;
  final ProjectSettings _projectSettings;

  /// The cut after [cutId] in storyboard order, or null at the end.
  CutId? nextCutIdInStoryboardOrder(CutId cutId) {
    final layout = _projectSettings.projectLayout();
    for (var index = 0; index < layout.length; index += 1) {
      if (layout[index].cutId == cutId) {
        return index + 1 < layout.length ? layout[index + 1].cutId : null;
      }
    }
    return null;
  }

  /// The cuts the storyboard selection covers — DERIVED from the range, in
  /// track order.
  List<CutId> get storyboardSelectedCutIds {
    final selection = _selection.trackFrameRangeSelection.value;
    if (selection == null ||
        !selection.coversRow(TrackRowAddress(selection.trackId))) {
      return const [];
    }
    return _timeline
        .axisForTrack(selection.trackId)
        .cutsIn(selection.startFrame, selection.endFrameExclusive);
  }

  /// The storyboard rail's rows for [trackId], in the order the panel
  /// stacks them: the SE rows top-down (highest slot first — slot 0 sits
  /// just above the cut row), then the CUT row at the bottom.
  ///
  /// A range drag walks THIS list (feedback #14, the timeline's Excel-style
  /// cross-row select), so the list order IS the visual order — a positive
  /// row delta must mean "downward on screen". It used to lead with the
  /// cut row, which inverted every cross-row drag: dragging from an S row
  /// down toward the V row walked the list AWAY from it (the real-device
  /// "row-span select does nothing" report).
  ///
  /// Only track-GLOBAL rows are on it — the strip is a cut-owned row on
  /// the other axis, so it cannot be reached by a row delta, and the clamp
  /// below is therefore the whole of the kind guard (the row-move
  /// precedent: what is not on the list is unreachable, so there is
  /// nothing to refuse).
  List<TimelineRowAddress> storyboardRailRows(TrackId trackId) {
    final track = _project.trackById(trackId);
    return [
      // The TRANSITION row heads the group on screen, so it heads the list: a
      // row delta walks this in VISUAL order, and a row missing from it is
      // unreachable — which is what left a cross-row drag unable to start on
      // it or arrive at it (user 2026-08-11).
      if (track != null) LayerRowAddress(track.transitionLayer.id),
      if (track != null)
        for (final layer in track.seLayers.reversed) LayerRowAddress(layer.id),
      TrackRowAddress(trackId),
    ];
  }

  void clearStoryboardCutSelection() {
    if (_selection.trackFrameRangeSelection.value != null) {
      _selection.trackFrameRangeSelection.value = null;
    }
  }
}

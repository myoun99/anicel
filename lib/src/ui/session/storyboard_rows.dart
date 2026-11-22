import '../../models/cut_id.dart';
import '../../models/timeline_row_address.dart';
import '../../models/track_frame_range.dart';
import 'session_roles.dart';
import 'project_settings.dart';

/// The STORYBOARD ROWS — the cut selection swept across the rail, and the
/// next cut in storyboard order — as their own object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). It names the roles it needs in its constructor.
///
/// ⛔It holds NO row of its own. WHERE THE USER STANDS on the rail is the
/// third of [Standing]'s panel rows, beside the verb row and the
/// timeline's — parked here it made [Standing] and this object need each
/// other to be built at all (G0-2, 2026-09-06). ↩️Nor does it list the
/// rail's rows any more: a sweep's rows are the ones the panel draws.
class StoryboardRows {
  StoryboardRows({
    required SelectionAccess selection,
    required ProjectSettings projectSettings,
  }) : _selection = selection,
       _projectSettings = projectSettings;

  final SelectionAccess _selection;
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

  /// The storyboard selection where it is swept over its track's CUT ROW —
  /// null where there is none, or it covers other rows only. Empty space on
  /// that row is selected as its cuts are: what it says is where the
  /// selection is, and [storyboardSelectedCutIds] which cuts it holds.
  TrackFrameRangeSelection? get cutRowSelection {
    final selection = _selection.trackFrameRangeSelection.value;
    return selection != null &&
            selection.coversRow(TrackRowAddress(selection.trackId))
        ? selection
        : null;
  }

  /// The cuts the storyboard selection covers — DERIVED from the range, in
  /// track order.
  List<CutId> get storyboardSelectedCutIds {
    final selection = cutRowSelection;
    if (selection == null) {
      return const [];
    }
    return _projectSettings
        .axisForTrack(selection.trackId)
        .cutsIn(selection.startFrame, selection.endFrameExclusive);
  }

  void clearStoryboardCutSelection() {
    if (_selection.trackFrameRangeSelection.value != null) {
      _selection.trackFrameRangeSelection.value = null;
    }
  }
}

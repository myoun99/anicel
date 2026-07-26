import '../models/cut_id.dart';
import '../models/project.dart';
import '../models/track_id.dart';
import 'active_cut_helpers.dart';

class EditingSessionState {
  EditingSessionState({required CutId? activeCutId, TrackId? selectedTrackId})
    : _activeCutId = activeCutId,
      _selectedTrackId = selectedTrackId;

  factory EditingSessionState.forProject(Project project) {
    final activeCutId = defaultActiveCutIdFor(project);
    return EditingSessionState(
      activeCutId: activeCutId,
      selectedTrackId: trackIdOfCut(project, activeCutId),
    );
  }

  /// NULL = the editing playhead stands in a track GAP (UI-R9 #3): no cut
  /// is selected — the timeline/timesheet show their empty states and the
  /// canvas shows the void. Playback FOLLOW keeps the last cut through
  /// gaps; only editing seeks/scrub commits land here.
  CutId? _activeCutId;

  CutId? get activeCutId => _activeCutId;

  void setActiveCutId(CutId? cutId) {
    _activeCutId = cutId;
  }

  /// The SELECTED track — first-class state, the way the timeline's row
  /// selection is. It used to be DERIVED by hunting for whichever track
  /// owned the active cut, which meant it had nowhere to live whenever the
  /// playhead parked in a gap ([activeCutId] null) and the selection
  /// evaporated. The session reconciles the pair: an active cut still wins
  /// while there IS one, so the answer is identical to the old derivation,
  /// and this is what survives when there is not.
  TrackId? _selectedTrackId;

  TrackId? get selectedTrackId => _selectedTrackId;

  void setSelectedTrackId(TrackId? trackId) {
    _selectedTrackId = trackId;
  }
}

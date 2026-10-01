import '../../models/cut_id.dart';
import 'session_roles.dart';

/// The storyboard V row's EYES (R9): the cuts whose PICTURE the playback
/// display hides. The paper stays, the composite doesn't draw. A working
/// aid: the editing canvas, exports and thumbnails ignore it.
///
/// Its own object — the last state the session kept for itself (the
/// session-state audit's twenty-third family, 2026-09-29). Hiding and
/// showing move the playhead too, so it asks the session's seeks: a
/// global select through the selection role, and [park], the one park
/// there is (`parkGlobalFrame`), handed in because no role carries it.
class CutPictureEyes {
  CutPictureEyes({
    required SelectionAccess selection,
    required TimelineAccess timeline,
    required ChangeSink changes,
    required void Function(int globalFrame) park,
  }) : _selection = selection,
       _timeline = timeline,
       _changes = changes,
       _park = park;

  final SelectionAccess _selection;
  final TimelineAccess _timeline;
  final ChangeSink _changes;
  final void Function(int globalFrame) _park;

  final Set<CutId> _hidden = {};

  bool showsPicture(CutId cutId) => !_hidden.contains(cutId);

  void toggle(CutId cutId) {
    final editing = _timeline.editingSession;
    if (!_hidden.remove(cutId)) {
      _hidden.add(cutId);
      // UI-R13 #2: hiding the ACTIVE cut's picture is the no-cut state —
      // nothing displays at this index anymore, exactly like a gap
      // landing: park at the current global — the one park there is.
      if (cutId == editing.activeCutId) {
        _park(_selection.editingGlobalFrame);
      }
      _changes.notifyChanged();
      return;
    }
    // Re-showing (UI-R14 #2): the symmetric restore — when the playhead
    // is parked ON the re-shown cut (the eye-off gap state), turning the
    // eye back on lands there again, exactly as if the position were
    // clicked. Without this the picture only returned in playback while
    // the editing view stayed in the void.
    final parked = editing.gapGlobalFrame;
    if (parked != null &&
        editing.activeCutId == null &&
        _timeline.trackFrameAxis().ownerOf(parked)?.cutId == cutId) {
      _selection.selectGlobalFrame(parked);
      return; // selectGlobalFrame notifies.
    }
    _changes.notifyChanged();
  }
}

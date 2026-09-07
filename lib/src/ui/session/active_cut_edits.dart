import '../../models/cut_id.dart';
import 'session_roles.dart';

/// THE ACTIVE-CUT ENVELOPE — "the cut you are standing on, or nothing".
///
/// Thirteen verbs across five collaborators read the active cut id, stand
/// down when it is null (the gap state, UI-R9 #3), run one coordinator
/// call and then tell the session. Only the coordinator call differed, so
/// only the coordinator call is passed in.
///
/// ⛔ONE MOVE, WITH A SIGN. The two verbs used to be written out, guard
/// and command and refresh each, so a step that stopped refreshing after
/// the reorder would have done it in one direction only.
/// (`CutVerbs._moveActiveCut`'s own argument, and the reason this object
/// exists: thirteen hand-written envelopes are thirteen chances to lose
/// the tail in one of them.)
class ActiveCutEdits {
  ActiveCutEdits({
    required TimelineAccess timeline,
    required ChangeSink changes,
  }) : _timeline = timeline,
       _changes = changes;

  final TimelineAccess _timeline;
  final ChangeSink _changes;

  /// Runs [command] on the active cut and rebuilds after it: the cut's
  /// STRUCTURE may have moved (rows, frames, canvas), so the controllers
  /// have to be re-read before anyone paints.
  void onActiveCut(void Function(CutId cutId) command) =>
      onActiveCutQuietly((cutId) {
        command(cutId);
        _changes.refreshAfterCutCommand();
      });

  /// The same envelope for an edit that changes a row's ATTRIBUTES and
  /// not the shape of the cut — a mark, an effect chain. Nothing to
  /// rebuild; the repaint is the whole of the reaction.
  void onActiveCutQuietly(void Function(CutId cutId) command) {
    final cutId = _timeline.editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    command(cutId);
    _changes.notifyChanged();
  }
}

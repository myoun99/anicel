import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import 'session_roles.dart';

/// THE ACTIVE-CUT ENVELOPE — "the cut you are standing on, or nothing".
///
/// Eighteen verbs across seven collaborators read the active cut id, stand
/// down when it is null (the gap state, UI-R9 #3), run one coordinator
/// call and then tell the session. Only the coordinator call differed, so
/// only the coordinator call is passed in.
///
/// ⛔ONE MOVE, WITH A SIGN. The two verbs used to be written out, guard
/// and command and refresh each, so a step that stopped refreshing after
/// the reorder would have done it in one direction only.
/// (`CutVerbs._moveActiveCut`'s own argument, and the reason this object
/// exists: eighteen hand-written envelopes are eighteen chances to lose
/// the tail in one of them.)
///
/// 🚨THE CUT ID IS READ IN ONE PLACE HERE — [onActiveCutQuietly]. The
/// row-scoped arm rides it too, so "which cut am I on" cannot come to
/// have two answers inside one envelope.
class ActiveCutEdits {
  ActiveCutEdits({
    required SelectionAccess selection,
    required TimelineAccess timeline,
    required ChangeSink changes,
  }) : _selection = selection,
       _timeline = timeline,
       _changes = changes;

  final SelectionAccess _selection;
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

  /// The ACTIVE-ROW arm: refuse unless the verb's own gate says yes, take
  /// the ACTIVE row's id, run one coordinator command keyed by
  /// (cut, layer), then refresh KEEPING THAT ROW ACTIVE and notify.
  ///
  /// Four verbs across two collaborators wrote it out by hand — 링크 복제,
  /// 링크 해제, 폴더 생성, 공정 폴더 생성. What differs between them is a bool
  /// getter and a two-argument command, and both are values.
  ///
  /// ⚠️The trailing step is the one that goes missing when an envelope is
  /// copied: `CutVerbs._moveActiveCut` carries a comment recording exactly
  /// that loss. It has one writer now.
  void onActiveLayer({
    required bool when,
    required void Function(CutId cutId, LayerId layerId) command,
  }) {
    if (!when) {
      return;
    }
    // A non-null active layer implies an active cut (the gap state has no
    // rows at all), which every one of these gates already establishes.
    final layerId = _selection.activeLayer!.id;
    onActiveCutQuietly((cutId) {
      command(cutId, layerId);
      _changes.refreshAfterCutCommand(preferredActiveLayerId: layerId);
    });
  }
}

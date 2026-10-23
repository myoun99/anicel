import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../../services/project_lookup.dart' show cutWritingRow;
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
/// (the cut left/right verbs' own argument — gone since F-455 took their
/// buttons away — and the reason this object exists: eighteen
/// hand-written envelopes are eighteen chances to lose the tail in one of
/// them.)
///
/// 🚨THE CUT ID IS READ IN ONE PLACE HERE — [_standingCutId]. The
/// row-scoped arms ride it too, so "which cut am I on" cannot come to
/// have two answers inside one envelope.
class ActiveCutEdits {
  ActiveCutEdits({
    required ProjectAccess project,
    required SelectionAccess selection,
    required TimelineAccess timeline,
    required ChangeSink changes,
  }) : _project = project,
       _selection = selection,
       _timeline = timeline,
       _changes = changes;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final TimelineAccess _timeline;
  final ChangeSink _changes;

  /// Runs [command] on the active cut and rebuilds after it: the cut's
  /// STRUCTURE may have moved (rows, frames, canvas), so the controllers
  /// have to be re-read before anyone paints.
  void onActiveCut(void Function(CutId cutId) command) =>
      onActiveCutQuietly(_rebuilding(command));

  /// The same envelope for an edit that changes a row's ATTRIBUTES and
  /// not the shape of the cut — a mark, an effect chain. Nothing to
  /// rebuild; the repaint is the whole of the reaction.
  void onActiveCutQuietly(void Function(CutId cutId) command) =>
      _onCutQuietly(_standingCutId, command);

  /// What a step on the active cut will make, worked out [ahead] of it: no
  /// change yet, so nothing to rebuild or tell ([onActiveCut] takes the
  /// step).
  Future<void> aheadOfActiveCut(Future<void> Function(CutId cutId) ahead) {
    final cutId = _standingCutId;
    return cutId == null ? Future<void>.value() : ahead(cutId);
  }

  /// [onActiveCut] for an edit of ONE ROW: in the cut writing it
  /// ([cutOfRow]) — a camera's track (I-89-Q23).
  void onCutOfRow(LayerId row, void Function(CutId cutId) command) =>
      onCutOfRowQuietly(row, _rebuilding(command));

  /// [onActiveCutQuietly] for an edit of ONE ROW's attributes, addressed in
  /// the cut writing it ([cutOfRow]).
  ///
  /// A rail that draws one row for every cut presses it wherever the
  /// session stands, a gap included — the storyboard's conte head (I-73).
  /// The row is some cut's whatever is active, and that cut is where its
  /// link group and its seat are found. ↩️Every row verb was addressed in
  /// the active cut, and stood down in a gap with it.
  void onCutOfRowQuietly(LayerId row, void Function(CutId cutId) command) =>
      _onCutQuietly(cutOfRow(row), command);

  /// The cut an edit of [row] is written in ([cutWritingRow]): the cut that
  /// HOLDS it, stood in or not, and the active one where none holds it — a
  /// track's own row. ↩️Its callers looked the holder up themselves.
  CutId? cutOfRow(LayerId row) => cutWritingRow(
    _project.repository.requireProject(),
    row,
    standing: _standingCutId,
  );

  CutId? get _standingCutId => _timeline.editingSession.activeCutId;

  /// [command], and the rebuild [onActiveCut] says why.
  void Function(CutId cutId) _rebuilding(void Function(CutId cutId) command) =>
      (cutId) {
        command(cutId);
        _changes.refreshAfterCutCommand();
      };

  void _onCutQuietly(CutId? cutId, void Function(CutId cutId) command) {
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
  /// getter and a two-argument command, and both are values. (↩️The two
  /// link verbs have left since — I-25, I-77 — and the two folder verbs
  /// are what it serves.)
  ///
  /// ⚠️The trailing step is the one that goes missing when an envelope is
  /// copied: the cut left/right verbs (gone since F-455) carried a comment
  /// recording exactly that loss. It has one writer now.
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

import 'drags/cut_move_drag.dart';
import '../../models/cut_id.dart';
import 'session_roles.dart';
import 'storyboard_rows.dart';

/// A CUT BEING DRAGGED ALONG ITS TRACK — begun, moved by a cumulative
/// delta, and ended or cancelled — as its own object, like every other
/// drag the session hosts.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP
/// cut, Round 6, 2026-09-03). Measured before cutting: one field of its
/// own and the four verbs that are its only readers. It names the roles
/// it needs in its constructor.
class CutMoveDragVerbs {
  CutMoveDragVerbs({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required SessionInternals internals,
    required StoryboardRows storyboardRows,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _internals = internals,
       _storyboardRows = storyboardRows;

  final StoryboardRows _storyboardRows;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final SessionInternals _internals;

  /// The in-flight whole-block move ([CutMoveDrag]), or null. The move's
  /// own doc — re-time vs reorder, the contiguous-run rule — lives on the
  /// drag class.
  CutMoveDrag? _cutMoveDrag;

  bool beginCutMoveDrag(CutId cutId) {
    final drag = CutMoveDrag.begin(
      cutId: cutId,
      tracks: _project.repository.requireProject().tracks,
      selectedCutIds: _storyboardRows.storyboardSelectedCutIds,
      preview: _internals.dragPreview,
      selection: _selection.trackFrameRangeSelection.value,
      publishSelection: (selection) =>
          _selection.trackFrameRangeSelection.value = selection,
      commitOrder:
          ({
            required trackId,
            required order,
            required beforeGaps,
            required afterGaps,
          }) {
            _project.cutCommandCoordinator.commitCutMoveReorder(
              trackId: trackId,
              order: order,
              beforeGaps: beforeGaps,
              afterGaps: afterGaps,
            );
            _changes.refreshAfterCutCommand();
            _changes.notifyChanged();
          },
      commitGaps: ({required beforeGaps, required afterGaps}) {
        _project.cutCommandCoordinator.commitCutDurationDrag(
          beforeDurations: const {},
          afterDurations: const {},
          beforeGaps: beforeGaps,
          afterGaps: afterGaps,
        );
        _changes.refreshAfterCutCommand();
        _changes.notifyChanged();
      },
    );
    if (drag == null) {
      // A refused grip leaves an in-flight drag exactly as it was.
      return false;
    }
    _cutMoveDrag = drag;
    return true;
  }

  void updateCutMoveDrag(int cumulativeDelta) =>
      _cutMoveDrag?.update(cumulativeDelta);

  void endCutMoveDrag() {
    _cutMoveDrag?.commit();
    _cutMoveDrag = null;
  }

  /// Drops an in-flight move preview without touching history.
  void cancelCutMoveDrag() {
    _cutMoveDrag?.cancel();
    _cutMoveDrag = null;
  }
}

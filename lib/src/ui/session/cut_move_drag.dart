part of '../editor_session_manager.dart';

/// A CUT BEING DRAGGED ALONG ITS TRACK — begun, moved by a cumulative
/// delta, and ended or cancelled — as its own object, like every other
/// drag the session hosts.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP
/// cut, Round 6, 2026-09-03). Measured before cutting: one field of its
/// own and the four verbs that are its only readers. It reaches the
/// session through `_session`.
class _CutMoveDragVerbs {
  _CutMoveDragVerbs(this._session);

  final EditorSessionManager _session;

  /// The in-flight whole-block move ([CutMoveDrag]), or null. The move's
  /// own doc — re-time vs reorder, the contiguous-run rule — lives on the
  /// drag class.
  CutMoveDrag? _cutMoveDrag;

  bool beginCutMoveDrag(CutId cutId) {
    final drag = CutMoveDrag.begin(
      cutId: cutId,
      tracks: _session.repository.requireProject().tracks,
      selectedCutIds: _session.storyboardSelectedCutIds,
      preview: _session.dragPreview,
      selection: _session.trackFrameRangeSelection.value,
      publishSelection: (selection) =>
          _session.trackFrameRangeSelection.value = selection,
      commitOrder:
          ({
            required trackId,
            required order,
            required beforeGaps,
            required afterGaps,
          }) {
            _session.cutCommandCoordinator.commitCutMoveReorder(
              trackId: trackId,
              order: order,
              beforeGaps: beforeGaps,
              afterGaps: afterGaps,
            );
            _session.refreshAfterCutCommand();
            _session.notifyChanged();
          },
      commitGaps: ({required beforeGaps, required afterGaps}) {
        _session.cutCommandCoordinator.commitCutDurationDrag(
          beforeDurations: const {},
          afterDurations: const {},
          beforeGaps: beforeGaps,
          afterGaps: afterGaps,
        );
        _session.refreshAfterCutCommand();
        _session.notifyChanged();
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

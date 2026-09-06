part of '../editor_session_manager.dart';

/// The RUN FRAMES ADD DRAG — dragging the end of a run to add frames to
/// it — as its own object: the drag in flight and its steps.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Dry-run before cutting: one field of its own, and the
/// rest reads none of it.
class _RunFramesAddDrag {
  _RunFramesAddDrag(this._session);

  final EditorSessionManager _session;

  /// The in-flight "+ add frames" drag ([RunFramesAddDrag]), or null. The
  /// deterministic id reservation that keeps preview == commit lives on
  /// the drag class.
  RunFramesAddDrag? _runFramesAddDrag;

  /// Starts a "+ add frames" drag at the run edge (UI-R8): [atEnd] picks
  /// the side. Returns false when the row stands down or there is no run.
  bool beginRunFramesAddDrag({
    required LayerId layerId,
    required int blockStartIndex,
    required bool atEnd,
  }) {
    final drag = RunFramesAddDrag.begin(
      layerId: layerId,
      blockStartIndex: blockStartIndex,
      atEnd: atEnd,
      blockMoveEligible: _session._blockMoveEligible,
      layerById: _session.layerById,
      tracksNow: () => _session.repository.requireProject().tracks,
      activeCutFrameCount: () => _session.activeCutFrameCount,
      preview: _session.dragPreview,
      commitLayerDrag: ({required before, required after}) {
        _session.timelineController.commitLayerTimelineDrag(
          before: before,
          after: after,
        );
        _session.warmActiveCut();
        _session.notifyChanged();
      },
    );
    if (drag == null) {
      // A refused grip leaves an in-flight drag exactly as it was.
      return false;
    }
    _runFramesAddDrag = drag;
    return true;
  }

  void updateRunFramesAddDrag(int count) => _runFramesAddDrag?.update(count);

  void endRunFramesAddDrag() {
    _runFramesAddDrag?.commit();
    _runFramesAddDrag = null;
  }

  void cancelRunFramesAddDrag() {
    _runFramesAddDrag?.cancel();
    _runFramesAddDrag = null;
  }
}

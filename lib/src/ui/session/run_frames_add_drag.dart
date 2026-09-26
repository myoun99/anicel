import 'drags/run_frames_add_drag.dart';
import '../../models/layer_id.dart';
import 'active_cut_controllers.dart';
import 'session_roles.dart';

/// The RUN FRAMES ADD DRAG — dragging the end of a run to add frames to
/// it — as its own object: the drag in flight and its steps.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Dry-run before cutting: one field of its own, and the
/// rest reads none of it.
class RunFramesAddDragVerbs {
  RunFramesAddDragVerbs({
    required ProjectAccess project,
    required ChangeSink changes,
    required ActiveCutControllers controllers,
    required SessionInternals internals,
  }) : _project = project,
       _changes = changes,
       _controllers = controllers,
       _internals = internals;

  final ProjectAccess _project;
  final ChangeSink _changes;
  final ActiveCutControllers _controllers;
  final SessionInternals _internals;

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
      blockMoveEligible: _internals.blockMoveEligible,
      layerById: _project.layerById,
      activeCutFrameCount: () => _project.activeCutFrameCount,
      preview: _internals.dragPreview,
      commitLayerDrag: ({required before, required after}) {
        _controllers.timelineController.commitLayerTimelineDrag(
          before: before,
          after: after,
        );
        _changes.warmActiveCut();
        _changes.notifyChanged();
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

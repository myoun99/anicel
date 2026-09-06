import 'drags/drawing_block_move_drag.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/drawing_block_move.dart';
import 'session_roles.dart';
import 'folders_and_attachments.dart';

/// The DRAWING BLOCK MOVE DRAG — picking up a drawing block and landing
/// it elsewhere on its row — as its own object: the steps of it and the
/// landing. The preview the grid paints stays on the session.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Dry-run before cutting: the rest reads none of it.
class DrawingBlockMoveDragVerbs {
  DrawingBlockMoveDragVerbs({
    required ProjectAccess project,
    required ChangeSink changes,
    required TimelineAccess timeline,
    required SessionInternals internals,
    required FoldersAndAttachments folders,
  }) : _project = project,
       _changes = changes,
       _timeline = timeline,
       _internals = internals,
       _folders = folders;

  final ProjectAccess _project;
  final ChangeSink _changes;
  final TimelineAccess _timeline;
  final SessionInternals _internals;
  final FoldersAndAttachments _folders;

  /// Starts a whole-block move on the block starting at [blockStartIndex];
  /// returns false when there is no such block or the row stands down.
  bool beginDrawingBlockMoveDrag({
    required LayerId layerId,
    required int blockStartIndex,
  }) {
    // ⚠️Assigned only on SUCCESS. A refused begin must not touch a drag
    // already in flight — the first wiring of the session type overwrote
    // the slot with null and left a preview stuck in the channel.
    final drag = DrawingBlockMoveDrag.begin(
      layerId: layerId,
      blockStartIndex: blockStartIndex,
      layerById: _project.layerById,
      isEligibleRow: _internals.blockMoveEligible,
      noticeIneligible: _folders.noticeSyncedAttachRefusal,
      cutFrameCount: () => _project.activeCutFrameCount,
      preview: _internals.dragPreview,
      land: _landDrawingBlockMove,
    );
    if (drag == null) {
      return false;
    }
    _internals.blockMoveDrag = drag;
    return true;
  }

  /// The session's half of the block-move commit: one undo step built by
  /// the SHARED single-row builder, then the selection, the cache warm and
  /// the notify — all of which are this class's jobs, not the gesture's.
  void _landDrawingBlockMove(DrawingBlockMovePlan plan, Layer source) {
    _project.historyManager.execute(
      _internals.singleRowMoveCommand(
        plan,
        source: source,
        description: 'Move drawing block',
      ),
    );
    // The selection follows the block onto its new layer (R12-④): the
    // user grabbed THAT drawing — keep working on it where it landed.
    if (plan.isCrossLayer) {
      _timeline.layerController.selectLayer(plan.targetAfter!.id);
    }
    _changes.warmActiveCut();
    _changes.notifyChanged();
  }

  /// Applies the drag's cumulative deltas as a live preview on
  /// [_internals.dragPreview] (repository untouched). [targetLayerId] is the layer row
  /// currently under the pointer (null or the source id = plain slide).
  /// Blocks in the way are pushed in the direction of travel (R12-②) and
  /// ride the preview live; the rare still-illegal landing (mark collision,
  /// ineligible row, linked cel) clears the preview — the block shows at
  /// its committed spot until the pointer reaches a legal one.
  void updateDrawingBlockMoveDrag({
    required int frameDelta,
    LayerId? targetLayerId,
  }) => _internals.blockMoveDrag?.update(
    frameDelta: frameDelta,
    targetLayerId: targetLayerId,
  );

  /// Commits the move as a single undo step (no-op when the drag ends on
  /// an illegal or unchanged landing). Cross-layer moves compose the two
  /// layer updates with the brush-store rekey so undo restores everything.
  void endDrawingBlockMoveDrag() {
    // ⚠️Forgotten BEFORE the commit runs, so neither closer can be reached
    // twice and the landing cannot see a drag that is already over.
    final drag = _internals.blockMoveDrag;
    _internals.blockMoveDrag = null;
    drag?.commit();
  }

  /// Drops an in-flight move preview without touching history.
  void cancelDrawingBlockMoveDrag() {
    final drag = _internals.blockMoveDrag;
    _internals.blockMoveDrag = null;
    drag?.cancel();
  }
}

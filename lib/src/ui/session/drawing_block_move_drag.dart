part of '../editor_session_manager.dart';

/// The DRAWING BLOCK MOVE DRAG — picking up a drawing block and landing
/// it elsewhere on its row — as its own object: the steps of it and the
/// landing. The preview the grid paints stays on the session.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Dry-run before cutting: the rest reads none of it.
class _DrawingBlockMoveDrag {
  _DrawingBlockMoveDrag(this._session);

  final EditorSessionManager _session;

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
      layerById: _session.layerById,
      isEligibleRow: _session._blockMoveEligible,
      noticeIneligible: _session._folders._noticeSyncedAttachRefusal,
      cutFrameCount: () => _session.activeCutFrameCount,
      preview: _session.dragPreview,
      land: _landDrawingBlockMove,
    );
    if (drag == null) {
      return false;
    }
    _session._blockMoveDrag = drag;
    return true;
  }

  /// The session's half of the block-move commit: one undo step built by
  /// the SHARED single-row builder, then the selection, the cache warm and
  /// the notify — all of which are this class's jobs, not the gesture's.
  void _landDrawingBlockMove(DrawingBlockMovePlan plan, Layer source) {
    _session.historyManager.execute(
      _session._singleRowMoveCommand(
        plan,
        source: source,
        description: 'Move drawing block',
      ),
    );
    // The selection follows the block onto its new layer (R12-④): the
    // user grabbed THAT drawing — keep working on it where it landed.
    if (plan.isCrossLayer) {
      _session.layerController.selectLayer(plan.targetAfter!.id);
    }
    _session.warmActiveCut();
    _session.notifyChanged();
  }

  /// Applies the drag's cumulative deltas as a live preview on
  /// [_session.dragPreview] (repository untouched). [targetLayerId] is the layer row
  /// currently under the pointer (null or the source id = plain slide).
  /// Blocks in the way are pushed in the direction of travel (R12-②) and
  /// ride the preview live; the rare still-illegal landing (mark collision,
  /// ineligible row, linked cel) clears the preview — the block shows at
  /// its committed spot until the pointer reaches a legal one.
  void updateDrawingBlockMoveDrag({
    required int frameDelta,
    LayerId? targetLayerId,
  }) => _session._blockMoveDrag?.update(
    frameDelta: frameDelta,
    targetLayerId: targetLayerId,
  );

  /// Commits the move as a single undo step (no-op when the drag ends on
  /// an illegal or unchanged landing). Cross-layer moves compose the two
  /// layer updates with the brush-store rekey so undo restores everything.
  void endDrawingBlockMoveDrag() {
    // ⚠️Forgotten BEFORE the commit runs, so neither closer can be reached
    // twice and the landing cannot see a drag that is already over.
    final drag = _session._blockMoveDrag;
    _session._blockMoveDrag = null;
    drag?.commit();
  }

  /// Drops an in-flight move preview without touching history.
  void cancelDrawingBlockMoveDrag() {
    final drag = _session._blockMoveDrag;
    _session._blockMoveDrag = null;
    drag?.cancel();
  }
}

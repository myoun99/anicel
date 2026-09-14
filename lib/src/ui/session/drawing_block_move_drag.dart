import 'drags/drawing_block_move_drag.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/drawing_block_move.dart';
import '../../services/command.dart';
import '../../services/commands/rekey_brush_frames_command.dart';
import '../../services/commands/update_layer_timeline_command.dart';
import '../../models/timeline_repeat.dart';
import 'active_cut_controllers.dart';
import 'session_roles.dart';
import 'folders_and_attachments.dart';
import 'render_caches.dart';

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
    required ActiveCutControllers controllers,
    required SessionInternals internals,
    required FoldersAndAttachments folders,
    required RenderCaches renderCaches,
  }) : _project = project,
       _changes = changes,
       _controllers = controllers,
       _internals = internals,
       _folders = folders,
       _renderCaches = renderCaches;

  final ProjectAccess _project;
  final ChangeSink _changes;
  final ActiveCutControllers _controllers;
  final SessionInternals _internals;
  final FoldersAndAttachments _folders;
  final RenderCaches _renderCaches;

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
      bankOf: _controllers.timelineController.bankLanesOf,
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
      singleRowMoveCommand(
        plan,
        source: source,
        description: 'Move drawing block',
      ),
    );
    // The selection follows the block onto its new layer (R12-④): the
    // user grabbed THAT drawing — keep working on it where it landed.
    if (plan.isCrossLayer) {
      _controllers.layerController.selectLayer(plan.targetAfter!.id);
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


  /// The single undo step a ONE-ROW move lands as: the source row's
  /// rewrite, the target row's rewrite when the move crossed rows, and the
  /// brush-frame rekey that carries the cels across with it.
  ///
  /// The drawing-block drag and the frame-range drag both land exactly
  /// this way — same plan type, same three pieces, same collapse to a bare
  /// command when there is only one. They differed in the undo LABEL and
  /// nothing else, so that is all this takes. (The multi-row rigid move is
  /// a different shape: SE row pairs, instruction and camera riders, and a
  /// rekey list built from the plan instead of the moved frame ids.)

  Command singleRowMoveCommand(
    DrawingBlockMovePlan plan, {
    required Layer source,
    required String description,
  }) {
    final commands = <Command>[
      UpdateLayerTimelineCommand(
        repository: _project.repository,
        before: source,
        after: rederiveRunBehaviors(
          plan.sourceAfter,
          cutFrameCount: _project.activeCutFrameCount,
        ),
      ),
      if (plan.targetBefore != null)
        UpdateLayerTimelineCommand(
          repository: _project.repository,
          before: plan.targetBefore!,
          after: rederiveRunBehaviors(
            plan.targetAfter!,
            cutFrameCount: _project.activeCutFrameCount,
          ),
        ),
    ];
    if (plan.isCrossLayer && plan.movedFrameIds.isNotEmpty) {
      final cut = _project.requireActiveCut;
      commands.add(
        RekeyBrushFramesCommand(
          store: _renderCaches.brushFrameStore,
          pairs: [
            for (final frameId in plan.movedFrameIds)
              (
                _internals.brushFrameKeyForCut(cut, source.id, frameId),
                _internals.brushFrameKeyForCut(cut, plan.targetAfter!.id, frameId),
              ),
          ],
        ),
      );
    }
    return commands.length == 1
        ? commands.single
        : CompositeCommand(description: description, commands: commands);
  }
}

import '../timeline/timeline_drag_preview.dart' show BlockMoveDragPreview;
import '../../models/cel_rekey.dart';
import '../../models/cut.dart';
import '../../models/layer.dart';
import '../../models/drawing_block_move.dart';
import '../../services/command.dart';
import '../../services/commands/move_cel_pictures_command.dart';
import '../../services/commands/rekey_brush_frames_command.dart';
import '../../services/commands/update_layer_timeline_command.dart';
import '../../models/timeline_repeat.dart';
import 'session_roles.dart';
import 'pixel_editing.dart';
import 'render_caches.dart';

/// The undo steps a block MOVE lands by — the rows it rewrites, the brush
/// frames its cels carry across, the pictures that change cels — for the
/// one drag that moves blocks, the frame-range move.
///
/// ↩️This was the DRAWING BLOCK MOVE DRAG's collaborator, carved out of
/// `EditorSessionManager` (the audit's SRP cut, 2026-09-02): the drag that
/// picked a block up by its body, and these, which its landing shared with
/// the range move. UI-R8 (#517, 2026-07-16 — 「TVPaint 식 프레임 블록
/// 조작」) took the last press that started it: a block moves by being
/// selected and dragged as a range. Only tests drove it after that, so it
/// went (2026-10-24, card the-whole-block-drag-has-no-door) and what it
/// shared stayed.
class BlockMoveCommands {
  BlockMoveCommands({
    required ProjectAccess project,
    required RenderCaches renderCaches,
    required PixelEditing pixelEditing,
  }) : _project = project,
       _renderCaches = renderCaches,
       _pixelEditing = pixelEditing;

  final ProjectAccess _project;
  final RenderCaches _renderCaches;
  final PixelEditing _pixelEditing;

  /// The single undo step a ONE-ROW move lands as: the source row's
  /// rewrite, the target row's rewrite when the move crossed rows, and the
  /// brush-frame rekey that carries the cels across with it. (The multi-row
  /// rigid move is a different shape: SE row pairs, instruction and camera
  /// riders — its cels cross by [celRekeyCommand] all the same.)
  ///
  /// ↩️It took the undo LABEL: the drawing-block drag and the frame-range
  /// drag both landed exactly this way and differed in that and nothing
  /// else. One drag is left, so one label.
  Command singleRowMoveCommand(
    DrawingBlockMovePlan plan, {
    required Layer source,
  }) {
    final commands = <Command>[
      UpdateLayerTimelineCommand(
        repository: _project.repository,
        before: source,
        after: rederiveRunBehaviors(
          plan.sourceAfter,
          drawnFrameCount: _project.activeCutDrawnFrameCount,
        ),
      ),
      if (plan.targetBefore != null)
        UpdateLayerTimelineCommand(
          repository: _project.repository,
          before: plan.targetBefore!,
          after: rederiveRunBehaviors(
            plan.targetAfter!,
            drawnFrameCount: _project.activeCutDrawnFrameCount,
          ),
        ),
    ];
    if (plan.rekeys.isNotEmpty) {
      commands.add(celRekeyCommand(_project.requireActiveCut, plan.rekeys));
    }
    // Never empty: the source row's rewrite is always the first.
    return oneStepOf('Move frame range', commands)!;
  }

  /// The brush-frame rekey that carries [rekeys]' cels onto the rows they
  /// land on in [cut] — every move that carries cels across lands its
  /// pixels by it, from the list its drag showed them by
  /// ([BlockMoveDragPreview.rekeys]).
  RekeyBrushFramesCommand celRekeyCommand(Cut cut, List<CelRekey> rekeys) =>
      RekeyBrushFramesCommand(
        store: _renderCaches.brushFrameStore,
        pairs: [
          for (final rekey in rekeys)
            (
              _project.brushFrameKeyForCut(cut, rekey.from, rekey.frameId),
              _project.brushFrameKeyForCut(cut, rekey.to, rekey.frameId),
            ),
        ],
      );

  /// What hangs [moves]' pictures in the cels of [cut] they go to, the cels
  /// staying (F-330) — from the list its drag showed them by
  /// ([BlockMoveDragPreview.picturesMoved]). Null while no canvas has built
  /// the editing coordinator, the one door a picture is written through.
  MoveCelPicturesCommand? pictureMoveCommand(
    Cut cut,
    List<CelPictureMove> moves,
  ) {
    final coordinator = _pixelEditing.coordinator;
    if (coordinator == null) {
      return null;
    }
    return MoveCelPicturesCommand(
      coordinator: coordinator,
      moves: [
        for (final move in moves)
          (
            _project.brushFrameKeyForCut(cut, move.fromRow, move.fromCel),
            _project.brushFrameKeyForCut(cut, move.toRow, move.toCel),
          ),
      ],
      cacheInvalidationSink: _renderCaches.cacheInvalidationHub,
    );
  }
}

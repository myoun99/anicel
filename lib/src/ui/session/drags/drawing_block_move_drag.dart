import 'package:flutter/foundation.dart';

import '../../../models/drawing_block_move.dart';
import '../../../models/layer.dart';
import '../../../models/layer_id.dart';
import '../../../models/timeline_repeat.dart';
import '../../timeline/timeline_drag_preview.dart';

/// The one-row drawing-block MOVE drag (R12-②).
///
/// A block slides along its own row, or crosses onto another eligible row
/// and takes its cels with it. Blocks in the way are pushed in the
/// direction of travel and ride the preview live; a still-illegal landing
/// (mark collision, ineligible row, linked cel) clears the preview, so the
/// block shows at its committed spot until the pointer reaches a legal one.
///
/// ⛔It does NOT sign [EditorDragSession]. That interface fixes the
/// lifecycle around ONE scalar, and this drag's input is two things — a
/// cumulative frame delta AND the row currently under the pointer. Widening
/// the interface to fit would be a design change made during a move, which
/// is the one thing the split brief forbids. `RowOrderDrag` set the
/// precedent: a family whose input is not a scalar moves as a plain class
/// wearing the same laws.
///
/// The laws it wears anyway: [begin] captures the BEFORE state and refuses
/// by returning null; [update] recomputes the after-state and publishes a
/// preview; [commit] lands at most one undo step from its OWN stored plan,
/// never from the preview channel; [cancel] drops the preview and touches
/// no history.
class DrawingBlockMoveDrag {
  DrawingBlockMoveDrag._({
    required Layer source,
    required int blockStart,
    required Layer? Function(LayerId layerId) layerById,
    required bool Function(LayerId layerId) isEligibleRow,
    required int Function() cutFrameCount,
    required ValueNotifier<TimelineDragPreview?> preview,
    required void Function(DrawingBlockMovePlan plan, Layer source) land,
  }) : _source = source,
       _blockStart = blockStart,
       _layerById = layerById,
       _isEligibleRow = isEligibleRow,
       _cutFrameCount = cutFrameCount,
       _preview = preview,
       _land = land;

  /// The row and block as they stood when the grip closed — the drag's own
  /// before-state, and what the commit's undo step restores to.
  final Layer _source;
  final int _blockStart;

  final Layer? Function(LayerId layerId) _layerById;
  final bool Function(LayerId layerId) _isEligibleRow;

  /// ⚠️A closure, not a captured int: the cut's length is what run
  /// behaviours are rederived against, and a drag outlives the frame it
  /// began on.
  final int Function() _cutFrameCount;

  final ValueNotifier<TimelineDragPreview?> _preview;

  /// Lands the move. ⛔The session keeps this half deliberately — building
  /// the undo step is SHARED with the frame-range move (same plan type,
  /// same three pieces), and history, layer selection and cache warming are
  /// the session's own jobs, not this gesture's.
  final void Function(DrawingBlockMovePlan plan, Layer source) _land;

  /// The last legal landing, or null while the pointer sits on one that is
  /// not. **The commit reads this, never the preview channel** — the
  /// preview is display, shared, and clearable by anyone.
  DrawingBlockMovePlan? _plan;

  /// Null when there is nothing to drag: no such row, no entry at the grip,
  /// or a GHOST repeat instance — those are derived, and their timing
  /// belongs to the region, not to a drag (UI-R8).
  ///
  /// ⚠️An ineligible row is a different refusal and says so out loud
  /// ([noticeIneligible]); the others are simply "nothing here".
  static DrawingBlockMoveDrag? begin({
    required LayerId layerId,
    required int blockStartIndex,
    required Layer? Function(LayerId layerId) layerById,
    required bool Function(LayerId layerId) isEligibleRow,
    required void Function(LayerId layerId) noticeIneligible,
    required int Function() cutFrameCount,
    required ValueNotifier<TimelineDragPreview?> preview,
    required void Function(DrawingBlockMovePlan plan, Layer source) land,
  }) {
    if (!isEligibleRow(layerId)) {
      noticeIneligible(layerId);
      return null;
    }
    final layer = layerById(layerId);
    final entry = layer?.timeline[blockStartIndex];
    if (layer == null || entry == null || !entry.isDrawing || entry.ghost) {
      return null;
    }
    return DrawingBlockMoveDrag._(
      source: layer,
      blockStart: blockStartIndex,
      layerById: layerById,
      isEligibleRow: isEligibleRow,
      cutFrameCount: cutFrameCount,
      preview: preview,
      land: land,
    );
  }

  /// Re-plans for the cumulative delta and the row under the pointer
  /// ([targetLayerId] null or the source's id = a plain slide), and
  /// publishes the result as a live preview. The repository is untouched.
  void update({required int frameDelta, LayerId? targetLayerId}) {
    Layer? target = _source;
    if (targetLayerId != null && targetLayerId != _source.id) {
      target = _isEligibleRow(targetLayerId) ? _layerById(targetLayerId) : null;
    }
    final frames = _cutFrameCount();
    final plan = target == null
        ? null
        : planDrawingBlockMove(
            source: _source,
            target: target,
            blockStartIndex: _blockStart,
            frameDelta: frameDelta,
            cutFrameCount: frames,
          );
    _plan = plan;
    // Ghosts follow the moved run LIVE (UI-R8 rederive on the preview).
    _preview.value = plan == null
        ? null
        : BlockMoveDragPreview(
            previewLayers: {
              plan.sourceAfter.id: rederiveRunBehaviors(
                plan.sourceAfter,
                cutFrameCount: frames,
              ),
              if (plan.targetAfter != null)
                plan.targetAfter!.id: rederiveRunBehaviors(
                  plan.targetAfter!,
                  cutFrameCount: frames,
                ),
            },
          );
  }

  /// Lands the move as a single undo step, or nothing when the drag ended
  /// on an illegal or unchanged landing. Clears the preview either way.
  void commit() {
    final plan = _plan;
    _plan = null;
    _preview.value = null;
    if (plan == null) {
      return;
    }
    _land(plan, _source);
  }

  /// Drops the preview; history is untouched.
  void cancel() {
    _plan = null;
    _preview.value = null;
  }
}

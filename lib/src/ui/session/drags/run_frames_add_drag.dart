import 'package:flutter/foundation.dart';

import '../../../models/frame_id.dart';
import '../../../models/layer.dart';
import '../../../models/layer_id.dart';
import '../../../models/timeline_repeat.dart';
import '../../../models/timeline_run_edit.dart';
import '../../../services/editing/run_id_mint.dart';
import '../../timeline/timeline_drag_preview.dart';
import 'editor_drag_session.dart';

/// The "+ add frames" drag at a run edge (UI-R8): its input is the COUNT of
/// new one-frame drawings at the edge, absolute like the audio slide's
/// offset (0 shows the committed state).
class RunFramesAddDrag implements EditorDragSession {
  RunFramesAddDrag._({
    required Layer before,
    required int blockStartIndex,
    required bool atEnd,
    required int Function() activeCutFrameCount,
    required ValueNotifier<TimelineDragPreview?> preview,
    required void Function({required Layer before, required Layer after})
    commitLayerDrag,
  }) : _before = before,
       _blockStart = blockStartIndex,
       _atEnd = atEnd,
       _activeCutFrameCount = activeCutFrameCount,
       _preview = preview,
       _commitLayerDrag = commitLayerDrag;

  /// Starts the drag at [layerId]'s run edge; null when the row stands
  /// down or there is no run — no object, no drag.
  static RunFramesAddDrag? begin({
    required LayerId layerId,
    required int blockStartIndex,
    required bool atEnd,
    required bool Function(LayerId) blockMoveEligible,
    required Layer? Function(LayerId) layerById,
    required int Function() activeCutFrameCount,
    required ValueNotifier<TimelineDragPreview?> preview,
    required void Function({required Layer before, required Layer after})
    commitLayerDrag,
  }) {
    if (!blockMoveEligible(layerId)) {
      return null;
    }
    final layer = layerById(layerId);
    if (layer == null || gluedRunAt(layer, blockStartIndex) == null) {
      return null;
    }
    return RunFramesAddDrag._(
      before: layer,
      blockStartIndex: blockStartIndex,
      atEnd: atEnd,
      activeCutFrameCount: activeCutFrameCount,
      preview: preview,
      commitLayerDrag: commitLayerDrag,
    );
  }

  final Layer _before;
  final int _blockStart;
  final bool _atEnd;

  /// The row as this drag would leave it; null while the count shows "no
  /// change". The commit reads THIS, never [_preview].
  Layer? _after;

  /// The ids reserved so far, in ordinal order — drag-scoped, discarded
  /// with the object.
  final List<FrameId> _reservedIds = [];

  /// The run-behavior fill boundary (hold/repeat edges fill to the cut
  /// end); read per update.
  final int Function() _activeCutFrameCount;

  final ValueNotifier<TimelineDragPreview?> _preview;

  /// The session's committer: ONE timeline drag through the controller,
  /// with the warm + notify epilogue behind it.
  final void Function({required Layer before, required Layer after})
  _commitLayerDrag;

  /// Reserves the drag's new frame ids, deterministically: the same ordinal
  /// always resolves the same id, so every preview step and the commit
  /// agree.
  ///
  /// 🚨From the RUN, not the project's first free `frame-N`: a drawing
  /// undone keeps its picture in the session under its id for the redo, and
  /// the next drag given that id showed it on a blank cel (card
  /// `undone-paste-reuses-ids`).
  FrameId _reservedNewFrameId(int ordinal) {
    while (_reservedIds.length <= ordinal) {
      _reservedIds.add(mintFrameId(_before.id));
    }
    return _reservedIds[ordinal];
  }

  /// Live preview: [count] new one-frame drawings at the run edge (0 shows
  /// the committed state).
  @override
  void update(int count) {
    if (count < 1) {
      _after = null;
      _preview.value = null;
      return;
    }
    final result = layerWithNewFramesAtRunEdge(
      _before,
      blockStartIndex: _blockStart,
      atEnd: _atEnd,
      count: count,
      frameIdAt: _reservedNewFrameId,
    );
    _after = result == null
        ? null
        : rederiveRunBehaviors(
            result.layer,
            cutFrameCount: _activeCutFrameCount(),
          );
    _preview.value = _after == null
        ? null
        : ExposureEdgeDragPreview(previewLayer: _after!);
  }

  /// Commits the added frames as ONE undo step.
  @override
  void commit() {
    final after = _after;
    _preview.value = null;
    if (after == null || after == _before) {
      return;
    }
    _commitLayerDrag(before: _before, after: after);
  }

  @override
  void cancel() {
    _preview.value = null;
  }
}

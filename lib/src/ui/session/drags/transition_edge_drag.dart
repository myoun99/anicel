import 'package:flutter/foundation.dart';

import '../../../models/camera_instruction.dart';
import '../../../models/layer.dart';
import '../../../models/layer_id.dart';
import '../../../models/timeline_coverage.dart' show TimelineBlockEdge;
import '../../timeline/instruction_span_editing.dart';
import 'editor_drag_session.dart';

/// The transition row's edge drag (the first [EditorDragSession]; the
/// section comment that used to introduce it in the session manager applies
/// unchanged).
///
/// The grip widget, the callback shape and the pure span edit are the
/// direction row's, unchanged. What differs is WHICH map the delta lands in
/// (the track's, on the global axis) and which command commits it — so this
/// is its own small verb rather than a branch inside the exposure drag,
/// whose commit writes CUT layers and whose bulk/ripple/cut-sync machinery
/// means nothing to a span that owns no cels.
class TransitionEdgeDrag implements EditorDragSession {
  TransitionEdgeDrag._({
    required Layer before,
    required int spanStartIndex,
    required TimelineBlockEdge edge,
    required ValueNotifier<Layer?> preview,
    required void Function(
      Map<int, InstructionEvent> instructions, {
      required String description,
    })
    commitInstructions,
  }) : _before = before,
       _spanStartIndex = spanStartIndex,
       _edge = edge,
       _preview = preview,
       _commitInstructions = commitInstructions;

  /// Grabs [edge] of the transition span starting at [spanStartIndex]
  /// (GLOBAL frame); null when no span starts there — no object, no drag.
  ///
  /// [layerId], when given, must BE [layer]'s id (the active track's
  /// transition row). Every verb here is active-track scoped (as
  /// `activeTrackTransitionSpans`, the sheet and the compositor all are), so
  /// a grip belonging to another track's row is refused rather than silently
  /// retiming this track's span. Pressing a row selects its track, which is
  /// how that grip becomes reachable.
  static TransitionEdgeDrag? begin({
    required Layer layer,
    required int spanStartIndex,
    required TimelineBlockEdge edge,
    LayerId? layerId,
    required ValueNotifier<Layer?> preview,
    required void Function(
      Map<int, InstructionEvent> instructions, {
      required String description,
    })
    commitInstructions,
  }) {
    if (layerId != null && layerId != layer.id) {
      return null;
    }
    if (!layer.instructions.containsKey(spanStartIndex)) {
      return null;
    }
    return TransitionEdgeDrag._(
      before: layer,
      spanStartIndex: spanStartIndex,
      edge: edge,
      preview: preview,
      commitInstructions: commitInstructions,
    );
  }

  final Layer _before;
  final int _spanStartIndex;
  final TimelineBlockEdge _edge;

  /// The row as this drag would leave it; null while the delta lands on "no
  /// change". The commit reads THIS, never [_preview].
  Layer? _after;

  /// The session's display channel (the strip renders it so the mark
  /// follows the hand instead of jumping on release) — published to,
  /// cleared by both closers, never read back.
  final ValueNotifier<Layer?> _preview;

  /// The row's own writer on the session ([updateTransitionInstructions]):
  /// one undo step, description and all.
  final void Function(
    Map<int, InstructionEvent> instructions, {
    required String description,
  })
  _commitInstructions;

  @override
  void update(int cumulativeDelta) {
    final next = instructionMapWithEdgeShifted(
      _before.instructions,
      spanStartIndex: _spanStartIndex,
      startEdge: _edge == TimelineBlockEdge.start,
      delta: cumulativeDelta,
    );
    _after = next == null ? null : _before.copyWith(instructions: next);
    _preview.value = _after;
  }

  /// Commits the drag as ONE undo step through the row's own writer.
  @override
  void commit() {
    final after = _after;
    _preview.value = null;
    if (after == null || after == _before) {
      return;
    }
    _commitInstructions(after.instructions, description: 'Resize transition');
  }

  @override
  void cancel() {
    _preview.value = null;
  }
}

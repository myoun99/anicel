import 'dart:collection';

import 'package:flutter/foundation.dart' show mapEquals;

import '../../models/block_run_lead_edge.dart';
import '../../models/block_run_move.dart';
import '../../models/camera_instruction.dart';

/// Pure edits on an instruction row's span map. Each returns the edited
/// map, or null when the edit changes nothing / is not possible — callers
/// commit non-null results as ONE undo step (UpdateLayerInstructionsCommand).

/// The span covering [frameIndex], as (startIndex, event); null on empty
/// cells.
MapEntry<int, InstructionEvent>? instructionSpanCovering(
  SplayTreeMap<int, InstructionEvent> instructions,
  int frameIndex,
) {
  final startIndex = instructions.lastKeyBefore(frameIndex + 1);
  if (startIndex == null) {
    return null;
  }
  final event = instructions[startIndex]!;
  if (frameIndex >= startIndex + event.length) {
    return null;
  }
  return MapEntry(startIndex, event);
}

/// Shifts one edge of the span starting at [spanStartIndex] by [delta]
/// frames. The END edge resizes the span (min length 1, clamped at the
/// next span's start). The START edge is a block's front edge
/// ([_withLeadEdgeShifted]).
SplayTreeMap<int, InstructionEvent>? instructionMapWithEdgeShifted(
  SplayTreeMap<int, InstructionEvent> instructions, {
  required int spanStartIndex,
  required bool startEdge,
  required int delta,
}) {
  final event = instructions[spanStartIndex];
  if (event == null || delta == 0) {
    return null;
  }
  if (startEdge) {
    return _withLeadEdgeShifted(instructions, spanStartIndex, delta);
  }
  final nextStart = instructions.firstKeyAfter(spanStartIndex);
  final maxLength = nextStart == null ? 1 << 20 : nextStart - spanStartIndex;
  final newLength = (event.length + delta).clamp(1, maxLength).toInt();
  if (newLength == event.length) {
    return null;
  }
  return SplayTreeMap<int, InstructionEvent>.of(instructions)
    ..[spanStartIndex] = event.copyWith(length: newLength);
}

/// The START edge of the span at [spanStartIndex] dragged [delta] frames by
/// the one rule every block's front edge follows ([planBlockRunLeadEdge]):
/// its end holds; drawn out, it spends the empty frames in front and then
/// the span it touches gives frames, down to one (I-21); pulled back past
/// its last frame, it sweeps on and every span it passes whole is gone
/// (I-179). Null when nothing moves.
///
/// ↩️The start used to stop at the previous span's end and at its own last
/// frame, "unlike cel blocks there is no ripple — instruction spans are
/// independent notes" (1c11b5685, an implementation choice). A front edge
/// is a block's: 「이건 블록을 사용하는거라면 모든것에 법 통일적용 … 그게
/// 이 앱의 규칙이니까」 (유저 2026-11-19, I-179).
SplayTreeMap<int, InstructionEvent>? _withLeadEdgeShifted(
  SplayTreeMap<int, InstructionEvent> instructions,
  int spanStartIndex,
  int delta,
) {
  final starts = instructions.keys.toList();
  final events = instructions.values.toList();
  final lengths = [for (final event in events) event.length];
  final gaps = leadingGapsOf(starts: starts, lengths: lengths);
  final layout = planBlockRunLeadEdge(
    slots: [
      for (var i = 0; i < events.length; i += 1)
        (leadingGap: gaps[i], length: lengths[i]),
    ],
    targetIndex: starts.indexOf(spanStartIndex),
    frameDelta: delta,
  );
  final newStarts = slotStartsOf([
    for (var i = 0; i < events.length; i += 1)
      (leadingGap: layout.leadingGaps[i], length: layout.lengths[i]),
  ]);
  final next = SplayTreeMap<int, InstructionEvent>.of({
    for (var i = 0; i < events.length; i += 1)
      if (layout.lengths[i] > 0)
        newStarts[i]: events[i].copyWith(length: layout.lengths[i]),
  });
  return mapEquals(next, instructions) ? null : next;
}

/// Places [event] at [startIndex] on an empty cell, clamping its length at
/// the next span; null when the cell is already covered.
SplayTreeMap<int, InstructionEvent>? instructionMapWithEventAdded(
  SplayTreeMap<int, InstructionEvent> instructions, {
  required int startIndex,
  required InstructionEvent event,
}) {
  if (startIndex < 0 ||
      instructionSpanCovering(instructions, startIndex) != null) {
    return null;
  }
  final nextStart = instructions.firstKeyAfter(startIndex);
  final maxLength = nextStart == null ? event.length : nextStart - startIndex;
  final next = SplayTreeMap<int, InstructionEvent>.of(instructions);
  next[startIndex] = event.copyWith(
    length: event.length.clamp(1, maxLength < 1 ? 1 : maxLength),
  );
  return next;
}

/// Replaces the event of the span starting at [spanStartIndex] (start and
/// length untouched); null when absent or unchanged.
SplayTreeMap<int, InstructionEvent>? instructionMapWithEventReplaced(
  SplayTreeMap<int, InstructionEvent> instructions, {
  required int spanStartIndex,
  required InstructionEvent event,
}) {
  final existing = instructions[spanStartIndex];
  if (existing == null) {
    return null;
  }
  final replacement = event.copyWith(length: existing.length);
  if (replacement == existing) {
    return null;
  }
  final next = SplayTreeMap<int, InstructionEvent>.of(instructions);
  next[spanStartIndex] = replacement;
  return next;
}

/// Removes the span starting at [spanStartIndex]; null when absent.
SplayTreeMap<int, InstructionEvent>? instructionMapWithEventRemoved(
  SplayTreeMap<int, InstructionEvent> instructions, {
  required int spanStartIndex,
}) {
  if (!instructions.containsKey(spanStartIndex)) {
    return null;
  }
  return SplayTreeMap<int, InstructionEvent>.of(instructions)
    ..remove(spanStartIndex);
}

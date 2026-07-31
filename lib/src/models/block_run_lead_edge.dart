/// The ONE rule a LEAD-edge drag follows, on either axis.
///
/// Dragging a block's front edge changes where the block STARTS and how
/// long it is, and leaves its END exactly where it was — the two changes
/// cancel at the back boundary. Everything after it therefore holds still,
/// not by a rule but by arithmetic.
///
/// What happens in FRONT is the rule, and it is the contact rule the frame
/// axis has always used ([planBlockRunMove]'s sibling in
/// `timeline_controller`'s `_shiftEdgeTimeline`): a block GLUED to the one
/// being dragged stays glued, so it translates wholesale — same length,
/// same internal commas — and the block glued to THAT one follows, all the
/// way to the head of the axis, which is where the emptiness ends up. A
/// SEPARATED predecessor holds its ground and lets its gap absorb the
/// move, giving way only when it would otherwise be overlapped.
///
/// So a lead-edge drag never destroys timing behind it and never destroys
/// timing in front of it — it moves ONE boundary and lets the head of the
/// film absorb the difference.
library;

import 'dart:math' as math;

import 'block_run_move.dart';

/// Where every slot sits after a lead-edge drag.
class BlockRunLeadEdgeLayout {
  const BlockRunLeadEdgeLayout({
    required this.leadingGaps,
    required this.lengths,
  });

  /// Each slot's leading gap after the drag, by original index. The FIRST
  /// slot's is the head of the axis — the frames the film begins empty.
  final List<int> leadingGaps;

  /// Each slot's length after the drag, by original index. Only the
  /// dragged slot's can differ from its input.
  final List<int> lengths;
}

/// Plans a drag of `slots[targetIndex]`'s LEAD edge by [frameDelta] frames
/// (positive shortens the block from the front).
///
/// [minLength] floors the dragged block; [frameDelta] is additionally
/// clamped so nothing lands before frame 0 — growing a block forward can
/// only consume the slack that actually exists ahead of it, and the head of
/// the axis is the wall.
BlockRunLeadEdgeLayout planBlockRunLeadEdge({
  required List<BlockMoveSlot> slots,
  required int targetIndex,
  required int frameDelta,
  int minLength = 1,
}) {
  assert(targetIndex >= 0 && targetIndex < slots.length, 'target must exist');

  // Absolute starts, so the contact questions read the way they read on
  // screen; the answer converts back to gaps at the end.
  final starts = <int>[];
  var cursor = 0;
  for (final slot in slots) {
    cursor += slot.leadingGap;
    starts.add(cursor);
    cursor += slot.length;
  }

  final target = slots[targetIndex];
  // Shrinking stops at the floor; growing stops at the head of the axis,
  // which is every gap from frame 0 up to this block.
  //
  // Both are floored at zero before they meet: a block ALREADY under the
  // floor (a cut shorter than the row it must tile, which a load or a
  // stale minimum can hand us) would otherwise make the shrink limit
  // negative and `clamp` throw on a lower bound above its upper.
  final maxShrink = math.max(0, target.length - minLength);
  final maxGrow = math.max(
    0,
    starts[targetIndex] - _occupiedBefore(slots, targetIndex),
  );
  final delta = frameDelta.clamp(-maxGrow, maxShrink);

  final newStarts = List<int>.of(starts);
  final lengths = [for (final slot in slots) slot.length];
  newStarts[targetIndex] = starts[targetIndex] + delta;
  lengths[targetIndex] = target.length - delta;

  // Walk BACKWARD from the target: glued predecessors ride the boundary,
  // separated ones hold until they would be overlapped. Followers are
  // absent from this loop on purpose — the target's end did not move.
  var nextOldStart = starts[targetIndex];
  var nextNewStart = newStarts[targetIndex];
  for (var i = targetIndex - 1; i >= 0; i -= 1) {
    final oldEnd = starts[i] + slots[i].length;
    var end = oldEnd == nextOldStart ? nextNewStart : oldEnd;
    if (end > nextNewStart) {
      end = nextNewStart;
    }
    newStarts[i] = end - slots[i].length;
    nextOldStart = starts[i];
    nextNewStart = newStarts[i];
  }

  final leadingGaps = <int>[];
  var previousEnd = 0;
  for (var i = 0; i < slots.length; i += 1) {
    leadingGaps.add(newStarts[i] - previousEnd);
    previousEnd = newStarts[i] + lengths[i];
  }
  return BlockRunLeadEdgeLayout(leadingGaps: leadingGaps, lengths: lengths);
}

/// How much of the axis before [index] is BLOCK rather than gap — the
/// floor a forward-growing lead edge cannot pass, because pushing past it
/// would put the head of the axis before frame 0.
int _occupiedBefore(List<BlockMoveSlot> slots, int index) {
  var occupied = 0;
  for (var i = 0; i < index; i += 1) {
    occupied += slots[i].length;
  }
  return occupied;
}

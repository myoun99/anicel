/// The ONE rule a LEAD-edge drag follows, on either axis.
///
/// Dragging a block's front edge changes where the block STARTS and how
/// long it is, and leaves its END exactly where it was — the two changes
/// cancel at the back boundary. Everything after it therefore holds still,
/// not by a rule but by arithmetic.
///
/// What happens in FRONT is the rule, and I-21 (유저 2026-09-12) reversed
/// it: 「프리미어 프로처럼 … 앞 블록의 **헤드 그대로 두고**, 그 블록이랑
/// 현재 블록이랑 코마를 조절해서 전체적으론 안움직이도록」.
///
/// ★EVERYTHING IN FRONT KEEPS ITS HEAD. The distance comes out of the
/// EMPTY SPACE first, and when that is spent, out of the glued
/// predecessor's own LENGTH — so the pair trades frames across the one
/// boundary the hand is holding and the film in front of it does not
/// move at all. This is Premiere's ROLLING edit, and like Premiere's it
/// simply STOPS at the limit: the predecessor floors at [minLength], the
/// same floor the dragged block has.
///
/// ↩️WHAT THIS REPLACED, so nobody restores it as a bug fix: the glued
/// predecessor used to TRANSLATE wholesale (same length, same internal
/// commas), dragging its own glued chain with it, and the difference
/// ended up as emptiness at the head of the axis. That rule is gone —
/// with heads pinned there is no backward ripple left to write.
///
/// A lead-edge drag still never destroys timing BEHIND it: the dragged
/// block's end never moves, so everything after it holds still by
/// arithmetic.
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
  final starts = slotStartsOf(slots);

  final target = slots[targetIndex];
  // Shrinking from the front stops at the dragged block's own floor.
  //
  // Floored at zero before the clamp: a block ALREADY under the floor (a
  // cut shorter than the row it must tile, which a load or a stale
  // minimum can hand us) would otherwise make the shrink limit negative
  // and `clamp` throw on a lower bound above its upper.
  final maxShrink = math.max(0, target.length - minLength);
  final maxGrow = _roomInFront(
    slots,
    targetIndex,
    starts: starts,
    minLength: minLength,
  );
  final delta = frameDelta.clamp(-maxGrow, maxShrink);

  final newStarts = List<int>.of(starts);
  final lengths = [for (final slot in slots) slot.length];
  newStarts[targetIndex] = starts[targetIndex] + delta;
  lengths[targetIndex] = target.length - delta;

  // ★THE ONE BOUNDARY. Whatever the gap in front cannot pay for comes out
  // of the predecessor's LENGTH — its head, and therefore everything in
  // front of it, never moves. `gap` is what the empty space absorbs;
  // `traded` is what the neighbour's exposure gives up (or takes back,
  // when the drag shortens this block and hands frames forward).
  if (targetIndex > 0) {
    final gap = slots[targetIndex].leadingGap;
    // ⛔ONLY A TOUCHING NEIGHBOUR TRADES. Growing forward spends the gap
    // first and only then asks the neighbour (`-delta - gap`); shrinking
    // from the front hands its frames to a neighbour it is GLUED to, and
    // to nobody when a gap already separates them — there the empty space
    // simply grows, which is the rule this axis always had for a
    // separated predecessor.
    final traded = delta < 0
        ? math.max(0, -delta - gap)
        : (gap == 0 ? -delta : 0);
    lengths[targetIndex - 1] = slots[targetIndex - 1].length - traded;
  }

  return BlockRunLeadEdgeLayout(
    leadingGaps: leadingGapsOf(starts: newStarts, lengths: lengths),
    lengths: lengths,
  );
}

/// How far the lead edge can travel FORWARD (a negative delta): the empty
/// space in front, plus the frames the glued predecessor can give up
/// before it would fall under [minLength].
///
/// ⛔NOT "every gap up to frame 0" any more (I-21). Heads are pinned now,
/// so nothing in front can be compacted to make room — only the immediate
/// neighbour trades, and only down to its own floor. The FIRST block has
/// no neighbour, so its room is simply the head of the axis.
int _roomInFront(
  List<BlockMoveSlot> slots,
  int index, {
  required List<int> starts,
  required int minLength,
}) {
  if (index == 0) {
    return math.max(0, starts[0]);
  }
  final gap = slots[index].leadingGap;
  final neighbourGives = math.max(0, slots[index - 1].length - minLength);
  return math.max(0, gap + neighbourGives);
}

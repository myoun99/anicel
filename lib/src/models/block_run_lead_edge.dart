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

/// What bounds a lead-edge drag: the floor every block it touches keeps,
/// and how many blocks in front it may trade with.
///
/// ★ONE VALUE BECAUSE IT IS ONE QUESTION — "how far may this go" — and the
/// two halves are never decided apart: the caller that knows the reach is
/// the caller that knows the floor.
typedef LeadEdgeLimits = ({int minLength, int reach});

const LeadEdgeLimits defaultLeadEdgeLimits = (minLength: 1, reach: 1);

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
/// [minLength] floors every block the drag touches — the dragged one and
/// the ones it trades with.
///
/// ★[reach] IS THE ONLY THING THE THREE CASES DISAGREE ABOUT (유저
/// 2026-09-12): how many blocks IN FRONT this edge may trade with.
///
///  * a plain grip reaches ONE — the block it touches (the default);
///  * a grip inside a range selection reaches every SELECTED block in
///    front of it — 「불도저로 쭉 미는 느낌」, each squeezed to one frame
///    in turn and the squeezed ones packed forward;
///  * the storyboard's first panel reaches into the CUT in front (its
///    last conte block, or the cut itself when it has none).
///
/// The travel stops at the head of the last block it may reach, which is
/// why the caller says how far rather than the rule guessing.
///
/// ★THE BOUNDARY WALKS FORWARD. Whatever the gap in front cannot pay for
/// comes out of the block in front — nearest first, each down to
/// [LeadEdgeLimits.minLength] before the next one is asked — and a block
/// that gave everything it had is PUSHED forward by whatever the one
/// ahead of it gives up next. Everything outside the reach keeps both its
/// head and its length, which is the wall the travel stops against.
///
/// ⛔A SEPARATED neighbour trades only on the way FORWARD: shrinking from
/// the front hands its frames to a block it is GLUED to, and to nobody
/// when a gap already lies between them — there the empty space simply
/// grows, which is the rule this axis always had.
BlockRunLeadEdgeLayout planBlockRunLeadEdge({
  required List<BlockMoveSlot> slots,
  required int targetIndex,
  required int frameDelta,
  LeadEdgeLimits limits = defaultLeadEdgeLimits,
}) {
  final minLength = limits.minLength;
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
    limits: limits,
  );
  final delta = frameDelta.clamp(-maxGrow, maxShrink);

  final newStarts = List<int>.of(starts);
  final lengths = [for (final slot in slots) slot.length];
  newStarts[targetIndex] = starts[targetIndex] + delta;
  lengths[targetIndex] = target.length - delta;

  // The walk itself; the law it follows is stated in the doc above.
  if (targetIndex > 0 && delta < 0) {
    _tradeForward(
      slots,
      (
        targetIndex: targetIndex,
        owed: -delta,
        limits: limits,
        starts: starts,
      ),
      newStarts: newStarts,
      lengths: lengths,
    );
  } else if (targetIndex > 0 && slots[targetIndex].leadingGap == 0) {
    // Shrinking against a block it touches: that one takes the frames back.
    lengths[targetIndex - 1] = slots[targetIndex - 1].length + delta;
  }

  return BlockRunLeadEdgeLayout(
    leadingGaps: leadingGapsOf(starts: newStarts, lengths: lengths),
    lengths: lengths,
  );
}

/// What a forward trade reads: which block is being dragged, how many
/// frames it is asking for, the limits it obeys and where every block sat
/// before the drag.
typedef _TradeInput = ({
  int targetIndex,
  int owed,
  LeadEdgeLimits limits,
  List<int> starts,
});

/// Takes [input.owed] frames out of the blocks in front — gaps first,
/// then lengths, nearest first, each down to the floor — and PACKS what
/// lies between the last block reached and the dragged edge, each keeping
/// whatever gap it has left. The head of the last block reached never
/// moves: that is the wall the travel stops against.
///
/// Writes through [newStarts] and [lengths]; the dragged block's own start
/// and length are settled here too, because where it ends up IS what the
/// blocks in front just gave.
void _tradeForward(
  List<BlockMoveSlot> slots,
  _TradeInput input, {
  required List<int> newStarts,
  required List<int> lengths,
}) {
  final targetIndex = input.targetIndex;
  final starts = input.starts;
  var owed = input.owed;
  var reached = targetIndex;
  // What each gap has LEFT once the drag spent its share: a spent gap must
  // not reappear in the packing below.
  final gapsLeft = [for (final slot in slots) slot.leadingGap];
  for (
    var i = targetIndex - 1;
    i >= 0 && targetIndex - i <= input.limits.reach;
    i -= 1
  ) {
    final spent = math.min(owed, slots[i + 1].leadingGap);
    gapsLeft[i + 1] = slots[i + 1].leadingGap - spent;
    owed -= spent;
    final gives = math.min(
      owed,
      math.max(0, slots[i].length - input.limits.minLength),
    );
    lengths[i] = slots[i].length - gives;
    owed -= gives;
    reached = i;
    if (owed == 0) {
      break;
    }
  }
  var cursor = starts[reached];
  for (var i = reached; i < targetIndex; i += 1) {
    newStarts[i] = cursor;
    cursor += lengths[i] + gapsLeft[i + 1];
  }
  final targetEnd = starts[targetIndex] + slots[targetIndex].length;
  newStarts[targetIndex] = cursor;
  lengths[targetIndex] = targetEnd - cursor;
}

/// How far the lead edge can travel FORWARD (a negative delta): the empty
/// space it crosses, plus the frames every block within [reach] can give
/// up before it would fall under [minLength].
///
/// ⛔NOT "every gap up to frame 0" (I-21): blocks outside the reach are
/// never compacted, so the wall is the head of the last block the drag may
/// touch. The FIRST block has nothing in front, so its room is the head of
/// the axis.
int _roomInFront(
  List<BlockMoveSlot> slots,
  int index, {
  required List<int> starts,
  required LeadEdgeLimits limits,
}) {
  if (index == 0) {
    return math.max(0, starts[0]);
  }
  var room = 0;
  for (var i = index - 1; i >= 0 && index - i <= limits.reach; i -= 1) {
    room += slots[i + 1].leadingGap;
    room += math.max(0, slots[i].length - limits.minLength);
  }
  return math.max(0, room);
}

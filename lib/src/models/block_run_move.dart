/// The ONE rule a block-run drag follows, on either axis.
///
/// A drag answers TWO questions, and it answers both every time. What
/// SEQUENCE does the release leave — the run's rank among the blocks it is
/// not part of, measured against the seats they hold in the ORIGINAL
/// layout? And WHERE in that sequence does the run sit — inside the free
/// space its new neighbours leave it, with the follower absorbing the
/// difference so everything past the run holds still?
///
/// Re-timing and reordering are therefore not two modes. A reorder is a
/// drag whose FIRST answer changed; it still has a second answer, and the
/// hand keeps its hold on the run once the sequence has flipped. Asking the
/// second question only when the rank HELD was a real bug: a run that had
/// just swapped stopped dead on its seat, so the empty frames past it were
/// unreachable for the rest of that drag, and from there on only the cursor
/// moved — which reads as "the swap is measured from where I started
/// dragging" (UI 피드백 08-14 #5, both halves of it).
///
/// Measuring the rank against ORIGINAL positions is what keeps the rule
/// stable — a rank read off previewed positions would chase itself, since
/// re-timing moves the very seats the next step compares to.
///
/// This started on the cut axis and the frame axis kept BULLDOZING — a
/// slide that shoved its neighbours along. They are the same motion on two
/// axes, so the rule lives here once, and the axes differ only in what a
/// slot is made of and what a landing commits to.
library;

/// One block as the move planner sees it: the empty space in front of it,
/// and its own length.
///
/// A cut's is its leading gap and its duration; a drawing block's is the
/// distance from the previous block's end (frame 0 for the first) and its
/// exposure length. Every block carrying its own leading space is what
/// lets "the commas never change" be one sentence on both axes.
typedef BlockMoveSlot = ({int leadingGap, int length});

/// Where every slot sits after the move.
class BlockRunMoveLayout {
  BlockRunMoveLayout({
    required List<BlockMoveSlot> slots,
    required this.order,
    required this.leadingGaps,
  }) : assert(
         order.length == leadingGaps.length,
         'Every slot in the new order needs its leading gap.',
       ),
       starts = _startsFor(slots, order, leadingGaps);

  /// The slots' ORIGINAL indices, in the order the release would leave.
  final List<int> order;

  /// Parallel to [order]: the leading gap of each POSITION after the move.
  /// The gaps belong to positions rather than to the blocks that arrive in
  /// them, so a permutation reads the same numbers in a new sequence; what
  /// a move can still change is the pair around the run, which trade the
  /// slack the run slid through.
  final List<int> leadingGaps;

  /// Parallel to [order]: the frame each slot starts on.
  final List<int> starts;

  /// Whether the sequence changed rather than only the timing.
  bool get isReorder {
    for (var position = 0; position < order.length; position += 1) {
      if (order[position] != position) {
        return true;
      }
    }
    return false;
  }

  /// Where the slot originally at [slotIndex] now starts.
  int startOf(int slotIndex) => starts[order.indexOf(slotIndex)];

  static List<int> _startsFor(
    List<BlockMoveSlot> slots,
    List<int> order,
    List<int> leadingGaps,
  ) {
    final starts = <int>[];
    var cursor = 0;
    for (var position = 0; position < order.length; position += 1) {
      cursor += leadingGaps[position];
      starts.add(cursor);
      cursor += slots[order[position]].length;
    }
    return starts;
  }
}

/// Plans a move of `slots[runStart..runEnd]` (inclusive, contiguous) by
/// [frameDelta] frames.
///
/// The run is clamped into the free space of whatever rank it lands at, so
/// a move never overlaps a neighbour and never pushes one: running out of
/// room means the run stops at contact, and reaching the seat BEYOND that
/// neighbour means the order changes — after which the run goes on being
/// clamped into the free space of the rank it just took. Pushing the
/// followers along was the old shove — that behaviour belongs to the
/// push/pull buttons, which take a scope, not to a drag.
///
/// [axisEndExclusive] is where the axis stops, for the axes that have an
/// end. The LAST slot is otherwise unbounded on the right — the cut axis
/// and an ordinary drawing row both want that, since a cut may run off the
/// end of the movie and a block may sit past the end of its cut. A row that
/// lives INSIDE something (the storyboard's, which tiles its cut) passes
/// that thing's end, and then a gapless row is rigid in both directions:
/// no free space anywhere, so every move it allows is a reorder.
BlockRunMoveLayout planBlockRunMove({
  required List<BlockMoveSlot> slots,
  required int runStart,
  required int runEnd,
  required int frameDelta,
  int? axisEndExclusive,
}) {
  final starts = <int>[];
  var cursor = 0;
  for (final slot in slots) {
    cursor += slot.leadingGap;
    starts.add(cursor);
    cursor += slot.length;
  }

  final runFrom = starts[runStart];
  final runTo = starts[runEnd] + slots[runEnd].length;
  final runLength = runTo - runFrom;
  final wanted = runFrom + frameDelta;

  // The blocks that are NOT moving, at the positions they hold throughout
  // the drag, plus the run's original rank among them.
  final rest = <({int index, int start, int endExclusive})>[];
  for (var index = 0; index < slots.length; index += 1) {
    if (index >= runStart && index <= runEnd) {
      continue;
    }
    rest.add((
      index: index,
      start: starts[index],
      endExclusive: starts[index] + slots[index].length,
    ));
  }
  // The run is contiguous, so the blocks before it in the list are exactly
  // the ones before it in rank.
  final originalRank = runStart;

  // 🚨★★ THE RULE (유저 확정 2026-08-14, ⛔재론 금지):
  // **a run swaps when the cursor reaches the seat it will SIT IN after
  // the swap.**
  //
  // > 「**커서랑 판정이랑 일치**하도록. A가 10코마 끌어야하는거. 그게
  // > 직관적임 … A10코마 B1코마의 경우 … **A를 1코마 끌면 A가 바뀌게
  // > 되는거니까**」
  //
  // The block is therefore exactly under the hand at the instant it moves:
  // the travel a swap costs is the NEIGHBOUR's length, and nothing jumps.
  //
  // ⛔What this replaces was midpoint against midpoint, which cost
  // (mine + neighbour) ÷ 2 — a 1-frame block had to travel 5.5 to pass a
  // 10-frame one and then landed nowhere near the cursor. That was chosen
  // because comparing an EDGE to a midpoint flips one direction a whole
  // run-length earlier than the other. The asymmetry is real; the answer to
  // it is not a midpoint, it is asking the question separately on each
  // side, which is what the two loops below do.
  //
  // 📐The seat is computed in the ORIGINAL layout — the invariant the old
  // note guarded and this keeps. Judging against the PREVIEW makes a run
  // chase its own tail.
  int seatStartFor(int rank) {
    var at = 0;
    for (var position = 0; position < rank; position += 1) {
      // Gaps belong to POSITIONS and blocks to ranks — the same split the
      // reorder below applies, so this is where the run really lands.
      at += slots[position].leadingGap + slots[rest[position].index].length;
    }
    return at + slots[rank].leadingGap;
  }

  // Asked from the side the hand came from. Moving right, the run passes a
  // seat once the cursor is at or past it; moving left, once it is at or
  // before it. A single expression would need a tie-break, and that
  // tie-break IS the asymmetry — 10 frames to pass a 10-frame neighbour
  // going one way and 1 going the other, for the same pair.
  var rank = originalRank;
  if (wanted > runFrom) {
    for (var next = originalRank + 1; next <= rest.length; next += 1) {
      if (seatStartFor(next) > wanted) {
        break;
      }
      rank = next;
    }
  } else if (wanted < runFrom) {
    for (var next = originalRank - 1; next >= 0; next -= 1) {
      if (seatStartFor(next) < wanted) {
        break;
      }
      rank = next;
    }
  }

  final moving = [for (var i = runStart; i <= runEnd; i += 1) i];
  final others = [for (final other in rest) other.index];
  final order = <int>[...others.take(rank), ...moving, ...others.skip(rank)];

  // 🚨★★★ EVERY BLOCK IS ALWAYS HEADING HOME (유저 H9/H10, 2026-08-22).
  //
  // > 「**원래 공간으로 회귀하려하는 시스템**을 넣고싶음. 지금 1,2,3,4가
  // > 바뀐위치에 그냥 고정되있는데, 그게아니라 **원래 위치가 비어있다면
  // > 거기로 최대한 회귀**하는 거」
  //
  // > 「**집으로 향하는 길이 비어있으면 최대한 그 길 향해서 이동**하도록
  // > 하는게 목표야. **집이 비어있으면 집으로이동 / 아니면 지금처럼
  // > 원래자리 고정이 아니야**」
  //
  // ⛔NOT A CONDITIONAL, A GRADIENT — the second sentence is the user
  // striking down exactly the two-branch reading of the first. There is no
  // "home was taken, so now something else decides". A block walks toward
  // the frame it started on and stops where the road stops. Home free means
  // it arrives; home taken means it parks against whatever took it.
  //
  // ⛔Two earlier answers are retired by this and neither may come back:
  //
  //  * gaps travelling WITH the block put the head of a sparse row on the
  //    wrong block — two blocks at 18 and 21 with an 18-frame empty head
  //    have gaps 18 and 0, so a swap carried the 0 to the front and the
  //    block landed on frame 1;
  //  * gaps staying with the POSITION (R5 #13, which fixed that) is what
  //    the user photographed: a positional gap has no memory of where its
  //    block was, so the blocks a run passes freeze wherever the
  //    permutation left them, and a run jumping from last place to first
  //    hands its big leading gap to whoever lands there.
  //
  // ★An anchor has that memory and says both in one line. The 18/21 pair
  // still trades places — P heads for 18, finds the run standing on it, and
  // parks at 21, which is where the other block was. R5 #13's case is a
  // SPECIAL CASE of heading home, not a rule beside it.
  //
  // The run's own start is PINNED, never nudged: T14's law is that the
  // block is exactly under the cursor at the instant it moves, so the
  // others answer around it — backwards on the near side, forwards on the
  // far one.
  final runPosition = rank;
  final afterRun = rank + moving.length;

  // Each block's own starting frame — the anchor it returns to.
  final anchorOf = <int, int>{
    for (var index = 0; index < slots.length; index += 1) index: starts[index],
  };

  // 🚨A block only ever gives way to a run that has CROSSED it. The ones the
  // run has not reached are WALLS: a slide stops at contact instead of
  // bulldozing, which is the rule this whole library was extracted for.
  //
  // The crossed ones are exactly those between the old rank and the new, and
  // they sit next to the run in the new order — behind it when the hand went
  // right, ahead of it when the hand went left.
  final crossedBehind = rank > originalRank ? rank - originalRank : 0;
  final crossedAhead = rank < originalRank ? originalRank - rank : 0;

  // Where the run lands. The floor is the nearest UNCROSSED block behind it,
  // standing on its own anchor, plus room for everyone it did cross.
  var floor = 0;
  final lastWallBehind = runPosition - crossedBehind - 1;
  if (lastWallBehind >= 0) {
    final wall = order[lastWallBehind];
    floor = anchorOf[wall]! + slots[wall].length;
  }
  for (var position = runPosition - crossedBehind; position < runPosition; position += 1) {
    floor += slots[order[position]].length;
  }

  // …and the ceiling is that same sentence read from the other end, never
  // past whatever end the axis itself declares.
  int? ceiling = axisEndExclusive == null ? null : axisEndExclusive - runLength;
  final firstWallAhead = afterRun + crossedAhead;
  if (firstWallAhead < order.length) {
    var wall = anchorOf[order[firstWallAhead]]!;
    for (var position = afterRun; position < firstWallAhead; position += 1) {
      wall -= slots[order[position]].length;
    }
    final contact = wall - runLength;
    if (ceiling == null || contact < ceiling) {
      ceiling = contact;
    }
  }

  var landed = wanted < floor ? floor : wanted;
  if (ceiling != null && landed > ceiling) {
    landed = ceiling < floor ? floor : ceiling;
  }

  // The run travels as ONE unit: every member keeps the distance it already
  // held from the run's head, internal gaps included.
  final placed = List<int>.filled(order.length, 0);
  for (var position = runPosition; position < afterRun; position += 1) {
    placed[position] = landed + (starts[order[position]] - runFrom);
  }

  // BEHIND the run, right to left: head for home and get as far along that
  // road as the block ahead of you (ultimately the run) leaves open. Frame 0
  // is the wall.
  var limit = landed;
  for (var position = runPosition - 1; position >= 0; position -= 1) {
    final length = slots[order[position]].length;
    final home = anchorOf[order[position]]!;
    var start = home + length > limit ? limit - length : home;
    if (start < 0) {
      start = 0;
    }
    placed[position] = start;
    limit = start;
  }

  // AHEAD of the run, left to right: the same sentence, mirrored.
  var ahead = landed + runLength;
  for (var position = afterRun; position < order.length; position += 1) {
    final home = anchorOf[order[position]]!;
    final start = home < ahead ? ahead : home;
    placed[position] = start;
    ahead = start + slots[order[position]].length;
  }

  // The layout speaks in leading gaps, so the absolute places become the
  // distances between them.
  final gaps = <int>[];
  var previousEnd = 0;
  for (var position = 0; position < order.length; position += 1) {
    gaps.add(placed[position] - previousEnd);
    previousEnd = placed[position] + slots[order[position]].length;
  }
  return BlockRunMoveLayout(slots: slots, order: order, leadingGaps: gaps);
}

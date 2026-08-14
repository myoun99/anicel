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

  // THE GAPS STAY WITH THE POSITION, not with the block that arrived
  // carrying one (R5 #13).
  //
  // They used to travel: `[for (final index in order) slots[index]...]`
  // reads each block's OWN leading gap in the new sequence. The total
  // span survives that either way — a permutation moves the same numbers
  // around — but the PLACES do not, and places are what a reorder is
  // for. A row whose first block sits at frame 19 with eighteen empty
  // frames ahead of it, and a second block glued to its end, has gaps
  // 18 and 0; swapping the two carried the 0 to the front and the block
  // landed on frame 1, with the emptiness pushed between them. Nothing
  // was lost and nothing was where the user put it.
  //
  // Reading the gaps by POSITION makes a swap a swap: each block takes
  // over the leading space of the slot it moved into, so the two trade
  // places and everything outside the run holds still. On a row with no
  // gaps (blocks packed end to end) the two rules agree exactly, which
  // is why this only ever showed itself at the head of a sparse row.
  final gaps = [
    for (var position = 0; position < order.length; position += 1)
      slots[position].leadingGap,
  ];

  // The run's own position in the sequence it just landed in, and the one
  // behind it. When the rank held, these are `runStart` and `runEnd + 1`
  // and everything below reduces to the plain slide it always was.
  final runPosition = rank;
  final afterRun = rank + moving.length;
  final isLast = afterRun >= order.length;

  // Re-time inside the free space the new neighbours leave — or, past the
  // last of them, up to the axis's own end when it has one.
  //
  // The slack is the pair of gaps AROUND the run: sliding right hands the
  // follower's space to the leader and sliding left hands it back, which is
  // the same "the follower absorbs the difference" the slide always did,
  // said as a total instead of as an increment. Everything outside that
  // pair holds still, so a swap that lands mid-gap disturbs nothing the
  // swap itself did not already move.
  var floor = 0;
  for (var position = 0; position < runPosition; position += 1) {
    floor += gaps[position] + slots[order[position]].length;
  }
  final slack = gaps[runPosition] + (isLast ? 0 : gaps[afterRun]);
  final ceiling = isLast
      ? (axisEndExclusive == null ? null : axisEndExclusive - runLength)
      : floor + slack;
  var landed = wanted < floor ? floor : wanted;
  if (ceiling != null && landed > ceiling) {
    landed = ceiling < floor ? floor : ceiling;
  }

  gaps[runPosition] = landed - floor;
  if (!isLast) {
    gaps[afterRun] = slack - (landed - floor);
  }
  return BlockRunMoveLayout(slots: slots, order: order, leadingGaps: gaps);
}

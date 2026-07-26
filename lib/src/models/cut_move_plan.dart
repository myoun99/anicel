import 'cut_id.dart';

/// One cut as the move planner sees it: its leading gap and its length.
typedef CutMoveSlot = ({CutId id, int leadingGapFrames, int duration});

/// What a cut MOVE drag resolves to — exactly one of two things.
///
/// A drag that stays in its own free space RE-TIMES: the run's leading gap
/// grows or shrinks and the cuts around it hold still. A drag that reaches
/// into a neighbour REORDERS: the sequence permutes and every comma stays
/// where it was, so the run carries its own length and only the boundaries
/// between cuts move (the design's ㉠).
///
/// The two are outcomes of ONE rule rather than two modes: the run's rank
/// among the cuts it is not part of, measured against their ORIGINAL
/// midpoints. Same rank = re-time, different rank = reorder. Measuring
/// against the original positions is what makes the rule stable — a rank
/// read off previewed positions would chase itself, since re-timing moves
/// the very midpoints the next step compares to.
class CutMovePlan {
  const CutMovePlan.slide(this.gaps) : order = null;
  const CutMovePlan.reorder(this.order) : gaps = const {};

  /// The previewed leading gaps, keyed by cut. Empty on a reorder.
  final Map<CutId, int> gaps;

  /// The previewed cut order. Null on a slide.
  final List<CutId>? order;

  bool get isReorder => order != null;
}

/// Plans a move of `slots[runStart..runEnd]` (inclusive, contiguous) by
/// [frameDelta] frames.
///
/// The run is clamped into the free space of whatever rank it lands at, so
/// a slide never overlaps a neighbour and never pushes one: running out of
/// room means the run stops at contact, and reaching past the neighbour's
/// midpoint means the order changes instead. Pushing the followers along
/// was the old whole-track shove — that behavior belongs to the push/pull
/// buttons, which take a scope, not to a drag.
CutMovePlan planCutMove({
  required List<CutMoveSlot> slots,
  required int runStart,
  required int runEnd,
  required int frameDelta,
}) {
  final starts = <int>[];
  var cursor = 0;
  for (final slot in slots) {
    cursor += slot.leadingGapFrames;
    starts.add(cursor);
    cursor += slot.duration;
  }

  final runFrom = starts[runStart];
  final runTo = starts[runEnd] + slots[runEnd].duration;
  final runLength = runTo - runFrom;
  final wanted = runFrom + frameDelta;

  // The cuts that are NOT moving, at the positions they hold throughout the
  // drag, plus the run's original rank among them.
  final rest = <({int index, int start, int endExclusive})>[];
  for (var index = 0; index < slots.length; index += 1) {
    if (index >= runStart && index <= runEnd) {
      continue;
    }
    rest.add((
      index: index,
      start: starts[index],
      endExclusive: starts[index] + slots[index].duration,
    ));
  }
  // The run is contiguous, so the cuts before it in the list are exactly
  // the ones before it in rank.
  final originalRank = runStart;

  // Midpoint against midpoint — the only comparison that reads the same
  // dragging left and right. Comparing an EDGE to a midpoint would make
  // one direction flip a whole run-length earlier than the other.
  //
  // Doubled, so an odd-length cut's midpoint is exact: truncating it would
  // shift the flip point by a frame for odd durations only.
  final wantedMidpointX2 = 2 * wanted + runLength;
  var rank = 0;
  for (final other in rest) {
    if (other.start + other.endExclusive <= wantedMidpointX2) {
      rank += 1;
    }
  }

  if (rank != originalRank) {
    final moving = [for (var i = runStart; i <= runEnd; i += 1) slots[i].id];
    final others = [for (final other in rest) slots[other.index].id];
    return CutMovePlan.reorder([
      ...others.take(rank),
      ...moving,
      ...others.skip(rank),
    ]);
  }

  // Same rank: re-time inside the free space between the neighbours.
  final floor = rank == 0 ? 0 : rest[rank - 1].endExclusive;
  final ceiling = rank == rest.length ? null : rest[rank].start - runLength;
  var landed = wanted < floor ? floor : wanted;
  if (ceiling != null && landed > ceiling) {
    landed = ceiling < floor ? floor : ceiling;
  }
  if (landed == runFrom) {
    return const CutMovePlan.slide({});
  }

  final gaps = <CutId, int>{slots[runStart].id: landed - floor};
  // The follower absorbs the difference so everything past the run holds
  // still — the run took its own space with it, not its neighbours'.
  if (runEnd + 1 < slots.length) {
    final follower = slots[runEnd + 1];
    gaps[follower.id] = follower.leadingGapFrames + (runFrom - landed);
  }
  return CutMovePlan.slide(gaps);
}

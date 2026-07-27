import 'block_run_move.dart';
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
/// The rule itself is [planBlockRunMove], shared with the frame axis: the
/// two are the same motion, and only the commit differs — this axis writes
/// leading gaps or a track order, the frame axis rewrites timeline keys.
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
/// [frameDelta] frames — the shared rank rule, stated in cuts.
CutMovePlan planCutMove({
  required List<CutMoveSlot> slots,
  required int runStart,
  required int runEnd,
  required int frameDelta,
}) {
  final layout = planBlockRunMove(
    slots: [
      for (final slot in slots)
        (leadingGap: slot.leadingGapFrames, length: slot.duration),
    ],
    runStart: runStart,
    runEnd: runEnd,
    frameDelta: frameDelta,
  );

  if (layout.isReorder) {
    return CutMovePlan.reorder([
      for (final index in layout.order) slots[index].id,
    ]);
  }

  // Only the gaps that actually changed: the drag's edit is that sparse,
  // and a full map would make every step look like it touched the track.
  return CutMovePlan.slide({
    for (var position = 0; position < layout.order.length; position += 1)
      if (layout.leadingGaps[position] !=
          slots[layout.order[position]].leadingGapFrames)
        slots[layout.order[position]].id: layout.leadingGaps[position],
  });
}

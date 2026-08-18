import 'block_run_move.dart';
import 'cut_id.dart';

/// One cut as the move planner sees it: its leading gap and its length.
typedef CutMoveSlot = ({CutId id, int leadingGapFrames, int duration});

/// What a cut MOVE drag resolves to — exactly one of two things.
///
/// A drag that stays in its own free space RE-TIMES: the run's leading gap
/// grows or shrinks and the cuts around it hold still. A drag that reaches
/// into a neighbour REORDERS: the sequence permutes, the gaps stay with
/// their POSITIONS (each cut takes over the leading space of the slot it
/// moved into, R5 #13), and the run keeps re-timing in its new rank (UI
/// 08-14 #5) — so a reorder carries gaps too.
///
/// The rule itself is [planBlockRunMove], shared with the frame axis: the
/// two are the same motion, and only the commit differs — this axis writes
/// leading gaps or a track order, the frame axis rewrites timeline keys.
class CutMovePlan {
  const CutMovePlan.slide(this.gaps, {required this.runStartFrame})
    : order = null;
  const CutMovePlan.reorder(this.order, this.gaps, {required this.runStartFrame});

  /// The previewed leading gaps, keyed by the cut whose gap changes. Sparse:
  /// only the cuts whose gap differs from their current one appear.
  final Map<CutId, int> gaps;

  /// The previewed cut order. Null on a slide.
  final List<CutId>? order;

  /// The global frame the grabbed run's first cut starts on after the move
  /// — the shared layout's second answer, which anything riding the run
  /// (the selection band) follows.
  final int runStartFrame;

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

  // Only the gaps that actually changed, keyed by the cut that lands in
  // each position: the drag's edit is that sparse, and a full map would
  // make every step look like it touched the track. The same map serves
  // both shapes — a reorder's gaps are the position gaps read by their new
  // occupants, which is exactly how "the gaps stay with the position" lands
  // on an axis whose cuts each carry their own leading gap.
  final gaps = <CutId, int>{
    for (var position = 0; position < layout.order.length; position += 1)
      if (layout.leadingGaps[position] !=
          slots[layout.order[position]].leadingGapFrames)
        slots[layout.order[position]].id: layout.leadingGaps[position],
  };

  final runStartFrame = layout.startOf(runStart);
  if (layout.isReorder) {
    return CutMovePlan.reorder(
      [for (final index in layout.order) slots[index].id],
      gaps,
      runStartFrame: runStartFrame,
    );
  }

  return CutMovePlan.slide(gaps, runStartFrame: runStartFrame);
}

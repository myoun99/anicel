import 'block_run_lead_edge.dart';
import 'cut_id.dart';
import 'cut_move_plan.dart';

/// What a cut LEAD-edge drag resolves to.
///
/// The rule is [planBlockRunLeadEdge], shared with the frame axis: dragging
/// a cut's front edge and dragging a drawing block's front edge are the
/// same motion, and only the commit differs — this axis writes cut
/// durations and leading gaps, the frame axis rewrites timeline keys.
///
/// R10 R4: before this, the two surfaces disagreed about what the gesture
/// even meant. The storyboard forked on whether the cut had a conte row —
/// with one it re-timed the LEAD (cut start pinned, later cuts pulled in),
/// without one it trimmed the cut (a gap opening in front of this cut
/// alone). Neither was the frame axis's answer, which is why the user read
/// the storyboard as "working differently from the timeline".
class CutLeadEdgePlan {
  const CutLeadEdgePlan({required this.durations, required this.gaps});

  /// The previewed durations, keyed by cut — only the dragged one, and
  /// ALWAYS present, even when the clamp left it unchanged. A caller
  /// deciding whether the drag moved anything reads this map against the
  /// before-values, and a missing key would read as a change.
  final Map<CutId, int> durations;

  /// The previewed leading gaps, keyed by cut. Sparse: only what moved.
  final Map<CutId, int> gaps;

  bool get isEmpty => durations.isEmpty && gaps.isEmpty;
}

/// Plans a drag of `slots[targetIndex]`'s lead edge by [frameDelta] frames
/// — the shared contact rule, stated in cuts.
CutLeadEdgePlan planCutLeadEdge({
  required List<CutMoveSlot> slots,
  required int targetIndex,
  required int frameDelta,
  int minDuration = 1,
}) {
  final layout = planBlockRunLeadEdge(
    slots: [
      for (final slot in slots)
        (leadingGap: slot.leadingGapFrames, length: slot.duration),
    ],
    targetIndex: targetIndex,
    frameDelta: frameDelta,
    minLength: minDuration,
  );

  final target = slots[targetIndex];
  return CutLeadEdgePlan(
    durations: {target.id: layout.lengths[targetIndex]},
    // Only the gaps that actually changed: a full map would make every
    // step of the drag look like it re-timed the whole track.
    gaps: {
      for (var i = 0; i < slots.length; i += 1)
        if (layout.leadingGaps[i] != slots[i].leadingGapFrames)
          slots[i].id: layout.leadingGaps[i],
    },
  );
}

import '../../models/key_range_shift.dart';
import '../../models/layer_id.dart';
import '../../models/timeline_frame_range.dart';
import '../../models/track_frame_range.dart';
import 'transitions.dart';

/// What a RANGE selection holds of the TRANSITION rows — the spans' half of
/// what `RangeSelections.selectionBlockStartsByLayer` answers for blocks: by
/// row id, the GLOBAL starts of the spans the selection covers. The range
/// move rides them and the range delete takes them
/// (transition-row-range-in-the-cut, 2026-09-26).
///
/// Beside [Transitions] rather than in it: it asks the row only what the row
/// already answers — which span a mark shows, and whether the cut edits it.
extension TransitionRangeHold on Transitions {
  /// The GLOBAL starts of the spans whose marks START in the cut's frames
  /// `[start, endExclusive)`, each mapped back the way
  /// [Transitions.transitionSpanStartEditableInCutAt] maps its own first
  /// frame — an O.L's left out.
  Set<int> transitionSpanStartsEditableInCutWithin(
    int start,
    int endExclusive,
  ) => {
    for (final shown in trackTransitionDisplayLayer.instructions.keys)
      if (shown >= start && shown < endExclusive)
        ?transitionSpanStartEditableInCutAt(shown),
  };

  /// What a CUT-local range [selection] holds: a cut draws one transition
  /// row, its track's, and its marks map back to their spans
  /// ([transitionSpanStartsEditableInCutWithin]).
  Map<LayerId, Set<int>> transitionStartsHeldInCut(
    TimelineFrameRangeSelection selection,
  ) => {
    for (final id in selection.spanLayerIds)
      if (isTrackTransitionLayerId(id))
        if (transitionSpanStartsEditableInCutWithin(
              selection.startIndex,
              selection.endIndexExclusive,
            )
            case final starts when starts.isNotEmpty)
          id: starts,
  };

  /// The same on the storyboard's TRACK axis, where the range is stated on
  /// the rows' own axis: every span STARTING in it ([keysStartingIn]) on
  /// each transition row it spans — an O.L's too, this being the rail that
  /// edits them.
  Map<LayerId, Set<int>> transitionStartsHeldOnTrack(
    TrackFrameRangeSelection selection,
  ) => {
    for (final row in selection.spanRows)
      if (row.owningLayerId case final id?)
        if (trackTransitionOwner(id) case final owner?)
          if (keysStartingIn(
                owner.transitionLayer.instructions.keys,
                selection.startFrame,
                selection.endFrameExclusive,
              )
              case final starts when starts.isNotEmpty)
            id: starts,
  };

  /// THE live selection's hold, whichever axis it is stated on; null when
  /// it holds none.
  Map<LayerId, Set<int>>? transitionStartsHeldBy({
    required TimelineFrameRangeSelection? inCut,
    required TrackFrameRangeSelection? onTrack,
  }) {
    final held = <LayerId, Set<int>>{
      if (inCut != null) ...transitionStartsHeldInCut(inCut),
      if (onTrack != null) ...transitionStartsHeldOnTrack(onTrack),
    };
    return held.isEmpty ? null : held;
  }

  /// Takes a hold off the rows: from each transition row in [startsByRow],
  /// the spans starting at its starts. One write per row — the range delete
  /// runs this beside the blocks inside its own one undo step.
  void removeTransitionSpans(Map<LayerId, Set<int>> startsByRow) {
    for (final MapEntry(key: id, value: starts) in startsByRow.entries) {
      if (trackTransitionOwner(id) case final track?) {
        writeTransitionRow(track, {
          for (final entry in track.transitionLayer.instructions.entries)
            if (!starts.contains(entry.key)) entry.key: entry.value,
        }, description: 'Delete transition');
      }
    }
  }
}

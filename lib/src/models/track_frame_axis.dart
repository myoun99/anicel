import '../ui/storyboard_timeline_layout.dart';
import 'cut_id.dart';
import 'range_snap.dart';

/// THE track-global frame axis (R15-①): one structural model of a track's
/// timeline — cuts occupy [start, end) ranges, the frames between them are
/// REAL addresses exactly like a layer timeline's empty frames — consumed
/// by the session's editing playhead, the storyboard AND the timeline.
/// There is exactly one implementation of "which frame is this globally":
/// changing the axis changes every panel.
///
/// A GAP (or past-the-end) frame is OWNED by the preceding cut: its local
/// index runs over that cut's end, which is the same runway grammar the
/// timeline's endless frame axis already speaks. `ownerOf` returns null
/// only in the leading gap before the first cut.
class TrackFrameAxis {
  TrackFrameAxis(this.entries);

  /// The active track's cut ranges in sequence order (the same entries the
  /// storyboard layout builds — one cumulative pass over leading gaps and
  /// durations).
  final List<StoryboardTimelineLayoutEntry> entries;

  bool get isEmpty => entries.isEmpty;

  /// The cut owning [globalFrame]: containing it, or — in a gap / past the
  /// last cut — the cut BEFORE it (its over-end runway).
  StoryboardTimelineLayoutEntry? ownerOf(int globalFrame) {
    StoryboardTimelineLayoutEntry? previous;
    for (final entry in entries) {
      if (globalFrame < entry.startFrame) {
        return previous;
      }
      if (globalFrame < entry.endFrame) {
        return entry;
      }
      previous = entry;
    }
    return previous;
  }

  /// This track's CUTS as snap material for the shared range rule
  /// ([snapSpanToBlocks]): a span half-covering a cut extends through it,
  /// exactly the way it extends through a layer's exposure block.
  ///
  /// Distinct from [ownerOf] on purpose — the owner rule hands a gap frame
  /// to the PRECEDING cut (its runway), which is right for addressing a
  /// playhead and wrong for snapping: a selection may span a gap, it just
  /// must not grow for one.
  RangeBlock? cutBlockAt(int globalFrame) {
    for (final entry in entries) {
      if (globalFrame < entry.startFrame) {
        return null;
      }
      if (globalFrame < entry.endFrame) {
        return RangeBlock(
          startIndex: entry.startFrame,
          endIndexExclusive: entry.endFrame,
        );
      }
    }
    return null;
  }

  /// The cuts a raw dragged span covers once snapped to whole cuts — the
  /// storyboard's range selection, run through the SAME rule the timeline's
  /// cell selection uses.
  List<CutId> cutsInSnappedSpan({
    required int anchorFrame,
    required int headFrame,
  }) {
    final span = snapSpanToBlocks(
      lanes: [cutBlockAt],
      anchorIndex: anchorFrame,
      headIndex: headFrame,
    );
    if (span == null) {
      return const [];
    }
    return [
      for (final entry in entries)
        if (entry.startFrame < span.endIndexExclusive &&
            entry.endFrame > span.startIndex)
          entry.cutId,
    ];
  }

  /// Whether [globalFrame] falls between cuts (no cut contains it).
  bool isGap(int globalFrame) {
    final owner = ownerOf(globalFrame);
    return owner == null || globalFrame >= owner.endFrame;
  }

  StoryboardTimelineLayoutEntry? entryFor(CutId cutId) {
    for (final entry in entries) {
      if (entry.cutId == cutId) {
        return entry;
      }
    }
    return null;
  }

  /// The global frame of ([cutId], [localFrame]); null for unknown cuts.
  int? globalOf(CutId cutId, int localFrame) {
    final entry = entryFor(cutId);
    if (entry == null) {
      return null;
    }
    return entry.startFrame + localFrame;
  }

  /// ([cutId], cut-local frame) for [globalFrame] under the owner rule;
  /// null in the leading gap before the first cut.
  ({CutId cutId, int localFrame})? localOf(int globalFrame) {
    final owner = ownerOf(globalFrame);
    if (owner == null) {
      return null;
    }
    return (cutId: owner.cutId, localFrame: globalFrame - owner.startFrame);
  }

  /// The last local frame of [cutId]'s TERRITORY — its frames plus its
  /// trailing gap; null for the last cut (endless runway) or unknown cuts.
  int? territoryLastLocalOf(CutId cutId) {
    for (var index = 0; index < entries.length - 1; index += 1) {
      if (entries[index].cutId == cutId) {
        return entries[index + 1].startFrame - entries[index].startFrame - 1;
      }
    }
    return null;
  }

  /// ([cutId], [localFrame]) as a global frame, clamped into the cut's
  /// territory — a stale over-end local index never addresses the next
  /// cut. Null for unknown cuts.
  int? clampedGlobalOf(CutId cutId, int localFrame) {
    final entry = entryFor(cutId);
    if (entry == null) {
      return null;
    }
    final local = localFrame < 0 ? 0 : localFrame;
    final territoryLast = territoryLastLocalOf(cutId);
    return entry.startFrame +
        (territoryLast == null || local <= territoryLast
            ? local
            : territoryLast);
  }

  /// ([cutId], [localFrame]) as a global frame, clamped to the CUT itself
  /// (its last frame — never the trailing gap). The timeline's over-end
  /// runway is a clipped view of the cut (UI-R9 #4): displaying it on the
  /// global axis must stop at the cut end, not leak into the gap. Null for
  /// unknown cuts.
  int? clampedToCutGlobalOf(CutId cutId, int localFrame) {
    final entry = entryFor(cutId);
    if (entry == null) {
      return null;
    }
    final lastLocal = entry.duration < 1 ? 0 : entry.duration - 1;
    final local = localFrame < 0
        ? 0
        : (localFrame > lastLocal ? lastLocal : localFrame);
    return entry.startFrame + local;
  }
}

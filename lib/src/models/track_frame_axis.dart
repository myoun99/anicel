import 'storyboard_timeline_layout.dart';
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
///
/// 🚨A CUT'S OWN FRAME 0 IS ITS MEDIA START, not its place on the track:
/// a cut an O.L arrives into is drawn [leads] frames before its conte
/// begins (F-227), and its rows' keys, the timeline's columns and
/// playback's `localFrameIndex` all count from there (`cutMediaStartFrame`
/// says where that was settled). So a frame of the cut's own is
/// [mediaStartOf] plus its index, and every conversion here says so.
///
/// ↩️The conversions counted from the cut's START (I-73-ol-index-space,
/// 🧪2026-10-08: two 24-frame cuts joined by a 12-frame O.L — the
/// storyboard's playhead on the track's frame 30 left the session on the
/// receiving cut's frame 6, whose picture plays at frame 24; a sound at
/// frame 30 stood six columns left of the picture it is heard with).
class TrackFrameAxis {
  TrackFrameAxis(this.entries, {Map<CutId, int> leads = const {}})
    : _leads = leads;

  /// The active track's cut ranges in sequence order (the same entries the
  /// storyboard layout builds — one cumulative pass over leading gaps and
  /// durations).
  final List<StoryboardTimelineLayoutEntry> entries;

  /// How many of each cut's OWN frames come before its place on the track
  /// — the のりしろ an O.L arriving into it asks
  /// (`CutTransitionHandles.head`). A cut that is not there has none.
  final Map<CutId, int> _leads;

  /// [cutId]'s のりしろ before its conte, in frames — any cut of the
  /// project's, whichever track's cuts [entries] holds: the session hands
  /// every axis the one map (`ProjectSettings`).
  int leadOf(CutId cutId) => _leads[cutId] ?? 0;

  /// The track frame [entry]'s cut shows at its own frame 0.
  int _mediaStartOf(StoryboardTimelineLayoutEntry entry) =>
      entry.startFrame - leadOf(entry.cutId);

  /// The track frame [cutId]'s own frame 0 shows; null for unknown cuts.
  int? mediaStartOf(CutId cutId) {
    final entry = entryFor(cutId);
    return entry == null ? null : _mediaStartOf(entry);
  }

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

  /// A raw dragged span snapped to whole CUTS — the storyboard's range
  /// selection, run through the SAME rule the timeline's cell selection
  /// uses. Null when the span covers no cut at all (a drag entirely inside
  /// a gap).
  ///
  /// The cut row is a frame-axis row like any other and a cut is just a
  /// long block on it; "select these cuts" is what the snap makes of a
  /// frame range, not a selection model of its own.
  RangeBlock? snapSpanToCuts({
    required int anchorFrame,
    required int headFrame,
  }) {
    final span = snapSpanToBlocks(
      lanes: [cutBlockAt],
      anchorIndex: anchorFrame,
      headIndex: headFrame,
    );
    return span == null
        ? null
        : RangeBlock(
            startIndex: span.startIndex,
            endIndexExclusive: span.endIndexExclusive,
          );
  }

  /// The cuts overlapping the half-open global span [start, endExclusive).
  List<CutId> cutsIn(int start, int endExclusive) => [
    for (final entry in entries)
      if (entry.startFrame < endExclusive && entry.endFrame > start)
        entry.cutId,
  ];

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

  /// The global frame of ([cutId], [localFrame]) — the track frame the
  /// cut's own frame plays at; null for unknown cuts.
  int? globalOf(CutId cutId, int localFrame) {
    final entry = entryFor(cutId);
    if (entry == null) {
      return null;
    }
    return _mediaStartOf(entry) + localFrame;
  }

  /// ([cutId], the cut's own frame) for [globalFrame] under the owner rule;
  /// null in the leading gap before the first cut.
  ({CutId cutId, int localFrame})? localOf(int globalFrame) {
    final owner = ownerOf(globalFrame);
    if (owner == null) {
      return null;
    }
    return (cutId: owner.cutId, localFrame: localIn(owner, globalFrame));
  }

  /// [globalFrame] as a frame of [entry]'s cut's own — [globalOf] read the
  /// other way, for a caller that already holds the cut.
  int localIn(StoryboardTimelineLayoutEntry entry, int globalFrame) =>
      globalFrame - _mediaStartOf(entry);

  /// ([cutId], [localFrame]) as a global frame, clamped to the CUT itself
  /// (its last frame — never the trailing gap). The timeline's over-end
  /// runway is a clipped view of the cut (UI-R9 #4): displaying it on the
  /// global axis must stop at the cut end, not leak into the gap. Null for
  /// unknown cuts.
  ///
  /// The same at the cut's HEAD: a frame of the のりしろ before its conte
  /// plays over the cut in front, and stands on this cut's first frame
  /// here — the cut's own block, as at its end.
  ///
  /// The ONE clamp: the storyboard's playhead and the name tags a cut's
  /// frame puts on the canvas (`SeEntries.seNameTagsForCutFrame`) both ask
  /// it. ⚠️MUTANT SURVIVES, equivalent (measured 2026-09-08, where the tags
  /// held this clamp for themselves): `>` → `>=` clamps a frame that
  /// already IS the last to itself — and `<` → `<=` the first, the same.
  int? clampedToCutGlobalOf(CutId cutId, int localFrame) {
    final entry = entryFor(cutId);
    if (entry == null) {
      return null;
    }
    final lastFrame = entry.duration < 1 ? 0 : entry.duration - 1;
    final intoConte = localFrame - leadOf(cutId);
    return entry.startFrame +
        (intoConte < 0 ? 0 : (intoConte > lastFrame ? lastFrame : intoConte));
  }

  /// Where the STORYBOARD stands for an EDITING playhead: a gap parking at
  /// its exact frame, else the active cut's local frame clamped into that cut
  /// ([clampedToCutGlobalOf]) — the storyboard shows the cut's territory
  /// (UI-R9 #4), so an index past the cut's end, where the timeline may
  /// stand, would address the NEXT cut there. Null with no cut to clamp into
  /// and no parking.
  ///
  /// ★One answer for where the storyboard DRAWS its playhead and where its
  /// flip STARTS: counted from the unclamped frame, a V-row flip from a
  /// playhead the storyboard showed on this cut's last frame jumped clean
  /// over the next cut's first panel.
  int? storyboardFrameOf({
    required int? parkedGlobalFrame,
    required CutId? activeCutId,
    required int localFrame,
  }) {
    if (parkedGlobalFrame != null) {
      return parkedGlobalFrame;
    }
    if (activeCutId == null) {
      return null;
    }
    return clampedToCutGlobalOf(activeCutId, localFrame);
  }
}

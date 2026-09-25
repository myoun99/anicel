import '../models/cut.dart';
import '../models/cut_id.dart';
import '../models/layer.dart';
import '../models/layer_id.dart';
import '../models/layer_kind.dart';
import '../models/storyboard_coverage.dart';
import '../models/storyboard_timeline_layout.dart';

/// The cut's storyboard row, or null when it has none.
///
/// A cut may hold at most ONE (the conte has one strip per cut, and the
/// coverage rule has one row to tile it). The verbs that could make a
/// second refuse — see [cutAcceptsAnotherStoryboardLayer] — but this does
/// NOT throw when it finds one anyway: it is read from painters and row
/// builds, and a throw there took the whole frame down with a red screen
/// (user, 2026-07-28). A file written by an older build, or a path nobody
/// guarded yet, must degrade to "the first one is the row" rather than to
/// no editor at all. [storyboardLayersOfCut] is how a caller that wants to
/// SAY something about the duplicate finds it.
Layer? storyboardLayerForCut(Cut cut) {
  for (final layer in cut.layers) {
    if (layer.kind == LayerKind.storyboard) {
      return layer;
    }
  }
  return null;
}

/// Each cut's PANELS, under the coverage rule — the V row's blocks: what its
/// strip paints, what its edge grips hang on, what its flip steps through.
/// A cut with no storyboard row answers with ONE cell over the whole cut, so
/// no reader has an empty case to handle.
///
/// ★One reading, because it had become three: the strip's painter and the
/// row's grips each spelled this map out, and the flip was about to be the
/// third (유저 2026-09-24: 「콘티레이어 있으면 콘티레이어 블록기준」).
Map<CutId, List<StoryboardCoverageCell>> storyboardCellsByCut(
  Iterable<StoryboardTimelineLayoutEntry> entries,
) => {
  for (final entry in entries)
    entry.cutId: storyboardCoverageCells(
      timeline: storyboardLayerForCut(entry.cut)?.timeline,
      cutDuration: entry.duration,
    ),
};

/// One PANEL of a track's V row, on the track's global axis.
typedef StoryboardTrackPanel = ({
  int start,
  int endExclusive,
  StoryboardTimelineLayoutEntry cut,
});

/// The V row's blocks laid on the TRACK's global axis, in order — each cut's
/// panels at the cut's own place ([storyboardCellsByCut]), so a cut with a
/// conte row is several blocks and a cut without one is a single block that
/// happens to be the whole cut. The frames between cuts are no block at
/// all: a gap is walked a frame at a time, like any uncovered frame.
///
/// ★The unit is I-21's (유저 2026-09-12, 「그 컷 블록에 콘티블록있으면 그
/// 블록의 헤드까지. 이것도 똑같은 법인거지」): the V row's lead edge trades
/// frames across exactly these, and the flip counts exactly these.
List<StoryboardTrackPanel> storyboardPanelsOnTrack(
  List<StoryboardTimelineLayoutEntry> entries,
) {
  final cells = storyboardCellsByCut(entries);
  return [
    for (final entry in entries)
      for (final cell in cells[entry.cutId]!)
        (
          start: entry.startFrame + cell.startIndex,
          endExclusive: entry.startFrame + cell.endIndexExclusive,
          cut: entry,
        ),
  ];
}

/// Every storyboard row on [cut] — one in every reachable state, more only
/// where something already went wrong.
List<Layer> storyboardLayersOfCut(Cut cut) => [
  for (final layer in cut.layers)
    if (layer.kind == LayerKind.storyboard) layer,
];

/// Whether [cut] may take another storyboard row — false once it has one.
///
/// [exceptLayerId] is the layer being CONVERTED, which does not count
/// against itself: re-applying the kind to the row that already is one is
/// a no-op, not a second row.
bool cutAcceptsAnotherStoryboardLayer(Cut cut, {LayerId? exceptLayerId}) {
  for (final layer in cut.layers) {
    if (layer.kind == LayerKind.storyboard && layer.id != exceptLayerId) {
      return false;
    }
  }
  return true;
}

/// The shortest [cut] may become without leaving a storyboard drawing
/// outside it (user's rule 2026-07-27).
///
/// The storyboard row lives INSIDE its cut — that is the whole basis of
/// the conte, where a cell is a panel OF this cut. So the cut's end cannot
/// be dragged past the last division on it: to shrink further, delete the
/// cells first. Everything else keeps the plain one-frame floor.
///
/// This is the invariant's near half. The far half is that the row is born
/// covering the cut, so the two together mean the coverage rule never has
/// a hole to repair.
int minimumCutDurationFor(Cut cut) {
  final layer = storyboardLayerForCut(cut);
  return layer == null ? 1 : minimumCutDurationForStoryboardRow(layer);
}

/// The same floor, read off the ROW rather than off the cut.
///
/// A drag holds its row's next form in hand and has not written it yet, so
/// asking the cut — which reaches the repository — answers about the row as
/// it was BEFORE the gesture. Mixing that stale floor with a previewed row
/// end is what let a shrink pin the duration ABOVE the row's end and commit
/// the pair out of sync; the same drag then read as flapping, and the next
/// one collapsed the cut onto the row it had already broken.
int minimumCutDurationForStoryboardRow(Layer row) {
  var lastDivision = 0;
  for (final entry in row.timeline.entries) {
    if (entry.value.isDrawing && !entry.value.ghost) {
      lastDivision = entry.key > lastDivision ? entry.key : lastDivision;
    }
  }
  return lastDivision + 1;
}

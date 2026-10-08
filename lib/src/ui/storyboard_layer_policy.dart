import 'dart:collection';

import '../models/cut.dart';
import '../models/cut_id.dart';
import '../models/frame.dart';
import '../models/layer.dart';
import '../models/layer_id.dart';
import '../models/layer_kind.dart';
import '../models/layer_mark.dart';
import '../models/storyboard_coverage.dart';
import '../models/storyboard_timeline_layout.dart';
import '../models/timeline_exposure.dart';
import '../models/track_conte_row.dart';
import '../models/track_id.dart';

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

/// THE CONTE LAYER THE STORYBOARD'S CONTE ROW HAS IN HAND: [cut]'s conte
/// layer, while it is the layer the timeline stands on ([activeLayerId]).
///
/// The conte row is ONE row over every cut ([trackConteRowId]), so what it
/// stands on is resolved each time it is asked. Standing there seats the
/// timeline on the conte layer of the cut under the playhead
/// (`Standing.layerAConteStandSeats`), and the verbs that act on the
/// timeline's own row — the frame buttons, the shove, the row's whole span
/// — are this row's for as long as that stays so. Null where the cut has no
/// conte layer, where there is no cut (a gap), and once another layer has
/// been picked in the timeline: that one is the timeline panel's subject,
/// not this row's.
Layer? conteLayerInHand({required Cut? cut, required LayerId? activeLayerId}) {
  final conte = cut == null ? null : storyboardLayerForCut(cut);
  return conte != null && conte.id == activeLayerId ? conte : null;
}

/// Each cut's PANELS, under the coverage rule — what the V row's strip
/// paints a picture for, and what the conte row under it hangs its edge
/// grips on. A cut with no storyboard row answers with ONE cell over the
/// whole cut, so no reader has an empty case to handle.
///
/// ★One reading, because it had become three: the strip's painter and the
/// row's grips each spelled this map out, and the flip was about to be the
/// third (유저 2026-09-24: 「콘티레이어 있으면 콘티레이어 블록기준」).
/// ↩️The flip read it as a list of blocks on the track's axis
/// (`storyboardPanelsOnTrack`) while the V row's flip counted panels; the
/// conte row's flip counts the blocks of [trackConteRowShown] now, as every
/// layer row's does (I-73).
Map<CutId, List<StoryboardCoverageCell>> storyboardCellsByCut(
  Iterable<StoryboardTimelineLayoutEntry> entries,
) => {
  for (final entry in entries)
    entry.cutId: storyboardCoverageCells(
      timeline: storyboardLayerForCut(entry.cut)?.timeline,
      cutDuration: entry.duration,
    ),
};

/// THE TRACK'S CONTE ROW AS IT IS DRAWN (I-73, 유저 2026-10-08: 「v행 아래에
/// 콘티행 만들어서 거기서」 · 「콘티행도 동일하게 하고싶으니까」): the cuts'
/// conte layers laid on the TRACK's axis as ONE row of blocks, each cut's
/// panels at the cut's own place, so the storyboard draws them with the
/// timeline's own row painter — a panel's name at its head and its length
/// at its end, the frame block's print, where the cut block's inner bands
/// used to carry them.
///
/// The blocks are the row's stored ones as the coverage rule reads them
/// ([storyboardTimelineFilledToCover], the rewrite the repository itself
/// keeps): tiled over the cut and counted in the CONTE's frames, so a cut
/// an O.L arrives into shows its panels from its own start and not the
/// のりしろ before it (F-227). A cut with no conte layer, and a gap, hold
/// nothing here.
///
/// The row wears the first conte layer's name and colour label
/// ([trackConteHeadLayer]).
Layer trackConteRowShown(
  TrackId trackId,
  Iterable<StoryboardTimelineLayoutEntry> entries,
) {
  final timeline = SplayTreeMap<int, TimelineExposure>();
  final frames = <Frame>[];
  for (final entry in entries) {
    final row = storyboardLayerForCut(entry.cut);
    if (row == null) {
      continue;
    }
    final conteStart = storyboardConteStart(row.timeline);
    final tiled = storyboardTimelineFilledToCover(
      timeline: row.timeline,
      cutDuration: entry.duration,
      conteStart: conteStart,
    );
    if (tiled == null) {
      continue;
    }
    frames.addAll(row.frames);
    for (final MapEntry(key: ownFrame, value: block) in tiled.entries) {
      timeline[entry.startFrame + ownFrame - conteStart] = block;
    }
  }
  final head = trackConteHeadLayer([for (final entry in entries) entry.cut]);
  return Layer(
    id: trackConteRowId(trackId),
    name: head?.name ?? '',
    kind: LayerKind.storyboard,
    mark: head?.mark ?? LayerMark.none,
    frames: frames,
    timeline: timeline,
  );
}

/// The conte layer the track's conte row is NAMED and COLOURED by: the
/// first one on the track, in the cuts' order — null while no cut has one.
///
/// ⚠️Every cut keeps its own conte layer, so until the row's head writes to
/// all of them at once (I-73 ③ — 유저 2026-10-08: 「콘티레이어 권고한대로
/// 머리만 한벌 ok」) two cuts' layers may still differ; the row then shows
/// the first's.
Layer? trackConteHeadLayer(Iterable<Cut> cuts) {
  for (final cut in cuts) {
    final row = storyboardLayerForCut(cut);
    if (row != null) {
      return row;
    }
  }
  return null;
}

/// The frame of [entry]'s conte layer — in the CUT's own frames, the row's
/// keys — that the track's frame [globalFrame] shows on the conte row, held
/// inside the cut: the conte begins [storyboardConteStart] frames into the
/// row (F-227), so a track frame counted from the cut's start is that much
/// short of the key it stands on.
int conteRowOwnFrameAt(
  StoryboardTimelineLayoutEntry entry,
  Layer row,
  int globalFrame,
) {
  final last = entry.duration - 1;
  final conteFrame = (globalFrame - entry.startFrame).clamp(
    0,
    last < 0 ? 0 : last,
  );
  return storyboardConteStart(row.timeline) + conteFrame;
}

/// Where [ownFrame] of [entry]'s conte layer stands on the track's axis —
/// [conteRowOwnFrameAt] read the other way.
int conteRowGlobalFrameOf(
  StoryboardTimelineLayoutEntry entry,
  Layer row,
  int ownFrame,
) => entry.startFrame + ownFrame - storyboardConteStart(row.timeline);

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
///
/// Counted in the CONTE's frames: a cut an O.L arrives into keeps its
/// panels after the のりしろ it owes ([storyboardConteStart], F-227), and
/// those frames are its first panel held back, not length to trim.
int minimumCutDurationForStoryboardRow(Layer row) {
  final conteStart = storyboardConteStart(row.timeline);
  var lastDivision = conteStart;
  for (final entry in row.timeline.entries) {
    if (entry.value.isDrawing && !entry.value.ghost) {
      lastDivision = entry.key > lastDivision ? entry.key : lastDivision;
    }
  }
  return lastDivision - conteStart + 1;
}

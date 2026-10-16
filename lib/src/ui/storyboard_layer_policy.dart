import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;

import '../core/signed_memo.dart';
import '../models/attached_layer_resolve.dart' show attachedRowAsShown;
import '../models/conte_group.dart';
import '../models/cut.dart';
import '../models/cut_camera.dart' show cameraDrawnFrameFloor;
import '../models/cut_id.dart';
import '../models/frame.dart';
import '../models/layer.dart';
import '../models/layer_id.dart';
import '../models/layer_kind.dart';
import '../models/layer_mark.dart';
import '../models/storyboard_coverage.dart';
import '../models/storyboard_timeline_layout.dart';
import '../models/timeline_exposure.dart';
import '../models/timeline_row_address.dart';
import '../models/timeline_splice.dart' show captureTimelineRun;
import '../models/track_camera_head.dart' show cameraHeadOf;
import '../models/track_camera_row.dart';
import '../models/track_conte_row.dart';
import '../models/track_id.dart';
import '../models/track_projection_row.dart';
import '../services/editing/default_cut_helpers.dart' show cameraRowBornName;
import '../services/editing/default_layer_helpers.dart' show conteRowBornName;

/// ⚠️Which row is a cut's conte — [storyboardLayerForCut] and its two
/// neighbours — moved inward (`models/conte_group.dart`) so that the
/// commands and the repository ask the same question: `services/` cannot
/// import this file, and each had spelled 「the first storyboard row」 for
/// itself. Re-exported here because this is where the storyboard's layer
/// questions are looked up.
export '../models/conte_group.dart'
    show
        cutAcceptsAnotherStoryboardLayer,
        storyboardLayerForCut,
        storyboardLayersOfCut;

/// THE LAYER A STORYBOARD PROJECTION ROW HAS IN HAND: the layer of [cut]
/// that [row] shows there ([projectedRowOf] — a seat of its conte group, or
/// its camera layer), while it is the layer the timeline stands on
/// ([activeLayerId]).
///
/// A projection row is ONE row over every cut ([trackConteRowId],
/// [trackCameraRowId]), so what it stands on is resolved each time it is
/// asked. Standing there seats the timeline on that layer of the cut the
/// session stands in (`Standing.layerAProjectionStandSeats`), and the verbs
/// that act on the timeline's own row — the frame buttons, the shove, the
/// row's whole span — are this row's for as long as that stays so. Null
/// where [row] is no projection row, where the cut has no layer there,
/// where there is no cut (a gap), and once another layer has been picked in
/// the timeline: that one is the timeline panel's subject, not this row's.
///
/// ↩️`conteLayerInHand` while the conte rows were the only projection rows;
/// the camera row asks the same question (I-73 ④, 「타임라인의 자리 = 카메라
/// 행」).
Layer? projectedLayerInHand({
  required TimelineRowAddress? row,
  required Cut? cut,
  required LayerId? activeLayerId,
}) {
  final layer = cut == null ? null : projectedRowOf(cut, row);
  return layer != null && layer.id == activeLayerId ? layer : null;
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
/// An ATTACH row of the conte ([seat] other than 0) is laid the same way:
/// each cut's row at that seat as the timeline shows it
/// ([attachedRowAsShown] — a synced row wears its base's blocks), the cells
/// of it that fall inside the conte ([captureTimelineRun], which cuts a
/// block that straddles an end there).
///
/// The row wears its head's name and colour label ([conteHeadRowAt]).
///
/// 🚨ONE ROW FOR ONE LAYING (I-57, 10-14). Made anew on every call, the
/// row was a new layer on every build of the storyboard — a cut crossed
/// under the playhead among them — and the timeline's row painter knows
/// its row by identity: each build repainted the whole film's conte cells
/// and said every one of them again to a screen reader (🔬the largest cost
/// of a crossing's frame on the AMMI OP). So the row is kept on the
/// track's id for the cuts as last laid, and handed back while they are
/// laid alike — the same cuts at the same places, by the one law the
/// storyboard's rows are kept by ([StoryboardTimelineLayoutEntry.==]).
Layer trackConteRowShown(
  TrackId trackId,
  Iterable<StoryboardTimelineLayoutEntry> entries, {
  int seat = 0,
}) {
  final laid = [...entries];
  return _conteRowsShownAt(seat).resolve(
    trackId,
    laid,
    () => _conteRowLaid(trackId, laid, seat),
  );
}

/// The conte rows last shown of each track, a memo per seat — each on the
/// track's id, which every version of the track shares, so they go with the
/// project.
final List<SignedMemo<List<StoryboardTimelineLayoutEntry>, Layer>>
_conteRowsShown = [];

SignedMemo<List<StoryboardTimelineLayoutEntry>, Layer> _conteRowsShownAt(
  int seat,
) {
  while (_conteRowsShown.length <= seat) {
    _conteRowsShown.add(SignedMemo('conte rows shown', same: listEquals));
  }
  return _conteRowsShown[seat];
}

/// [trackConteRowShown] made from [laid].
Layer _conteRowLaid(
  TrackId trackId,
  List<StoryboardTimelineLayoutEntry> laid,
  int seat,
) {
  final timeline = SplayTreeMap<int, TimelineExposure>();
  final frames = <Frame>[];
  for (final entry in laid) {
    final cells = _conteCellsOf(entry, seat);
    if (cells == null) {
      continue;
    }
    frames.addAll(cells.row.frames);
    for (final MapEntry(key: conteFrame, value: block)
        in cells.blocks.entries) {
      timeline[entry.startFrame + conteFrame] = block;
    }
  }
  final cuts = [for (final entry in laid) entry.cut];
  return Layer(
    id: trackConteRowId(trackId, seat: seat),
    name: trackConteRowName(cuts, seat: seat),
    kind: LayerKind.storyboard,
    mark: conteHeadRowAt(cuts, seat)?.mark ?? LayerMark.none,
    frames: frames,
    timeline: timeline,
  );
}

/// [entry]'s row at [seat] and its blocks counted in the CONTE's frames —
/// 0 at the cut's start on the track; null where the cut holds no row
/// there, or nothing of it to show.
({Layer row, Map<int, TimelineExposure> blocks})? _conteCellsOf(
  StoryboardTimelineLayoutEntry entry,
  int seat,
) {
  final base = storyboardLayerForCut(entry.cut);
  if (base == null) {
    return null;
  }
  final conteStart = storyboardConteStart(base.timeline);
  if (seat == 0) {
    final tiled = storyboardTimelineFilledToCover(
      timeline: base.timeline,
      cutDuration: entry.duration,
      conteStart: conteStart,
    );
    return tiled == null
        ? null
        : (
            row: base,
            blocks: {
              for (final MapEntry(key: ownFrame, value: block)
                  in tiled.entries)
                ownFrame - conteStart: block,
            },
          );
  }
  final row = conteRowAtSeat(entry.cut, seat);
  if (row == null) {
    return null;
  }
  final shown = attachedRowAsShown(row, entry.cut.layers);
  return (
    row: shown,
    blocks: captureTimelineRun(
      timeline: shown.timeline,
      index: conteStart,
      count: entry.duration,
    ).exposures,
  );
}

/// THE TRACK'S CAMERA ROW AS THE WALKS SEE IT (I-73 ④): a row on the
/// track's axis that holds no block — the timeline's camera row keeps keys,
/// not blocks ([LayerKind.hasBlocks]) — so a flip walks it a frame at a
/// time and the flip window draws it empty, as that row's are. It goes by
/// its head's name ([trackCameraRowName]).
Layer trackCameraRowShown(
  TrackId trackId,
  Iterable<Cut> cuts, {
  required CutId? standingIn,
}) => Layer(
  id: trackCameraRowId(trackId),
  name: trackCameraRowName(cuts, standingIn: standingIn),
  kind: LayerKind.camera,
  frames: const [],
);

/// The name a track's camera row goes by wherever it is written — its rail
/// label, the flip window: its head's, the camera layer of the cut
/// [standingIn] when that cut is one of [cuts], and otherwise (a gap,
/// another track's cut) the name the track's cameras wear as one
/// ([cameraHeadOf], I-73-camera-row-Q1) — or, with no camera at all, the
/// name one is born with ([cameraRowBornName]). ONE answer, the lesson
/// [trackConteRowName] learned. ↩️The gap read the program language's word
/// for the kind, so the row's name changed language as the playhead left a
/// cut (F-322: 「멋대로 한글로 콘티라고 하지말것」, of the conte row's).
String trackCameraRowName(Iterable<Cut> cuts, {required CutId? standingIn}) {
  for (final cut in cuts) {
    if (cut.id == standingIn) {
      final camera = cut.layers.cameraLayer;
      if (camera != null) {
        return camera.name;
      }
    }
  }
  return cameraHeadOf(cuts)?.name ?? cameraRowBornName;
}

/// The name a track's conte row goes by wherever it is written — its rail
/// label, the flip window: its head's ([conteHeadRowAt], the first of the
/// cuts that holds a row at [seat]), and the name a conte row is born with
/// while no cut has one ([conteRowBornName]). ↩️That was the program
/// language's word for the kind — 「콘티」 in Korean, until the first panel
/// made a row named Conte: 🗣️F-322 (유저 2026-10-09) 「그냥 통일. 멋대로
/// 한글로 콘티라고 하지말것」.
///
/// ⚠️ONE answer. The rail read the kind's word and the row as drawn an
/// empty name, so a film with no conte layer yet named the row on its rail
/// and left it nameless in the flip window (🧪2026-10-08, before it landed).
String trackConteRowName(Iterable<Cut> cuts, {int seat = 0}) =>
    conteHeadRowAt(cuts, seat)?.name ?? conteRowBornName;

/// The frame of [entry]'s cut — in the CUT's own frames, its rows' keys —
/// that the track's frame [globalFrame] shows on a conte row, held inside
/// the cut: the conte begins [storyboardConteStart] frames into its base
/// (F-227), so a track frame counted from the cut's start is that much
/// short of the key it stands on.
///
/// ↩️It took the row as well and read the start off it, which was the cut's
/// conte layer while the row had one seat. An attach row's own first block
/// says nothing of where the conte begins — its BASE's does — so the cut
/// is asked ([storyboardLayerForCut]).
int conteRowOwnFrameAt(StoryboardTimelineLayoutEntry entry, int globalFrame) {
  final last = entry.duration - 1;
  final conteFrame = (globalFrame - entry.startFrame).clamp(
    0,
    last < 0 ? 0 : last,
  );
  return _conteStartOf(entry) + conteFrame;
}

/// Where [ownFrame] of [entry]'s cut stands on the track's axis —
/// [conteRowOwnFrameAt] read the other way.
int conteRowGlobalFrameOf(StoryboardTimelineLayoutEntry entry, int ownFrame) =>
    entry.startFrame + ownFrame - _conteStartOf(entry);

int _conteStartOf(StoryboardTimelineLayoutEntry entry) =>
    storyboardConteStart(storyboardLayerForCut(entry.cut)?.timeline);

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
///
/// The CAMERA lives inside its cut the same way (I-73-camera-row-Q4, 유저
/// 2026-10-09: 「밖엔 애초에 존재못하게하는게 지금구조잖아」): the key on the
/// cut's last frame comes in with the end, and the end stops short of every
/// other key ([cameraDrawnFrameFloor]) — counted in the frames the cut is
/// drawn for, [drawnFrameCount], so the のりしろ it owes is no length to
/// trim.
int minimumCutDurationFor(Cut cut, {required int drawnFrameCount}) {
  final layer = storyboardLayerForCut(cut);
  final conte = layer == null ? 1 : minimumCutDurationForStoryboardRow(layer);
  return math.max(
    conte,
    minimumCutDurationForCamera(cut, drawnFrameCount: drawnFrameCount),
  );
}

/// The camera's half of [minimumCutDurationFor] alone — what a FRONT edge
/// shrink is bounded by too, where the conte's floor is its first panel's
/// own rather than its last division.
int minimumCutDurationForCamera(Cut cut, {required int drawnFrameCount}) =>
    cameraDrawnFrameFloor(cut.camera, drawnFrameCount: drawnFrameCount) -
    (drawnFrameCount - cut.duration);

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

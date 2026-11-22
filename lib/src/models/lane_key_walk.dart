/// WHERE A LANE'S KEY ARROWS GO: the nearest key before the frame stood on
/// and the nearest after it — over one cut's lane on the timeline, and over
/// every cut's on the film, where the conte's rows show them.
///
/// 🗣️F-625 (유저 2026-11-21): 「콘티패널에선 로컬트랙이더라도 키 < > 누를수있는
/// 판정이나 이동이 글로벌로 작동하도록. 지금 카메라레이어에서 비율 <나 >로
/// 이전/다음 키로 이동할때 컷 내에서만 판정되서 이동가능한데, 글로벌로
/// 판정해서 다른컷에 키 있거나 해도 보이게? 이는 콘티레이어가 아직안됫다면
/// 콘티레이어나 다른것도 마찬가지. 로컬은 지금대로 컷 내에서 < > 판정」 —
/// the search is one ([keysAbout]); what differs is the frames it is asked
/// of: a cut's own keyed frames, or the track frames the film draws a key
/// at ([filmKeyFrames]).
library;

import 'camera_row_reach.dart';
import 'cut.dart';
import 'cut_id.dart';

/// The nearest of [frames] before [frame] and the nearest after it — null
/// where there is none. [frame] itself is neither: the arrows leave it.
({int? previous, int? next}) keysAbout(Iterable<int> frames, int frame) {
  int? previous;
  int? next;
  for (final keyed in frames) {
    if (keyed < frame && (previous == null || keyed > previous)) {
      previous = keyed;
    }
    if (keyed > frame && (next == null || keyed < next)) {
      next = keyed;
    }
  }
  return (previous: previous, next: next);
}

/// The track frames the film draws a key at: each of [reaches]' cuts' own
/// keyed frames ([ownKeysOf]) that lie in its reach — where a projection
/// row's strip draws them ([CameraRowReach.reaches]; a key past its cut's
/// own frames is not drawn, and not walked) — ascending, each frame once
/// though two cuts an O.L joins key it.
List<int> filmKeyFrames(
  List<CameraRowReach> reaches,
  Iterable<int> Function(Cut cut) ownKeysOf,
) {
  final frames = <int>{
    for (final reach in reaches)
      for (final key in ownKeysOf(reach.entry.cut))
        if (reach.reaches(reach.trackFrameOf(key))) reach.trackFrameOf(key),
  };
  return frames.toList()..sort();
}

/// The cut to stand in for the key the film draws at [trackFrame], and the
/// frame of its own the key is on: [stoodIn] where it holds one there — a
/// walk stays in its cut across an O.L, where two cuts' own frames share
/// the track's — else the first cut that does, in track order. Null where
/// none does.
({CutId cutId, int ownFrame})? filmKeyHolderAt(
  List<CameraRowReach> reaches,
  Iterable<int> Function(Cut cut) ownKeysOf,
  int trackFrame, {
  CutId? stoodIn,
}) {
  ({CutId cutId, int ownFrame})? first;
  for (final reach in reaches) {
    final cut = reach.entry.cut;
    final own = trackFrame - reach.mediaStart;
    if (!reach.reaches(trackFrame) || !ownKeysOf(cut).contains(own)) {
      continue;
    }
    if (cut.id == stoodIn) {
      return (cutId: cut.id, ownFrame: own);
    }
    first ??= (cutId: cut.id, ownFrame: own);
  }
  return first;
}

import 'conte_group.dart';
import 'cut.dart';
import 'cut_id.dart';
import 'layer.dart';
import 'layer_id.dart';
import 'project.dart';
import 'timeline_row_address.dart';
import 'track_camera_row.dart';
import 'track_conte_row.dart';
import 'track_id.dart';

/// A TRACK'S PROJECTION ROWS — a cut's own row shown as ONE row on the
/// track's axis, every cut's at its own place (I-73, 유저 2026-10-08: 「즉
/// 새롭게 로컬행을 글로벌행에도 보이게하는걸 생각중」). The track's conte rows
/// ([trackConteRowId], a row a seat) and its camera row ([trackCameraRowId])
/// are the two; the storyboard's S rows shown in a cut are the mirror image
/// of them, a track's row shown on a cut's axis.
///
/// ★ONE row kind with two instances — the shape the first consultation drew
/// (「컷 로컬 행을 트랙 축에 투영한 행이라는 행 종류 하나를 만들고 콘티 행 ·
/// 카메라 행이 그 두 사례가 된다」). What every projection row answers alike
/// is asked here: whose track it is, and which layer of a cut it shows.

/// The track whose projection row [layerId] names — a conte row at any seat,
/// or the camera row; null for every other id.
TrackId? trackIdOfProjectionRow(LayerId layerId) =>
    trackIdOfConteRow(layerId) ?? trackIdOfCameraRow(layerId);

/// Whether [row] is one of a track's projection rows.
bool isTrackProjectionRow(TimelineRowAddress? row) =>
    row is LayerRowAddress && trackIdOfProjectionRow(row.layerId) != null;

/// The layer of [cut] the projection row [row] shows there: the row at its
/// seat of the cut's conte group, or the cut's camera layer. Null where
/// [row] is no projection row, and where the cut holds no row there.
Layer? projectedRowOf(Cut cut, TimelineRowAddress? row) {
  final seat = conteRowSeatOf(row);
  if (seat != null) {
    return conteRowAtSeat(cut, seat);
  }
  return isTrackCameraRow(row) ? cut.layers.cameraLayer : null;
}

/// The projection row [row] stands on: [row] itself, or the row one of
/// whose LANES it is (I-73 ④ⓔ — a projection row twirls its lanes down as
/// the timeline's row does) — the lane address's own law, 「standing on a
/// property never costs you the layer」. Null for every other address.
///
/// ⛔Not [isTrackProjectionRow] widened: a lane holds keys, not blocks, and
/// the doors that ask THAT question (the cursor's block, a row's ＋) must
/// go on telling a lane from its row.
LayerRowAddress? projectionRowUnder(TimelineRowAddress? row) => switch (row) {
  LayerRowAddress(:final layerId) || LaneRowAddress(:final layerId)
      when trackIdOfProjectionRow(layerId) != null =>
    LayerRowAddress(layerId),
  _ => null,
};

/// The ROW IN HAND of the projection row [rowId], and the cut it is in:
/// the layer every verb on the row acts on, and the one its rail label
/// wears ([projectionRowInHandOn]). Null for every other id, and while no
/// cut holds a row there.
({Cut cut, Layer row})? projectionRowInHand(
  Project project,
  LayerId rowId, {
  required CutId? standingIn,
}) {
  final trackId = trackIdOfProjectionRow(rowId);
  for (final track in project.tracks) {
    if (track.id == trackId) {
      return projectionRowInHandOn(
        track.cuts,
        LayerRowAddress(rowId),
        standingIn: standingIn,
      );
    }
  }
  return null;
}

/// [projectionRowInHand] over [row]'s own track's [cuts]: the row [row]
/// shows in the cut the session stands in ([standingIn]), where that cut
/// holds one — the timeline's own row, so what is done to it shows there as
/// it would have — else the row that speaks for it, the first of [cuts]
/// that holds one: every head field is one for all of them (I-73,
/// `headMirrorTargets`). Null while none does.
///
/// ★ONE answer for every door that asks which layer a projection row is —
/// a press on its buttons, a verb on a selection holding it, a drag of it,
/// a rename, the label and the lanes it draws. ↩️Each asked its own (the
/// drag and the lanes the cut stood in else the head, the rename and the
/// label the head alone), and a selection holding the row reached no verb
/// at all — its buttons pressed the one row, and Delete took the block
/// under the playhead instead of the rows (the conte panel's audit,
/// 2026-10-10).
({Cut cut, Layer row})? projectionRowInHandOn(
  Iterable<Cut> cuts,
  TimelineRowAddress row, {
  required CutId? standingIn,
}) {
  ({Cut cut, Layer row})? head;
  for (final cut in cuts) {
    final shown = projectedRowOf(cut, row);
    if (shown == null) {
      continue;
    }
    if (cut.id == standingIn) {
      return (cut: cut, row: shown);
    }
    head ??= (cut: cut, row: shown);
  }
  return head;
}

/// [projectedRowOf] read backwards: the projection row of [trackId] that
/// shows [cut]'s row [layerId] — the camera row for its camera, the conte
/// row at its seat for a row of its conte group — or null for any other row.
LayerId? projectionRowIdOf(TrackId trackId, Cut cut, LayerId layerId) {
  if (cut.layers.cameraLayer?.id == layerId) {
    return trackCameraRowId(trackId);
  }
  final seat = conteSeatOf(cut, layerId);
  return seat == null ? null : trackConteRowId(trackId, seat: seat);
}

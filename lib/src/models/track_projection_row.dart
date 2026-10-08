import 'conte_group.dart';
import 'cut.dart';
import 'layer.dart';
import 'layer_id.dart';
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

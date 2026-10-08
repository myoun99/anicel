import 'layer_id.dart';
import 'timeline_row_address.dart';
import 'track_id.dart';

/// THE TRACK'S CONTE ROW (I-73, 유저 2026-10-08).
///
/// 「v행 아래에 콘티행 만들어서 거기서 … 컷에 설때는 예전처럼 마지막에 섯던
/// 행에 서있는채로 그대로. 콘티행에 서야 콘티행에 서도록」 — the storyboard
/// panel shows the cuts' conte layers as ONE row on the track's axis, under
/// the V row: the V row is the cuts, this row their panels.
///
/// Every cut keeps its own conte layer — its own id, its own blocks — and
/// some cuts have none, and a gap has no cut at all. So the ROW needs an
/// address that is there wherever the playhead stands, and no cut's layer id
/// is one. This is that address, minted from the track the way the V track's
/// lane carrier is ([trackTransformLaneCarrierId]): a row the rail stands on
/// and lights, which the verbs then resolve to the conte layer of the cut
/// under the playhead — or to nothing, where there is none.
const _prefix = 'conte-row:';

LayerId trackConteRowId(TrackId trackId) =>
    LayerId('$_prefix${trackId.value}');

/// The track whose conte row [layerId] names; null for every other id — a
/// cut's own conte layer among them.
TrackId? trackIdOfConteRow(LayerId layerId) {
  final value = layerId.value;
  if (!value.startsWith(_prefix)) {
    return null;
  }
  return TrackId(value.substring(_prefix.length));
}

/// Whether [row] is a track's conte row — the address the storyboard's rail
/// stands on and lights, never a cut's own layer.
bool isTrackConteRow(TimelineRowAddress? row) =>
    row is LayerRowAddress && trackIdOfConteRow(row.layerId) != null;

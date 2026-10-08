import 'layer_id.dart';
import 'timeline_row_address.dart';
import 'track_id.dart';
import 'track_minted_row_id.dart';

/// THE TRACK'S CONTE ROWS (I-73, 유저 2026-10-08).
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
///
/// A cut's conte is a GROUP — its base and the attach rows riding it — and
/// the rail draws one row for each SEAT of it (`models/conte_group.dart`:
/// 0 the base, +k above, −k below; 유저: 「콘티행도 동일하게 하고싶으니까
/// 어태치 접기펼치기버튼등 동일하게 할수있는거 다 넣는거 잊지말고」). The
/// base's row keeps the address it was given first (`conte-row:<track>`);
/// an attach seat's says its seat BEFORE the track (`conte-row@-1:<track>`),
/// so that no track's own id can be read as a seat.
const _word = 'conte-row';
const _prefix = '$_word:';
const _seatPrefix = '$_word@';

LayerId trackConteRowId(TrackId trackId, {int seat = 0}) => seat == 0
    ? mintedTrackRowId(_prefix, trackId)
    : mintedTrackRowId('$_seatPrefix$seat:', trackId);

/// The track and the seat a conte row's address names; null for every other
/// id — a cut's own conte layer among them.
({TrackId trackId, int seat})? trackConteRowOf(LayerId layerId) {
  final base = trackOfMintedRowId(_prefix, layerId);
  if (base != null) {
    return (trackId: base, seat: 0);
  }
  final value = layerId.value;
  if (!value.startsWith(_seatPrefix)) {
    return null;
  }
  final colon = value.indexOf(':', _seatPrefix.length);
  final seat = colon < 0
      ? null
      : int.tryParse(value.substring(_seatPrefix.length, colon));
  return seat == null
      ? null
      : (trackId: TrackId(value.substring(colon + 1)), seat: seat);
}

/// The track whose conte row — at any seat — [layerId] names; null for
/// every other id.
TrackId? trackIdOfConteRow(LayerId layerId) =>
    trackConteRowOf(layerId)?.trackId;

/// The seat [row] names when it is a track's conte row; null for every
/// other row.
int? conteRowSeatOf(TimelineRowAddress? row) =>
    row is LayerRowAddress ? trackConteRowOf(row.layerId)?.seat : null;

/// Whether [row] is a track's conte row — the address the storyboard's rail
/// stands on and lights, never a cut's own layer.
bool isTrackConteRow(TimelineRowAddress? row) => conteRowSeatOf(row) != null;

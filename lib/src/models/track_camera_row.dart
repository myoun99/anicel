import 'layer_id.dart';
import 'timeline_row_address.dart';
import 'track_id.dart';
import 'track_minted_row_id.dart';

/// THE TRACK'S CAMERA ROW (I-73 ④, 유저 2026-10-08).
///
/// 「그리고 카메라는 로컬이랑 똑같이 최상단행. cam섹션의 제일 위」 · 「카메라
/// 행 범위는 키표시/이동/레인 등 모든거 콘티패널에서 가능. 컷 클램핑만
/// 되도록」 — the storyboard panel shows the cuts' camera layers as ONE row on
/// the track's axis, at the top of the track's CAM section, the way the
/// timeline shows a cut's camera row at the top of its own.
///
/// Every cut keeps its own camera — its own layer, its own keys — and a gap
/// has no cut at all. So the ROW needs an address that is there wherever the
/// playhead stands, and no cut's layer id is one: this one, minted from the
/// track as the conte row's is ([trackConteRowId]). The rail stands on it
/// and lights it; the verbs resolve it to the camera layer of the cut the
/// session stands in — or to nothing, in a gap.
const _prefix = 'camera-row:';

LayerId trackCameraRowId(TrackId trackId) =>
    mintedTrackRowId(_prefix, trackId);

/// The track whose camera row [layerId] names; null for every other id — a
/// cut's own camera layer among them.
TrackId? trackIdOfCameraRow(LayerId layerId) =>
    trackOfMintedRowId(_prefix, layerId);

/// Whether [row] is a track's camera row — the address the storyboard's
/// rail stands on and lights, never a cut's own layer.
bool isTrackCameraRow(TimelineRowAddress? row) =>
    row is LayerRowAddress && trackIdOfCameraRow(row.layerId) != null;

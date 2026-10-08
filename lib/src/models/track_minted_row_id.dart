import 'layer_id.dart';
import 'track_id.dart';

/// A ROW THE TRACK OWNS UNDER A NAME OF ITS OWN — an id minted from the
/// track for a row no layer's id names: the V track's lane carrier
/// (`v-track:`), the track's conte rows (`conte-row:`) and its camera row
/// (`camera-row:`). The rail and the lane substrate speak [LayerId], so each
/// such row borrows one, and the verbs read the track back off it.
///
/// ★ONE mint and ONE read. Each of the three spelled 「the prefix, then the
/// track's id」 and 「starts with the prefix ⇒ the rest is the track」 for
/// itself; the third was the day to say it once (CLAUDE.md, 3의 규칙).
LayerId mintedTrackRowId(String prefix, TrackId trackId) =>
    LayerId('$prefix${trackId.value}');

/// The track [layerId] was minted for under [prefix]
/// ([mintedTrackRowId]); null for every other id.
TrackId? trackOfMintedRowId(String prefix, LayerId layerId) {
  final value = layerId.value;
  return value.startsWith(prefix)
      ? TrackId(value.substring(prefix.length))
      : null;
}

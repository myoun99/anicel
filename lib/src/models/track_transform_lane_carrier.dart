import 'layer_id.dart';
import 'track_id.dart';
import 'track_minted_row_id.dart';

/// The V track's Transform lanes ride the shared lane substrate, which
/// speaks [LayerId] — so a TRACK's lanes borrow a synthetic carrier id
/// (R4b). This is the ONE contract for minting and recognizing it: the
/// storyboard rows mint with [trackTransformLaneCarrierId], and the
/// session's lane-selection verbs recognize it with
/// [trackIdOfTransformLaneCarrier] to route onto [Track.transformTrack]
/// instead of a layer's.
const _prefix = 'v-track:';

LayerId trackTransformLaneCarrierId(TrackId trackId) =>
    mintedTrackRowId(_prefix, trackId);

/// The track behind a carrier id; null for every real layer id.
TrackId? trackIdOfTransformLaneCarrier(LayerId layerId) =>
    trackOfMintedRowId(_prefix, layerId);

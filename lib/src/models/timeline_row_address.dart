import 'layer_id.dart';
import 'track_id.dart';

/// WHICH row a timeline-grammar gesture is on.
///
/// The frame axis is shared by three surfaces (the horizontal timeline, the
/// X-sheet, the storyboard), and until now every gesture that crossed one
/// spoke [LayerId] — which is why the storyboard's cut row, whose rows are
/// TRACKS, could not mount the same gesture layer and grew a lookalike of
/// its own. The address is the one thing that actually differs: the drag
/// state machine, the block snap ([snapSpanToBlocks]) and the selection
/// display are the same question on both.
///
/// The verbs a row answers with still differ — a layer row re-times
/// exposures, a track row re-times cuts — and that split lives at the
/// session seam the address is handed to, not in the gesture.
sealed class TimelineRowAddress {
  const TimelineRowAddress();

  /// The row's identity as a widget-key fragment. Layer rows spell out the
  /// bare id — the keys that already read `…-<layerId>` keep reading that
  /// way — and track rows carry a prefix so the two namespaces cannot
  /// collide.
  String get keySuffix;
}

/// A LAYER's cells row (the timeline and X-sheet grids, the storyboard's SE
/// strips).
final class LayerRowAddress extends TimelineRowAddress {
  const LayerRowAddress(this.layerId);

  final LayerId layerId;

  @override
  String get keySuffix => layerId.value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayerRowAddress && other.layerId == layerId;

  @override
  int get hashCode => Object.hash(LayerRowAddress, layerId);

  @override
  String toString() => 'LayerRowAddress($layerId)';
}

/// A TRACK's cut row (the storyboard's V row) — the blocks are cuts on the
/// track-global frame axis.
final class TrackRowAddress extends TimelineRowAddress {
  const TrackRowAddress(this.trackId);

  final TrackId trackId;

  @override
  String get keySuffix => 'track-${trackId.value}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrackRowAddress && other.trackId == trackId;

  @override
  int get hashCode => Object.hash(TrackRowAddress, trackId);

  @override
  String toString() => 'TrackRowAddress($trackId)';
}

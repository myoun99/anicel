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

/// A LAYER's PROPERTY LANE row — a transform/effect lane, or one of their
/// group headers (R10 #19).
///
/// The third tier of the AE reading the user asked for: a cut, a layer
/// inside it, a property inside that. It is an address rather than a
/// separate selection because "which row is the verb's subject" is ONE
/// question with three answers, not three parallel states — the mistake
/// #13 made and had to undo.
///
/// A lane row is INSIDE a layer, so a verb that has no lane meaning falls
/// back to [layerId] rather than refusing: standing on a property must
/// never cost you the layer you draw on, which is exactly the hazard the
/// user named when asking for selectable fx properties.
final class LaneRowAddress extends TimelineRowAddress {
  const LaneRowAddress(this.layerId, this.laneId);

  final LayerId layerId;

  /// The lane's id within its layer ('position', an effect parameter id, or
  /// a group header's).
  final String laneId;

  @override
  String get keySuffix => '${layerId.value}-lane-$laneId';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LaneRowAddress &&
          other.layerId == layerId &&
          other.laneId == laneId;

  @override
  int get hashCode => Object.hash(LaneRowAddress, layerId, laneId);

  @override
  String toString() => 'LaneRowAddress($layerId/$laneId)';
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

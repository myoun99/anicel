import 'layer_id.dart';
import 'project.dart';
import 'track_transform_lane_carrier.dart';

/// A row's twirls: whether its property lanes are twirled down, and the
/// lane groups — Transform, an effect's header — open inside them, by lane
/// id. A layer row keeps them as `Layer.lanesExpanded` and
/// `Layer.expandedLaneGroups` (F-360); the V row, which is no layer, as its
/// track's (`Track.lanesExpanded`, `Track.expandedLaneGroups`).
typedef RowTwirls = ({bool lanesExpanded, Set<String> expandedLaneGroups});

/// [rowId]'s twirls when it is a TRACK's own row — the V row, by its lane
/// carrier ([trackTransformLaneCarrierId]), or one of the track's S rows —
/// and null for every other row: a row a cut holds is twirled on its head
/// (`headMirrorTargets`), and a track's own row is in none.
RowTwirls? trackRowTwirlsOf(Project project, LayerId rowId) {
  final carried = trackIdOfTransformLaneCarrier(rowId);
  for (final track in project.tracks) {
    if (track.id == carried) {
      return (
        lanesExpanded: track.lanesExpanded,
        expandedLaneGroups: track.expandedLaneGroups,
      );
    }
    for (final row in track.seLayers) {
      if (row.id == rowId) {
        return (
          lanesExpanded: row.lanesExpanded,
          expandedLaneGroups: row.expandedLaneGroups,
        );
      }
    }
  }
  return null;
}

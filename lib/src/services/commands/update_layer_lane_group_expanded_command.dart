import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../project_repository.dart';
import 'link_mirrored_layer_field_command.dart';

/// Twirls ONE lane group open or shut inside a row's twirl-down — its
/// Transform, an effect's header (`Layer.expandedLaneGroups`) — on every row
/// of its head, as the row's own twirl is ([UpdateLayerLanesExpandedCommand]).
/// A camera's lanes have no group to twirl — the row is their header (㉙) —
/// so the track's cameras are not a head of this.
///
/// ⚠️What it reads and writes is [laneId]'s membership, not the row's whole
/// set: another group twirled after this one keeps its own state when this
/// one is undone.
///
/// ↩️The group twirl was written outside history (`RailView`), the one
/// fold that did not undo. F-360 moved it onto the row, where it undoes as
/// the folds beside it do — 유저 2026-08-29: 「접기도 마찬가지야. 폴더든
/// 어태치든」.
class UpdateLayerLaneGroupExpandedCommand
    extends LinkMirroredLayerFieldCommand<bool> {
  UpdateLayerLaneGroupExpandedCommand({
    required super.repository,
    required super.cutId,
    required super.layerId,
    required String laneId,
    required bool expanded,
  }) : super(
         value: expanded,
         fieldName: 'expandedLaneGroups',
         read: (layer) => layer.expandedLaneGroups.contains(laneId),
         write: _writeOf(laneId),
       );

  static LayerFieldWrite<bool> _writeOf(String laneId) =>
      (
        ProjectRepository repository, {
        required CutId cutId,
        required LayerId layerId,
        required bool value,
      }) => repository.updateLayer(
        layerId: layerId,
        update: (layer) => layer.expandedLaneGroups.contains(laneId) == value
            ? layer
            : layer.copyWith(
                expandedLaneGroups: value
                    ? {...layer.expandedLaneGroups, laneId}
                    : ({...layer.expandedLaneGroups}..remove(laneId)),
              ),
      );
}

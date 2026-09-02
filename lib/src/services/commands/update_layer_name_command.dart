import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../project_repository.dart';
import 'link_mirrored_layer_field_command.dart';

/// Renames a layer — and, when it is LINKED, every member of its group
/// in the same command: renaming never breaks a link, it propagates
/// (the "이름이 같으면 같은 그림" invariant maintains itself). One undo
/// step restores every member's previous name.
class UpdateLayerNameCommand extends LinkMirroredLayerFieldCommand<String> {
  UpdateLayerNameCommand({
    required super.repository,
    required super.cutId,
    required super.layerId,
    required String name,
  }) : super(
         value: name,
         fieldName: 'name',
         read: (layer) => layer.name,
         write: _writeName,
       );

  static void _writeName(
    ProjectRepository repository, {
    required CutId cutId,
    required LayerId layerId,
    required String value,
  }) => repository.updateLayerName(cutId: cutId, layerId: layerId, name: value);
}

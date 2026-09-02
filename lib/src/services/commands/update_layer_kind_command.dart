import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../project_repository.dart';
import 'link_mirrored_layer_field_command.dart';

/// Changes a layer's kind — and, when it is LINKED, every member of its
/// group in the same command (kind is a shared property like name/mark:
/// linked members are "the same layer" seen from different cuts). One
/// undo step restores every member's previous kind.
class UpdateLayerKindCommand extends LinkMirroredLayerFieldCommand<LayerKind> {
  UpdateLayerKindCommand({
    required super.repository,
    required super.cutId,
    required super.layerId,
    required LayerKind kind,
  }) : super(
         value: kind,
         fieldName: 'kind',
         read: (layer) => layer.kind,
         write: _writeKind,
       );

  static void _writeKind(
    ProjectRepository repository, {
    required CutId cutId,
    required LayerId layerId,
    required LayerKind value,
  }) => repository.updateLayerKind(cutId: cutId, layerId: layerId, kind: value);
}

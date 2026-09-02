import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../../models/layer_mark.dart';
import '../project_repository.dart';
import 'link_mirrored_layer_field_command.dart';

/// Updates a layer's mark — mirrored across its link group ("레인만
/// 각자, 나머지는 하나": the mark is shared identity). One undo step.
class UpdateLayerMarkCommand extends LinkMirroredLayerFieldCommand<LayerMark> {
  UpdateLayerMarkCommand({
    required super.repository,
    required super.cutId,
    required super.layerId,
    required LayerMark mark,
  }) : super(
         value: mark,
         fieldName: 'mark',
         read: (layer) => layer.mark,
         write: _writeMark,
       );

  static void _writeMark(
    ProjectRepository repository, {
    required CutId cutId,
    required LayerId layerId,
    required LayerMark value,
  }) => repository.updateLayerMark(cutId: cutId, layerId: layerId, mark: value);
}

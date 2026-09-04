import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../project_repository.dart';
import 'layer_field_command.dart';

/// Toggles a layer's fill-reference flag (R20-C2) — one undo step.
class UpdateLayerFillReferenceCommand extends LayerFieldCommand<bool> {
  UpdateLayerFillReferenceCommand({
    required ProjectRepository repository,
    required CutId cutId,
    required LayerId layerId,
    required bool isFillReference,
  }) : super(
         repository: repository,
         layerId: layerId,
         value: isFillReference,
         field: (
           name: 'fill-reference flag',
           label: null,
           read: (layer) => layer.isFillReference,
           write: (value) => repository.updateLayerFillReference(
             cutId: cutId,
             layerId: layerId,
             isFillReference: value,
           ),
         ),
       );
}

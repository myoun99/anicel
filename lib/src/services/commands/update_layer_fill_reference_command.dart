import '../../models/cut_id.dart';
import 'layer_field_command.dart';

/// Toggles a layer's fill-reference flag (R20-C2) — one undo step.
class UpdateLayerFillReferenceCommand extends LayerFieldCommand<bool> {
  UpdateLayerFillReferenceCommand({
    required super.repository,
    required CutId cutId,
    required super.layerId,
    required bool isFillReference,
  }) : super(
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

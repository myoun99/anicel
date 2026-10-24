import '../../models/cut_id.dart';
import 'layer_field_command.dart';

/// Sets a layer's clip to the layer below (I-92) — one undo step.
class UpdateLayerClipCommand extends LayerFieldCommand<bool> {
  UpdateLayerClipCommand({
    required super.repository,
    required CutId cutId,
    required super.layerId,
    required bool clipsToBelow,
  }) : super(
         value: clipsToBelow,
         field: (
           name: 'clip to layer below',
           label: null,
           read: (layer) => layer.clipsToBelow,
           write: (value) => repository.updateLayerClip(
             cutId: cutId,
             layerId: layerId,
             clipsToBelow: value,
           ),
         ),
       );
}

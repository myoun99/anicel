import '../../models/cut_id.dart';
import '../../models/layer_effect.dart';
import '../../models/layer_id.dart';
import '../project_repository.dart';
import 'layer_field_command.dart';

/// Replaces a layer's whole EFFECT CHAIN in one undo step (R6).
///
/// Adding, removing, re-parameterizing and keyframing an effect are all
/// computed as pure functions on the chain and committed here — the same
/// shape [UpdateLayerTransformCommand] gives the transform lanes, so one
/// lane drag is one undo whichever kind of FX it edited.
class UpdateLayerEffectsCommand extends LayerFieldCommand<List<LayerEffect>> {
  UpdateLayerEffectsCommand({
    required ProjectRepository repository,
    required CutId cutId,
    required LayerId layerId,
    required List<LayerEffect> effects,
    String description = 'Edit layer effects',
  }) : super(
         repository: repository,
         layerId: layerId,
         value: effects,
         field: (
           name: 'effects',
           label: description,
           read: (layer) => layer.effects,
           write: (value) => repository.updateLayerEffects(
             cutId: cutId,
             layerId: layerId,
             effects: value,
           ),
         ),
       );
}

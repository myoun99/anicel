import '../../models/se_sound.dart';
import 'layer_field_command.dart';

/// Replaces an SE row's SOUND — its volume keys and its pan — in one undo
/// step: the lane edits of its 「오디오」 group (I-140) are computed as pure
/// functions on the sound, then committed here, as a reference fx's keys
/// are (`UpdateLayerReferenceFxCommand`).
class UpdateLayerSeSoundCommand extends LayerFieldCommand<SeSound> {
  UpdateLayerSeSoundCommand({
    required super.repository,
    required super.layerId,
    required SeSound seSound,
    String description = 'Edit SE sound',
  }) : super(
         value: seSound,
         field: (
           name: 'sound',
           label: description,
           read: (layer) => layer.seSound,
           write: (value) => repository.updateLayer(
             layerId: layerId,
             update: (layer) => layer.copyWith(seSound: value),
           ),
         ),
       );
}

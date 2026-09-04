import '../../models/audio_clip.dart';
import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../project_repository.dart';
import 'layer_field_command.dart';

/// Replaces an SE layer's audio clip list in one undo step.
class UpdateLayerAudioClipsCommand extends LayerFieldCommand<List<AudioClip>> {
  /// [cutId] is bookkeeping only — the write is layer-addressed (anywhere
  /// lookup); null when the edit lands from a gap (no active cut, B6). The
  /// SE rows are TRACK fixtures, not cut layers.
  UpdateLayerAudioClipsCommand({
    required ProjectRepository repository,
    required CutId? cutId,
    required LayerId layerId,
    required List<AudioClip> audioClips,
    String description = 'Edit audio clips',
  }) : super(
         repository: repository,
         layerId: layerId,
         value: audioClips,
         field: (
           name: 'audio clips',
           label: description,
           read: (layer) => layer.audioClips,
           write: (value) => repository.updateLayerAudioClips(
             cutId: cutId,
             layerId: layerId,
             audioClips: value,
           ),
         ),
       );
}

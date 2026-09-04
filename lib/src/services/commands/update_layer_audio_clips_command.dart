import '../../models/audio_clip.dart';
import '../../models/cut_id.dart';
import 'layer_field_command.dart';

/// Replaces an SE layer's audio clip list in one undo step.
class UpdateLayerAudioClipsCommand extends LayerFieldCommand<List<AudioClip>> {
  /// [cutId] is bookkeeping only — the write is layer-addressed (anywhere
  /// lookup); null when the edit lands from a gap (no active cut, B6). The
  /// SE rows are TRACK fixtures, not cut layers.
  UpdateLayerAudioClipsCommand({
    required super.repository,
    required CutId? cutId,
    required super.layerId,
    required List<AudioClip> audioClips,
    String description = 'Edit audio clips',
  }) : super(
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

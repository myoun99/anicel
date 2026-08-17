import '../../models/audio_clip.dart';
import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../command.dart';
import '../project_lookup.dart';
import '../project_repository.dart';

/// Replaces an SE layer's audio clip list in one undo step.
class UpdateLayerAudioClipsCommand implements Command {
  UpdateLayerAudioClipsCommand({
    required this.repository,
    required this.cutId,
    required this.layerId,
    required this.audioClips,
    this.description = 'Edit audio clips',
  });

  final ProjectRepository repository;

  /// Bookkeeping only — the write is layer-addressed (anywhere lookup);
  /// null when the edit lands from a gap (no active cut, B6).
  final CutId? cutId;
  final LayerId layerId;
  final List<AudioClip> audioClips;

  @override
  final String description;

  List<AudioClip>? _previousClips;
  bool _hasExecuted = false;

  @override
  void execute() {
    // Anywhere lookup: the SE rows are TRACK fixtures, not cut layers.
    final layer = requireLayerAnywhere(repository.requireProject(), layerId);
    _previousClips ??= layer.audioClips;

    repository.updateLayerAudioClips(
      cutId: cutId,
      layerId: layerId,
      audioClips: audioClips,
    );
    _hasExecuted = true;
  }

  @override
  void undo() {
    final previousClips = _previousClips;
    if (!_hasExecuted || previousClips == null) {
      throw StateError('Command has not been executed.');
    }

    requireLayerAnywhere(repository.requireProject(), layerId);
    repository.updateLayerAudioClips(
      cutId: cutId,
      layerId: layerId,
      audioClips: previousClips,
    );
  }
}

import '../../models/layer_effect.dart';
import '../../models/track_id.dart';
import '../command.dart';
import '../project_repository.dart';

/// Replaces the V track's EFFECT CHAIN in one undo step.
///
/// A track is not a layer, so this is not [UpdateLayerEffectsCommand] with a
/// different id: there is no 겸용 link group to mirror into (a track is one
/// row of the film, held once) and no per-use values to merge. The chain is
/// simply the track's, keyed on the global axis like its pose.
///
/// It carries the WHOLE chain rather than an edit, the same shape the layer
/// command uses: one gesture may add, re-order and re-key at once, and the
/// lane editors all hand back a finished chain.
class UpdateTrackEffectsCommand implements Command {
  UpdateTrackEffectsCommand({
    required this.repository,
    required this.trackId,
    required this.effects,
    this.description = 'Edit track effects',
  });

  final ProjectRepository repository;
  final TrackId trackId;
  final List<LayerEffect> effects;

  @override
  final String description;

  List<LayerEffect>? _before;
  bool _hasExecuted = false;

  @override
  void execute() {
    _before ??= _currentEffects();
    repository.updateTrackEffects(trackId: trackId, effects: effects);
    _hasExecuted = true;
  }

  List<LayerEffect> _currentEffects() {
    for (final track in repository.requireProject().tracks) {
      if (track.id == trackId) {
        return track.effects;
      }
    }
    throw StateError('Track not found: $trackId');
  }

  @override
  void undo() {
    final before = _before;
    if (!_hasExecuted || before == null) {
      throw StateError('Command has not been executed.');
    }
    repository.updateTrackEffects(trackId: trackId, effects: before);
  }
}

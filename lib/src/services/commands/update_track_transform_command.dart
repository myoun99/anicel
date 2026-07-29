import '../../models/project.dart';
import '../../models/track_id.dart';
import '../../models/transform_track.dart';
import '../command.dart';
import '../project_repository.dart';

/// Replaces a TRACK's transform lanes (R4: the V effects on the global
/// axis — fades key the opacity lane) in one undo step.
class UpdateTrackTransformCommand implements Command {
  UpdateTrackTransformCommand({
    required this.repository,
    required this.trackId,
    required this.transformTrack,
    required this.description,
  });

  final ProjectRepository repository;
  final TrackId trackId;
  final TransformTrack transformTrack;

  @override
  final String description;

  Project? _previousProject;

  @override
  void execute() {
    _previousProject = repository.requireProject();
    repository.updateTrackTransform(
      trackId: trackId,
      transformTrack: transformTrack,
    );
  }

  @override
  void undo() {
    final previousProject = _previousProject;
    if (previousProject == null) {
      throw StateError('Command has not been executed.');
    }

    repository.replaceProject(previousProject);
  }
}

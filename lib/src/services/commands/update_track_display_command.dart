import '../../models/project.dart';
import '../../models/track_id.dart';
import '../command.dart';
import '../project_repository.dart';

/// Writes a TRACK's display properties — its static opacity and its fx
/// master (R9 #21) — in one undo step. Null leaves that property alone, so
/// the opacity drag's release and the fx switch share the command.
class UpdateTrackDisplayCommand implements Command {
  UpdateTrackDisplayCommand({
    required this.repository,
    required this.trackId,
    required this.description,
    this.opacity,
    this.fxEnabled,
  });

  final ProjectRepository repository;
  final TrackId trackId;
  final double? opacity;
  final bool? fxEnabled;

  @override
  final String description;

  Project? _previousProject;

  @override
  void execute() {
    _previousProject = repository.requireProject();
    repository.updateTrackDisplay(
      trackId: trackId,
      opacity: opacity,
      fxEnabled: fxEnabled,
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

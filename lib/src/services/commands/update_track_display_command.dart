import '../../models/project.dart';
import '../../models/track_id.dart';
import '../command.dart';
import '../project_repository.dart';

/// Writes a TRACK's fx master (R9 #21) in one undo step.
///
/// ↩️It carried the track's static opacity too, a null leaving either
/// alone so the opacity drag's release and the fx switch shared it. The
/// opacity went with the V row's bar (I-73, 2026-10-08), and the switch is
/// what a track's display has left.
class UpdateTrackDisplayCommand implements Command {
  UpdateTrackDisplayCommand({
    required this.repository,
    required this.trackId,
    required this.description,
    required this.fxEnabled,
  });

  final ProjectRepository repository;
  final TrackId trackId;
  final bool fxEnabled;

  @override
  final String description;

  Project? _previousProject;

  @override
  void execute() {
    _previousProject = repository.requireProject();
    repository.updateTrackDisplay(trackId: trackId, fxEnabled: fxEnabled);
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

import '../../models/cut.dart';
import '../../models/project.dart';
import '../../models/track_id.dart';
import '../command.dart';
import '../project_repository.dart';
import 'transitions_ride_the_cuts.dart';

class AddCutCommand implements Command {
  AddCutCommand({
    required this.repository,
    required this.trackId,
    required this.cut,
  });

  final ProjectRepository repository;
  final TrackId trackId;
  final Cut cut;

  Project? _previousProject;

  @override
  String get description => 'Add cut ${cut.name}';

  late final TransitionsRideTheCuts _ride = TransitionsRideTheCuts(repository);

  /// Appending moves no cut, so the ride carries nothing — it is here
  /// because every command that writes a cut layout takes it, and the one
  /// that "cannot move anything" is the one a later edit makes move.
  /// The undo puts the whole project back, rows included.
  @override
  void execute() {
    _previousProject = repository.requireProject();
    _ride.carry(() => repository.addCut(trackId: trackId, cut: cut));
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

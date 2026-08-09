import '../../models/project.dart';
import '../command.dart';
import '../project_repository.dart';

/// Moves a track within the project's list — the storyboard's V-row drag
/// (R5 #9).
///
/// The list order is the COMPOSITE order (see
/// [ProjectRepository.reorderTrack]), so this is a picture change, not a
/// bookkeeping one, and belongs on the undo stack like any other.
class ReorderTrackCommand implements Command {
  ReorderTrackCommand({
    required this.repository,
    required this.fromIndex,
    required this.toIndex,
    required this.trackName,
  });

  final ProjectRepository repository;
  final int fromIndex;
  final int toIndex;
  final String trackName;

  Project? _previousProject;

  @override
  String get description => 'Move track $trackName';

  @override
  void execute() {
    _previousProject = repository.requireProject();
    repository.reorderTrack(fromIndex: fromIndex, toIndex: toIndex);
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

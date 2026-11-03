import '../../models/project_timeline.dart';
import '../../models/timeline_id.dart';
import '../editing/editing_session_state.dart';
import '../history_manager.dart';
import '../project_repository.dart';
import 'change_timelines_command.dart';

/// THE TIMELINE COMMANDS (I-150): a timeline made, opened, named or
/// deleted — each one undo step ([ChangeTimelinesCommand]), none where
/// nothing would change.
class TimelineCommands {
  TimelineCommands({
    required this.repository,
    required this.editingSession,
    required this.historyManager,
  });

  final ProjectRepository repository;
  final EditingSessionState editingSession;
  final HistoryManager historyManager;

  List<ProjectTimeline> get _timelines => repository.requireProject().timelines;

  /// [made] at the end of the list, and opened.
  void add(ProjectTimeline made) =>
      _change('Add timeline', [..._timelines, made], made.id);

  void open(TimelineId id) {
    final project = repository.requireProject();
    if (id != project.currentTimelineId &&
        project.timelines.any((timeline) => timeline.id == id)) {
      _change('Open timeline', project.timelines, id);
    }
  }

  /// [id] named [name] — a blank one gives it back the name its number
  /// gives.
  void rename(TimelineId id, String name) {
    final given = name.trim().isEmpty ? null : name.trim();
    final project = repository.requireProject();
    if (project.timelines.any(
      (timeline) => timeline.id == id && timeline.name != given,
    )) {
      _change('Rename timeline', [
        for (final timeline in project.timelines)
          if (timeline.id == id) timeline.named(given) else timeline,
      ], project.currentTimelineId);
    }
  }

  /// [id] gone from the list — never the last one. The open one gone opens
  /// the one that takes its place, the one before it at the end.
  void delete(TimelineId id) {
    final project = repository.requireProject();
    final at = project.timelines.indexWhere((timeline) => timeline.id == id);
    if (at < 0 || project.timelines.length < 2) {
      return;
    }
    final left = [...project.timelines]..removeAt(at);
    _change(
      'Delete timeline',
      left,
      id == project.currentTimelineId
          ? left[at < left.length ? at : left.length - 1].id
          : project.currentTimelineId,
    );
  }

  void _change(
    String description,
    List<ProjectTimeline> timelines,
    TimelineId current,
  ) => historyManager.execute(
    ChangeTimelinesCommand(
      repository: repository,
      editingSession: editingSession,
      description: description,
      timelines: timelines,
      current: current,
    ),
  );
}

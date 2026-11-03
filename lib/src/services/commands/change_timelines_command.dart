import '../../models/cut_id.dart';
import '../../models/project_timeline.dart';
import '../../models/timeline_id.dart';
import '../command.dart';
import '../editing/editing_session_state.dart';
import '../project_repository.dart';

/// A change of the project's TIMELINES (I-150) — one made, named or
/// deleted, or another opened — as ONE undo step, and where the user stands
/// with it: opening another stands on its first cut, and the undo stands
/// back where the change found them. The track selected is the session's
/// to reconcile: a timeline holds one V track, the one it falls back to.
///
/// 🗣️I-150-Q1 (recommended a; the user's answer pending): opening another
/// timeline is a step of its own. An undo after it opens the one before
/// first, so the edit the next undo takes back is the one on screen.
class ChangeTimelinesCommand implements Command {
  ChangeTimelinesCommand({
    required this.repository,
    required this.editingSession,
    required this.description,
    required this.timelines,
    required this.current,
  });

  final ProjectRepository repository;
  final EditingSessionState editingSession;

  @override
  final String description;

  /// The list after the step: its order, and each one's name.
  final List<ProjectTimeline> timelines;

  /// The timeline open after the step.
  final TimelineId current;

  _Standing? _before;

  @override
  void execute() {
    final project = repository.requireProject();
    _before ??= (
      timelines: project.timelines,
      current: project.currentTimelineId,
      cut: editingSession.activeCutId,
      gap: editingSession.gapGlobalFrame,
    );
    _lay(timelines, current);
    if (current == project.currentTimelineId) {
      return;
    }
    final opened = repository.requireProject().tracks;
    _stand(
      cut: opened.expand((track) => track.cuts).firstOrNull?.id,
      gap: null,
    );
  }

  @override
  void undo() {
    final before =
        _before ?? (throw StateError('Command has not been executed.'));
    _lay(before.timelines, before.current);
    _stand(cut: before.cut, gap: before.gap);
  }

  void _lay(List<ProjectTimeline> timelines, TimelineId current) =>
      repository.updateProject(
        (project) => project.copyWith(
          timelines: timelines,
          currentTimelineId: current,
        ),
      );

  void _stand({required CutId? cut, required int? gap}) => editingSession
    ..setActiveCutId(cut)
    ..gapGlobalFrame = gap;
}

typedef _Standing = ({
  List<ProjectTimeline> timelines,
  TimelineId current,
  CutId? cut,
  int? gap,
});

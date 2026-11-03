import '../../models/cut_id.dart';
import '../../models/project.dart';
import '../../models/project_timeline.dart';
import '../../models/timeline_id.dart';
import '../../models/track_id.dart';
import '../command.dart';
import '../editing/active_cut_helpers.dart' show trackIdOfCut;
import '../editing/editing_session_state.dart';
import '../project_repository.dart';

/// A change of the project's TIMELINES (I-150) — one made, named or
/// deleted, or another opened — as ONE undo step, and where the user stands
/// with it: opening another stands on its first cut, and the undo stands
/// back where the change found them.
///
/// 🗣️I-150-Q1 (recommended a; the user's answer pending): opening another
/// timeline is a step of its own. An undo after it opens the one before
/// first, so the edit the next undo takes back is the one on screen.
///
/// ⚠️Only what changed goes back. The list is laid out as [timelines] says
/// — its order, its names, the ones made and the ones gone — over each
/// timeline as it stands when the step runs, so what happened to one since
/// is kept ([_laidOut]).
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
      track: editingSession.selectedTrackId,
      gap: editingSession.gapGlobalFrame,
    );
    _lay(timelines, current);
    if (current == project.currentTimelineId) {
      return;
    }
    final opened = repository.requireProject();
    final cut = opened.tracks.expand((track) => track.cuts).firstOrNull?.id;
    _stand(
      cut: cut,
      track: trackIdOfCut(opened, cut) ?? opened.tracks.firstOrNull?.id,
      gap: null,
    );
  }

  @override
  void undo() {
    final before =
        _before ?? (throw StateError('Command has not been executed.'));
    _lay(before.timelines, before.current);
    _stand(cut: before.cut, track: before.track, gap: before.gap);
  }

  void _lay(List<ProjectTimeline> order, TimelineId current) =>
      repository.updateProject(
        (project) => project.copyWith(
          timelines: _laidOut(order, project),
          currentTimelineId: current,
        ),
      );

  void _stand({
    required CutId? cut,
    required TrackId? track,
    required int? gap,
  }) => editingSession
    ..setActiveCutId(cut)
    ..setSelectedTrackId(track)
    ..gapGlobalFrame = gap;

  /// [order]'s timelines, each as [project] holds it now where it holds it
  /// — named as [order] names it.
  static List<ProjectTimeline> _laidOut(
    List<ProjectTimeline> order,
    Project project,
  ) {
    final now = {
      for (final timeline in project.timelines) timeline.id: timeline,
    };
    return [
      for (final timeline in order)
        switch (now[timeline.id]) {
          null => timeline,
          final held when held.name == timeline.name => held,
          final held => held.named(timeline.name),
        },
    ];
  }
}

typedef _Standing = ({
  List<ProjectTimeline> timelines,
  TimelineId current,
  CutId? cut,
  TrackId? track,
  int? gap,
});

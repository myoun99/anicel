import '../../models/layer_link_registry.dart';
import '../../models/project_timeline.dart';
import '../../models/timeline_id.dart';
import '../brush_frame_store.dart';
import '../editing/cut_duplicate_helpers.dart'
    show
        TimelineCopyIds,
        duplicateTimelineAsIndependentCopy,
        linkGroupsOfACopy;
import '../editing/editing_session_state.dart';
import '../editing/links_without_cuts.dart';
import '../history_manager.dart';
import '../project_repository.dart';
import 'change_timelines_command.dart';
import 'cut_command_input_planner.dart' show planDuplicateTimelineCommandInput;

/// THE TIMELINE COMMANDS (I-150): a timeline made, copied, opened, named or
/// deleted — each one undo step ([ChangeTimelinesCommand]), none where
/// nothing would change.
class TimelineCommands {
  TimelineCommands({
    required this.repository,
    required this.editingSession,
    required this.historyManager,
    this.brushFrameStore,
  });

  final ProjectRepository repository;
  final EditingSessionState editingSession;
  final HistoryManager historyManager;

  /// Where a deleted timeline's canonical cels re-key.
  final BrushFrameStore? brushFrameStore;

  List<ProjectTimeline> get _timelines => repository.requireProject().timelines;

  /// [made] at the end of the list, and opened.
  void add(ProjectTimeline made) =>
      _change('Add timeline', [..._timelines, made], made.id);

  /// [id] copied right after it in the list, named [name], and opened: its
  /// tracks, cuts, rows and cels under ids of their own, and the rows
  /// linked to each other in it linked to each other's copies — never to
  /// the source (I-150-Q2, recommended a). What it was planned with comes
  /// back for the pictures to follow; null where the project holds no [id].
  TimelineCopyIds? duplicate(TimelineId id, String name) {
    final project = repository.requireProject();
    final at = project.timelines.indexWhere((timeline) => timeline.id == id);
    if (at < 0) {
      return null;
    }
    final source = project.timelines[at];
    final ids = planDuplicateTimelineCommandInput(
      project: project,
      source: source,
    );
    final copy = duplicateTimelineAsIndependentCopy(
      source: source,
      ids: ids,
      number: timelineNumberAfter(project.timelines),
      name: _given(name),
    );
    final registry = project.linkRegistry;
    _change(
      'Duplicate timeline',
      [...project.timelines]..insert(at + 1, copy),
      copy.id,
      links: (
        registry: LayerLinkRegistry(
          groups: [...registry.groups, ...linkGroupsOfACopy(registry, ids)],
        ),
        rekeys: const [],
      ),
    );
    return ids;
  }

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
    final given = _given(name);
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

  /// [id] gone from the list — never the last one — and its cuts from the
  /// link table, as a deleted cut's are. The open one gone opens the one
  /// that takes its place, the one before it at the end.
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
      links: linksWithoutCuts(project, {
        for (final track in project.timelines[at].tracks)
          for (final cut in track.cuts) cut.id,
      }),
    );
  }

  /// [name] as a timeline is named: trimmed, and null when blank.
  static String? _given(String name) =>
      name.trim().isEmpty ? null : name.trim();

  /// One step to [timelines] with [current] open — and to [links]' table,
  /// its cels re-keyed, where the step changes it.
  void _change(
    String description,
    List<ProjectTimeline> timelines,
    TimelineId current, {
    ({LayerLinkRegistry registry, List<CelRekey> rekeys})? links,
  }) => historyManager.execute(
    ChangeTimelinesCommand(
      repository: repository,
      editingSession: editingSession,
      description: description,
      timelines: timelines,
      current: current,
      links: links?.registry,
      rekeys: links?.rekeys ?? const [],
      brushFrameStore: brushFrameStore,
    ),
  );
}

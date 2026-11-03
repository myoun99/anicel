import '../../controllers/default_project_helpers.dart' show newTimelineIn;
import '../../models/project_timeline.dart';
import '../../models/timeline_id.dart';
import '../../services/commands/timeline_commands.dart';
import '../../services/editing/default_cut_helpers.dart'
    show defaultCutCanvasSize;
import 'layer_id_mint.dart';
import 'session_roles.dart';

/// THE TIMELINE VERBS (I-150) — the timeline list's: a new one, another
/// opened, one named or deleted. Each is a step of the history
/// ([TimelineCommands]), and one that opens another timeline moves where
/// the user stands as a command that switches cuts does: walked off first
/// (I-41), the cut controllers re-read after.
class TimelineVerbs {
  TimelineVerbs({
    required ProjectAccess project,
    required TimelineAccess timeline,
    required ChangeSink changes,
    required LayerIdMint layerIds,
  }) : _project = project,
       _changes = changes,
       _layerIds = layerIds,
       _commands = TimelineCommands(
         repository: project.repository,
         editingSession: timeline.editingSession,
         historyManager: project.historyManager,
       );

  final ProjectAccess _project;
  final ChangeSink _changes;
  final LayerIdMint _layerIds;
  final TimelineCommands _commands;

  List<ProjectTimeline> get timelines =>
      _project.repository.requireProject().timelines;

  TimelineId get currentTimelineId =>
      _project.repository.requireProject().currentTimelineId;

  /// A new timeline at the end of the list, opened: a new project's track,
  /// its cut the size a new cut would be here.
  void addTimeline() => _moving(
    () => _commands.add(
      newTimelineIn(
        _project.repository.requireProject(),
        rowA: _layerIds.mint(),
        canvasSize:
            _project.activeCutOrNull?.canvasSize ?? defaultCutCanvasSize,
      ),
    ),
  );

  void openTimeline(TimelineId id) => _moving(() => _commands.open(id));

  void renameTimeline(TimelineId id, String name) {
    _commands.rename(id, name);
    _changes.notifyChanged();
  }

  void deleteTimeline(TimelineId id) => _moving(() => _commands.delete(id));

  void _moving(void Function() step) {
    final before = _project.repository.currentProject;
    _project.historyManager.places.leave();
    step();
    if (identical(before, _project.repository.currentProject)) {
      return;
    }
    _changes.refreshAfterCutCommand(preferredFrameIndex: 0);
    _changes.notifyChanged();
  }
}

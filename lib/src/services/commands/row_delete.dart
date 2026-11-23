import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../../models/project.dart';
import '../../models/track_id.dart';
import '../brush_frame_store.dart';
import '../editing/editing_session_state.dart';
import '../history_manager.dart';
import '../project_lookup.dart';
import '../project_repository.dart';
import '../repository_step_scope.dart';
import 'cut_command_coordinator.dart';
import 'track_se_layer_commands.dart';

/// One row's delete, where the row lives: an S row off its track [trackId]
/// — while the track keeps more than its floor of two — any other row in
/// [cutId], whose floors [CutCommandCoordinator.deleteLayer] asks.
///
/// 🗣️F-359 (유저 2026-10-14): 「s행은 삭제창통해 삭제해도 삭제가안됨」.
/// ↩️Only the active row's delete took an S row off its track; the
/// selection's — the one the delete window commits — handed it to the
/// cut's, which holds no S row and refused it.
void deleteRow(
  CutCommandCoordinator commands, {
  required CutId cutId,
  required TrackId trackId,
  required LayerId layerId,
}) {
  final project = commands.repository.requireProject();
  final track = project.tracks.firstWhere((track) => track.id == trackId);
  if (!track.seLayers.any((row) => row.id == layerId)) {
    commands.deleteLayer(cutId: cutId, layerId: layerId);
    return;
  }
  if (track.seLayers.length > 2) {
    commands.historyManager.execute(
      RemoveTrackSeLayerCommand(
        repository: commands.repository,
        trackId: trackId,
        layerId: layerId,
      ),
    );
  }
}

/// Deletes [ids] — rows of [cutId], or S rows of [trackId] — each by its
/// own [deleteRow], in the order given, as ONE undo step called [step].
///
/// A row an earlier delete took along is not asked for again: gone with
/// its link (a row and the copy pasted linked beside it, both selected),
/// it would be found nowhere, and the throw lost the step — the walk over
/// a folder's rows asks the same ([CutCommandCoordinator.deleteLayer]).
/// 🔎Card a-row-pasted-linked-takes-its-source-when-deleted (검증 11-23).
void deleteRows(
  CutCommandCoordinator commands, {
  required CutId cutId,
  required TrackId trackId,
  required List<LayerId> ids,
  required String step,
}) {
  commands.historyManager.runAsOneStep(step, () {
    for (final layerId in ids) {
      final project = commands.repository.requireProject();
      if (layerAnywhereOrNull(project, layerId) != null) {
        deleteRow(commands, cutId: cutId, trackId: trackId, layerId: layerId);
      }
    }
  });
}

/// Every row [deleteRows] of [ids] takes, in every cut: read off that
/// delete itself, run on a copy of [project] — the rows named, what they
/// take along, and their selves in other cuts, by the delete's own laws
/// and only those.
///
/// 🚨THE WINDOW ASKS THE DELETE, NOT A SECOND ACCOUNT OF IT (card
/// a-row-pasted-linked-takes-its-source-when-deleted, 검증 11-23). The
/// session had restated the delete's cascade inside the cut — a folder's
/// rows, a base's attach rows — and the delete reaches further: a linked
/// row's group, a row of a track's conte in every cut. A row pasted linked
/// into its own cut went with its source, and the window listed the copy
/// alone. Run on a copy, the answer is the delete's, whatever it comes to
/// take.
Set<LayerId> rowsDeleteRowsTakes(
  Project project, {
  required CutId cutId,
  required TrackId trackId,
  required List<LayerId> ids,
}) {
  if (ids.isEmpty) {
    return const {};
  }
  final repository = ProjectRepository(initialProject: project);
  final cels = BrushFrameStore();
  final history = HistoryManager()
    ..scope = RepositoryStepScope(repository, cels: cels);
  try {
    final copy = repository.requireProject();
    deleteRows(
      CutCommandCoordinator(
        repository: repository,
        editingSession: EditingSessionState.forProject(copy),
        historyManager: history,
      ),
      cutId: cutId,
      trackId: trackId,
      ids: ids,
      step: 'What a delete takes',
    );
    final left = _rowsOf(repository.requireProject());
    return _rowsOf(copy).difference(left);
  } finally {
    history.dispose();
    cels.dispose();
  }
}

Set<LayerId> _rowsOf(Project project) => {
  for (final (:layer, track: _, cut: _) in projectLayersWithOwners(project))
    layer.id,
};

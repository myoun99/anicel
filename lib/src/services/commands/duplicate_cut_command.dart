import '../editing/cut_duplicate_helpers.dart';
import '../editing/editing_session_state.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/frame_id.dart';
import '../../models/layer_id.dart';
import '../../models/track_id.dart';
import '../command.dart';
import '../project_lookup.dart';
import '../project_repository.dart';

class DuplicateCutCommand implements Command {
  DuplicateCutCommand({
    required this.repository,
    required this.editingSession,
    required this.sourceCutId,
    required this.targetTrackId,
    required this.newCutId,
    required this.newName,
    required this.layerIdMap,
    required this.frameIdMap,
    this.index,
  });

  final ProjectRepository repository;
  final EditingSessionState editingSession;
  final CutId sourceCutId;
  final TrackId targetTrackId;
  final CutId newCutId;
  final String newName;
  final Map<LayerId, LayerId> layerIdMap;
  final Map<FrameId, FrameId> frameIdMap;
  final int? index;

  CutId? _previousActiveCutId;
  Cut? _duplicatedCut;
  bool _hasExecuted = false;

  @override
  String get description => 'Duplicate cut $sourceCutId';

  @override
  void execute() {
    _previousActiveCutId = editingSession.activeCutId;
    final duplicatedCut = _duplicatedCut ??= duplicateCutAsIndependentCopy(
      source: requireCut(repository.requireProject(), sourceCutId),
      newCutId: newCutId,
      newName: newName,
      layerIdMap: layerIdMap,
      frameIdMap: frameIdMap,
    );

    repository.insertCut(
      trackId: targetTrackId,
      cut: duplicatedCut,
      index: index,
    );
    editingSession.setActiveCutId(duplicatedCut.id);
    _hasExecuted = true;
  }

  @override
  void undo() {
    final previousActiveCutId = _previousActiveCutId;
    if (!_hasExecuted || previousActiveCutId == null) {
      throw StateError('Command has not been executed.');
    }

    repository.removeCut(cutId: newCutId);
    editingSession.setActiveCutId(previousActiveCutId);
  }
}

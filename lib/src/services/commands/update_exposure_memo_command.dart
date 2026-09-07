import '../../models/cut_id.dart';
import '../../models/exposure_memo.dart';
import '../../models/layer_id.dart';
import '../command.dart';
import '../project_lookup.dart' show requireLayer, requireMemoBlockAt;
import '../project_repository.dart';

/// Writes one exposure BLOCK's memo, undoably.
///
/// Addressed by (cut, layer, block start) rather than by frame id: the memo
/// belongs to the exposure, not the drawing, so the same cel exposed twice
/// carries two memos and a linked cut's local timeline keeps its own.
class UpdateExposureMemoCommand implements Command {
  UpdateExposureMemoCommand({
    required this.repository,
    required this.cutId,
    required this.layerId,
    required this.blockStartIndex,
    required this.memo,
  });

  final ProjectRepository repository;
  final CutId cutId;
  final LayerId layerId;
  final int blockStartIndex;
  final ExposureMemo? memo;

  ExposureMemo? _previousMemo;
  bool _hasExecuted = false;

  @override
  String get description => 'Update memo at frame ${blockStartIndex + 1}';

  @override
  void execute() {
    if (!_hasExecuted) {
      // THE ONE WALK, and the one block rule: `project_lookup` owns both,
      // and the repository's write asks it again a line later. This used
      // to be a private re-implementation carrying the same two refusal
      // strings word for word — and missing the ghost ruling, which only
      // meant the refusal arrived from the write instead of from here.
      _previousMemo = requireMemoBlockAt(
        requireLayer(
          repository.requireProject(),
          cutId: cutId,
          layerId: layerId,
        ),
        blockStartIndex,
      ).memo;
    }

    repository.updateExposureMemo(
      cutId: cutId,
      layerId: layerId,
      blockStartIndex: blockStartIndex,
      memo: memo,
    );
    _hasExecuted = true;
  }

  @override
  void undo() {
    if (!_hasExecuted) {
      throw StateError('Command has not been executed.');
    }

    repository.updateExposureMemo(
      cutId: cutId,
      layerId: layerId,
      blockStartIndex: blockStartIndex,
      memo: _previousMemo,
    );
  }
}

import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/exposure_memo.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/timeline_exposure.dart';
import '../command.dart';
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
      _previousMemo = _requireBlock().memo;
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

  TimelineExposure _requireBlock() {
    final project = repository.requireProject();
    Cut? targetCut;
    for (final track in project.tracks) {
      for (final cut in track.cuts) {
        if (cut.id == cutId) {
          targetCut = cut;
          break;
        }
      }
      if (targetCut != null) {
        break;
      }
    }
    if (targetCut == null) {
      throw StateError('Cut not found: $cutId');
    }

    Layer? targetLayer;
    for (final layer in targetCut.layers) {
      if (layer.id == layerId) {
        targetLayer = layer;
        break;
      }
    }
    if (targetLayer == null) {
      throw StateError('Layer not found in cut $cutId: $layerId');
    }

    final entry = targetLayer.timeline[blockStartIndex];
    if (entry == null || !entry.isDrawing) {
      throw StateError(
        'No exposure block starts at $blockStartIndex on $layerId.',
      );
    }
    return entry;
  }
}

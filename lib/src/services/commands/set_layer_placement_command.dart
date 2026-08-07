import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../../models/track_id.dart';
import '../command.dart';
import '../project_lookup.dart';
import '../project_repository.dart';

/// Resequences a cut's layers and re-parents the rows a drag moved — THE
/// row-placement edit.
///
/// It carries the whole ORDER rather than an index pair for the reason
/// [SetCutOrderCommand] does: one gesture is not always one row. A folder
/// travels with its subtree and an attach base with its group, so the move
/// that produced this is a run, and unwinding it as a series of single-row
/// moves would be several undo steps for one drag.
///
/// [folderIds] rides along instead of being its own command because the
/// drop that changes membership is the same drop that changes order — see
/// [ProjectRepository.setLayerPlacement].
class SetLayerPlacementCommand implements Command {
  SetLayerPlacementCommand({
    required this.repository,
    required this.cutId,
    required this.order,
    this.folderIds = const {},
    this.description = 'Move layers',
  });

  final ProjectRepository repository;
  final CutId cutId;
  final List<LayerId> order;

  /// The rows whose folder membership this move changes, to the folder they
  /// land in (null = out of every folder). Rows absent from the map keep
  /// what they had.
  final Map<LayerId, LayerId?> folderIds;

  @override
  final String description;

  List<LayerId>? _originalOrder;
  Map<LayerId, LayerId?>? _originalFolderIds;
  bool _hasExecuted = false;

  @override
  void execute() {
    if (_originalOrder == null) {
      final cut = requireCut(repository.requireProject(), cutId);
      _originalOrder = [for (final layer in cut.layers) layer.id];
      // Only the rows this command re-parents: restoring membership it
      // never touched would fight a concurrent edit on the redo path.
      _originalFolderIds = {
        for (final layer in cut.layers)
          if (folderIds.containsKey(layer.id)) layer.id: layer.folderId,
      };
    }
    repository.setLayerPlacement(
      cutId: cutId,
      order: order,
      folderIds: folderIds,
    );
    _hasExecuted = true;
  }

  @override
  void undo() {
    final originalOrder = _originalOrder;
    final originalFolderIds = _originalFolderIds;
    if (!_hasExecuted || originalOrder == null || originalFolderIds == null) {
      throw StateError('Command has not been executed.');
    }
    repository.setLayerPlacement(
      cutId: cutId,
      order: originalOrder,
      folderIds: originalFolderIds,
    );
  }
}

/// Resequences a track's SE rows — the S-rows' counterpart, and a separate
/// command because they live on the TRACK, not in any cut. A drag can never
/// interleave the two (the display list appends the track's rows after the
/// cut's), so no single command has to speak both.
class SetTrackSeOrderCommand implements Command {
  SetTrackSeOrderCommand({
    required this.repository,
    required this.trackId,
    required this.order,
  });

  final ProjectRepository repository;
  final TrackId trackId;
  final List<LayerId> order;

  List<LayerId>? _originalOrder;
  bool _hasExecuted = false;

  @override
  String get description => 'Reorder SE rows';

  @override
  void execute() {
    _originalOrder ??= _currentOrder();
    repository.setTrackSeOrder(trackId: trackId, order: order);
    _hasExecuted = true;
  }

  @override
  void undo() {
    final originalOrder = _originalOrder;
    if (!_hasExecuted || originalOrder == null) {
      throw StateError('Command has not been executed.');
    }
    repository.setTrackSeOrder(trackId: trackId, order: originalOrder);
  }

  List<LayerId> _currentOrder() {
    for (final track in repository.requireProject().tracks) {
      if (track.id == trackId) {
        return [for (final layer in track.seLayers) layer.id];
      }
    }
    throw StateError('Track not found: $trackId');
  }
}

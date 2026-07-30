import '../../models/layer_id.dart';
import '../../models/se_name_tag.dart';
import '../command.dart';
import '../project_lookup.dart';
import '../project_repository.dart';

/// Sets an SE row's on-canvas name tag (R5b) in one undo step. Null
/// resets the row to the stacked default.
class UpdateSeNameTagCommand implements Command {
  UpdateSeNameTagCommand({
    required this.repository,
    required this.layerId,
    required this.seNameTag,
    this.description = 'Edit SE name tag',
  });

  final ProjectRepository repository;
  final LayerId layerId;
  final SeNameTag? seNameTag;

  @override
  final String description;

  SeNameTag? _previous;
  bool _hasExecuted = false;

  @override
  void execute() {
    // Anywhere lookup: SE rows are TRACK fixtures, not cut layers — the
    // cut-scoped read throws for them.
    final layer = requireLayerAnywhere(repository.requireProject(), layerId);
    if (!_hasExecuted) {
      _previous = layer.seNameTag;
    }
    repository.updateLayerSeNameTag(layerId: layerId, seNameTag: seNameTag);
    _hasExecuted = true;
  }

  @override
  void undo() {
    if (!_hasExecuted) {
      throw StateError('Command has not been executed.');
    }
    requireLayerAnywhere(repository.requireProject(), layerId);
    repository.updateLayerSeNameTag(layerId: layerId, seNameTag: _previous);
  }
}

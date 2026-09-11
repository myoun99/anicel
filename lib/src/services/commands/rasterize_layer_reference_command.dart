import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../../models/media_reference.dart';
import '../command.dart';
import '../project_lookup.dart';
import '../project_repository.dart';

/// RASTERIZE (§6-f/§6-z23): the reference layer's pixels are ALREADY its
/// cels, so the verb nulls [Layer.mediaReference] — nothing else. One undo
/// restores it.
///
/// ↩️It also unregistered the asset when this was the last layer pointing at
/// it — 「§3: baked = unregistered」, from the 07-30 import design
/// (`98f529fc`). The user reversed that on 2026-09-11 (미디어 배치 라운드 6:
/// 「구워도 풀에 남음」): the material of every placement is a pool entry,
/// and a baked layer's file is still the pool's to offer again. The
/// placement window's bake keeps it for the same reason, so the two doors to
/// this one verb say the same thing.
class RasterizeLayerReferenceCommand implements Command {
  RasterizeLayerReferenceCommand({
    required this.repository,
    required this.cutId,
    required this.layerId,
  });

  final ProjectRepository repository;
  final CutId cutId;
  final LayerId layerId;

  MediaReference? _referenceBefore;
  bool _hasExecuted = false;

  @override
  String get description => 'Rasterize layer';

  @override
  void execute() {
    final project = repository.requireProject();
    final layer = requireLayer(project, cutId: cutId, layerId: layerId);
    final reference = layer.mediaReference;
    if (reference == null) {
      _hasExecuted = true;
      return;
    }
    _referenceBefore ??= reference;
    repository.updateLayer(
      layerId: layerId,
      update: (layer) => layer.copyWith(mediaReference: null),
    );
    _hasExecuted = true;
  }

  @override
  void undo() {
    if (!_hasExecuted) {
      throw StateError('Command has not been executed.');
    }
    final reference = _referenceBefore;
    if (reference == null) {
      return; // Executed as a no-op.
    }
    repository.updateLayer(
      layerId: layerId,
      update: (layer) => layer.copyWith(mediaReference: reference),
    );
  }
}

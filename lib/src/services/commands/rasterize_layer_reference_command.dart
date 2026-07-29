import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../../models/media_asset.dart';
import '../../models/media_reference.dart';
import '../command.dart';
import '../project_lookup.dart';
import '../project_repository.dart';

/// RASTERIZE (§6-f/§6-z23): the reference layer's pixels are ALREADY its
/// cels, so the verb nulls [Layer.mediaReference] — nothing else — and
/// drops the asset registration when nothing else references it (§3:
/// baked = unregistered). One undo restores both.
class RasterizeLayerReferenceCommand implements Command {
  RasterizeLayerReferenceCommand({
    required this.repository,
    required this.cutId,
    required this.layerId,
    required this.assetStillReferenced,
  });

  final ProjectRepository repository;
  final CutId cutId;
  final LayerId layerId;

  /// Whether [MediaReference.assetPath] stays referenced by OTHERS after
  /// this layer lets go (the caller answers with the session's reference
  /// count MINUS this layer).
  final bool assetStillReferenced;

  MediaReference? _referenceBefore;
  List<MediaAsset>? _poolBefore;
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
    _poolBefore ??= project.mediaAssets;

    repository.updateLayer(
      layerId: layerId,
      update: (layer) => layer.copyWith(mediaReference: null),
    );
    if (!assetStillReferenced) {
      repository.updateMediaAssets([
        for (final asset in project.mediaAssets)
          if (asset.path != reference.assetPath) asset,
      ]);
    }
    _hasExecuted = true;
  }

  @override
  void undo() {
    if (!_hasExecuted) {
      throw StateError('Command has not been executed.');
    }
    final reference = _referenceBefore;
    final poolBefore = _poolBefore;
    if (reference == null || poolBefore == null) {
      return; // Executed as a no-op.
    }
    repository.updateLayer(
      layerId: layerId,
      update: (layer) => layer.copyWith(mediaReference: reference),
    );
    repository.updateMediaAssets(poolBefore);
  }
}

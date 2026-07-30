import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/layer_folder.dart';
import '../../models/layer_id.dart';
import '../../models/layer_link_registry.dart';
import '../command.dart';
import '../project_lookup.dart';
import '../project_repository.dart';

/// 폴더 해산: removes the folder ROW, releasing its direct members (layers
/// and nested folders alike) to its parent. The members themselves stay
/// where they are in the stack. Mirrors over 겸용 cuts through the folder
/// row's own link group — the same registry every other layer uses — and
/// one undo restores the rows, their memberships and the group.
///
/// The folder's own COMPOSITING state goes with it — its blend, its
/// opacity and (R6) its effect chain all belonged to a buffer that no
/// longer exists, and there is nowhere correct to put them: distributing a
/// group filter over the released members would change the picture wherever
/// they overlap. Undo restores the row whole, so nothing is lost for good.
class DissolveFolderCommand implements Command {
  DissolveFolderCommand({
    required this.repository,
    required this.cutId,
    required this.folderId,
  });

  final ProjectRepository repository;
  final CutId cutId;
  final LayerId folderId;

  List<
    ({
      CutId cutId,
      Layer folder,
      int index,
      List<LayerId> releasedLayerIds,
    })
  >?
  _dissolved;
  LayerLinkRegistry? _registryBefore;

  @override
  String get description => 'Dissolve folder $folderId';

  @override
  void execute() {
    final project = repository.requireProject();
    _registryBefore ??= project.linkRegistry;
    // Every counterpart folder row, resolved BEFORE anything moves.
    final targets = <({CutId cutId, LayerId folderId})>[
      (cutId: cutId, folderId: folderId),
      for (final member
          in project.linkRegistry
                  .groupOf(cutId: cutId, layerId: folderId)
                  ?.members ??
              const <LayerLinkMember>[])
        if (member.cutId != cutId)
          (cutId: member.cutId, folderId: member.layerId),
    ];

    final dissolved =
        <({
          CutId cutId,
          Layer folder,
          int index,
          List<LayerId> releasedLayerIds,
        })>[];
    for (final target in targets) {
      final cut = requireCut(project, target.cutId);
      final folder = cut.layers.folderById(target.folderId);
      if (folder == null) {
        continue;
      }
      final index = cut.layers.indexWhere((layer) => layer.id == folder.id);
      final releasedLayerIds = <LayerId>[];
      for (final layer in cut.layers) {
        if (layer.folderId == folder.id) {
          releasedLayerIds.add(layer.id);
          repository.updateLayerFolderId(
            cutId: target.cutId,
            layerId: layer.id,
            folderId: folder.folderId,
          );
        }
      }
      repository.deleteLayer(cutId: target.cutId, layerId: folder.id);
      dissolved.add((
        cutId: target.cutId,
        folder: folder,
        index: index,
        releasedLayerIds: releasedLayerIds,
      ));
    }
    _dissolved ??= dissolved;
  }

  @override
  void undo() {
    final dissolved = _dissolved;
    final registryBefore = _registryBefore;
    if (dissolved == null || registryBefore == null) {
      throw StateError('Command has not been executed.');
    }
    for (final entry in dissolved) {
      repository.insertLayer(
        cutId: entry.cutId,
        layer: entry.folder,
        index: entry.index,
      );
      for (final layerId in entry.releasedLayerIds) {
        repository.updateLayerFolderId(
          cutId: entry.cutId,
          layerId: layerId,
          folderId: entry.folder.id,
        );
      }
    }
    repository.updateProject(
      (current) => current.copyWith(linkRegistry: registryBefore),
    );
  }
}

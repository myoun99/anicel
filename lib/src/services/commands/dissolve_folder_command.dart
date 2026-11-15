import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/layer_folder.dart';
import '../../models/layer_id.dart';
import '../../models/layer_link_registry.dart';
import 'link_registry_snapshot_command.dart';
import '../project_lookup.dart';

/// 폴더 해산: removes the folder ROW, releasing its direct members (layers
/// and nested folders alike) to its parent. The members themselves stay
/// where they are in the stack — but a direction or camera row let out of
/// a drawing folder stands in its own section, over the pictures (F-596).
/// Mirrors over 겸용 cuts through the folder row's own link group — the
/// same registry every other layer uses — and one undo restores the rows,
/// their memberships and the group.
///
/// The folder's own COMPOSITING state goes with it — its blend, its
/// opacity and (R6) its effect chain all belonged to a buffer that no
/// longer exists, and there is nowhere correct to put them: distributing a
/// group filter over the released members would change the picture wherever
/// they overlap. Undo restores the row whole, so nothing is lost for good.
class DissolveFolderCommand extends LinkRegistrySnapshotCommand {
  DissolveFolderCommand({
    required super.repository,
    required this.cutId,
    required this.folderId,
  });

  final CutId cutId;
  final LayerId folderId;

  /// Each cut's rows as they stood before the folder went: the order and
  /// the memberships one undo writes back.
  ///
  /// ⛔ONE WRITE, NOT A ROW AND ITS MEMBERS ONE BY ONE. A cut stands a row
  /// where its outermost folder stands (`sectionedLayerOrder`, F-596), so a
  /// direction row the folder let go stands over the pictures — and put
  /// back a write at a time, the folder row first or its rows first, the
  /// cut stood that row out of the folder's run in between, for good.
  List<({CutId cutId, List<Layer> layersBefore})>? _dissolved;

  @override
  String get description => 'Dissolve folder $folderId';

  @override
  void execute() {
    final project = repository.requireProject();
    snapshotRegistry(project);
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

    final dissolved = <({CutId cutId, List<Layer> layersBefore})>[];
    for (final target in targets) {
      final cut = requireCut(project, target.cutId);
      final folder = cut.layers.folderById(target.folderId);
      if (folder == null) {
        continue;
      }
      for (final layer in cut.layers) {
        if (layer.folderId == folder.id) {
          repository.updateLayerFolderId(
            cutId: target.cutId,
            layerId: layer.id,
            folderId: folder.folderId,
          );
        }
      }
      repository.deleteLayer(cutId: target.cutId, layerId: folder.id);
      dissolved.add((cutId: target.cutId, layersBefore: cut.layers));
    }
    _dissolved ??= dissolved;
    markExecuted();
  }

  @override
  void undoBeforeRegistry() {
    for (final entry in _dissolved!) {
      final now = requireCut(repository.requireProject(), entry.cutId).layers;
      repository.setCutLayers(
        cutId: entry.cutId,
        layers: [
          for (final before in entry.layersBefore)
            switch (now.byId(before.id)) {
              // The folder row, gone with it: back as it was.
              null => before,
              // Every other row as it is, where it stood and in the folder
              // it stood in.
              final row => row.copyWith(folderId: before.folderId),
            },
        ],
      );
    }
  }
}

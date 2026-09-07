import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_link_registry.dart';
import 'link_registry_snapshot_command.dart';
import '../project_lookup.dart';
import 'link_mirror.dart';

/// Deletes a layer — and, when it is LINKED, every member of its group
/// in the same command ("완전 링크": the layer is ONE thing seen from
/// several cuts, so deleting it deletes it everywhere; the UI shows the
/// friendly warning before calling). The emptied link groups dissolve.
/// One undo reinserts every member at its exact index and restores the
/// registry.
class DeleteLayerCommand extends LinkRegistrySnapshotCommand {
  DeleteLayerCommand({
    required super.repository,
    required this.cutId,
    required this.layerId,
  });

  final CutId cutId;
  final LayerId layerId;

  List<({CutId cutId, LayerId layerId, Layer layer, int index})>? _targets;

  @override
  String get description => 'Delete layer $layerId';

  @override
  void execute() {
    final project = repository.requireProject();
    _targets ??= [
      for (final target in linkMirrorTargets(
        project,
        cutId: cutId,
        layerId: layerId,
      ))
        () {
          final cut = requireCut(project, target.cutId);
          final index = cut.layers.indexWhere(
            (layer) => layer.id == target.layerId,
          );
          if (index == -1) {
            throw StateError(
              'Layer not found in cut ${target.cutId}: ${target.layerId}',
            );
          }
          return (
            cutId: target.cutId,
            layerId: target.layerId,
            layer: cut.layers[index],
            index: index,
          );
        }(),
    ];
    // R28 #14: a cut may end up with NO layers. The floor used to live
    // here as well as in the coordinator's section rules; both are gone —
    // an empty cut is a representable state (the canvas shows its blank
    // paper, and drawing refuses with the R26 #35 notice).
    snapshotRegistry(project);
    for (final target in _targets!) {
      repository.deleteLayer(cutId: target.cutId, layerId: target.layerId);
    }
    // Every member of the affected group was just deleted — the group
    // dissolves whole (a layer belongs to at most one group).
    final deletedIds = {for (final target in _targets!) target.layerId};
    repository.updateProject(
      (current) => current.copyWith(
        linkRegistry: LayerLinkRegistry(
          groups: [
            for (final group in current.linkRegistry.groups)
              if (!group.members.any(
                (member) => deletedIds.contains(member.layerId),
              ))
                group,
          ],
        ),
      ),
    );
    markExecuted();
  }

  @override
  void undoBeforeRegistry() {
    for (final target in _targets!) {
      repository.insertLayer(
        cutId: target.cutId,
        layer: target.layer,
        index: target.index,
      );
    }
  }
}

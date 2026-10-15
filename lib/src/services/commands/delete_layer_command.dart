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
///
/// A row of a track's conte, deleted ITSELF ([withItsConteRow]), goes from
/// every cut of the track the same way — it is one row of the track's
/// conte structure (I-73, F-343, [existenceMirrorTargets]).
class DeleteLayerCommand extends LinkRegistrySnapshotCommand {
  DeleteLayerCommand({
    required super.repository,
    required this.cutId,
    required this.layerId,
    this.withItsConteRow = false,
  });

  final CutId cutId;
  final LayerId layerId;

  /// Whether the delete takes this row's row of its track's conte structure
  /// from every cut with it ([existenceMirrorTargets]) — the row deleted
  /// for itself. False for a row that goes because something it stands in
  /// goes: a cut's conte taking its attach rows along is that CUT's
  /// delete, and reaches no other cut's rows but through a link.
  final bool withItsConteRow;

  List<({CutId cutId, LayerId layerId, Layer layer, int index})>? _targets;

  @override
  String get description => 'Delete layer $layerId';

  @override
  void execute() {
    final project = repository.requireProject();
    _targets ??= [
      for (final target
          in withItsConteRow
              ? existenceMirrorTargets(project, cutId: cutId, layerId: layerId)
              : linkMirrorTargets(project, cutId: cutId, layerId: layerId))
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
    // One write of the track's conte (F-343): a row of its structure goes
    // from every cut here, cut by cut, and laid between two of them the
    // structure would give it back to the cuts it had gone from.
    repository.asOneConteWrite(() {
      for (final target in _targets!) {
        repository.deleteLayer(cutId: target.cutId, layerId: target.layerId);
      }
    });
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
    // …and comes back to every cut the same way, as one write: laid
    // between two of them, the structure would have given a cut the row
    // that is about to come back to it.
    repository.asOneConteWrite(() {
      for (final target in _targets!) {
        repository.insertLayer(
          cutId: target.cutId,
          layer: target.layer,
          index: target.index,
        );
      }
    });
  }
}

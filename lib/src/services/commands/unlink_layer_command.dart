import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../../models/layer_link_registry.dart';
import '../brush_frame_store.dart';
import 'link_group_parts.dart';
import 'link_registry_snapshot_command.dart';
import '../project_lookup.dart';

/// 독립시키기 (L2, layer scale): removes a layer's WHOLE attach group
/// from its link groups and FORKS the pixels — each member gets its own
/// physical copy of the shared cels, so edits stop propagating both
/// ways. The escape hatch of the "완전 링크" model: local exceptions are
/// made by unlinking, never by weakening the link.
///
/// Symmetric with 링크 복제: the unit is the attach group (one member
/// leaving alone would break the mirrored structure).
class UnlinkLayerCommand extends LinkRegistrySnapshotCommand {
  UnlinkLayerCommand({
    required super.repository,
    required BrushFrameStore brushFrameStore,
    required this.cutId,
    required this.sourceLayerId,
  }) : _copies = LinkPartCopies(brushFrameStore);

  final CutId cutId;

  /// Any member of the group to unlink (resolves to its base).
  final LayerId sourceLayerId;

  /// The cels forked at execute — undo empties exactly these.
  final LinkPartCopies _copies;

  @override
  String get description => 'Unlink layer $sourceLayerId';

  @override
  void execute() {
    final project = repository.requireProject();
    final registry = project.linkRegistry;
    // A 동기컷's rows leave TOGETHER and stay one group: the sync is one
    // cut, and its row is unlinked wherever the cut stands (I-150-Q3).
    final leaving = {
      for (final member in requireAttachedGroup(
        project,
        cutId: cutId,
        layerId: sourceLayerId,
      ).members)
        ...registry.rowAcrossItsSync(cutId: cutId, layerId: member.id),
    };
    bool leaves(LayerLinkMember member) =>
        leaving.contains((member.cutId, member.layerId));

    // Each group parted in two — the rows staying and the rows leaving —
    // each part keeping its pictures ([partLinkGroup]).
    final groups = <LayerLinkGroup>[];
    final copiers = <LayerLinkMember>[];
    for (final group in registry.groups) {
      final parted = partLinkGroup(
        group,
        [
          [
            for (final member in group.members)
              if (!leaves(member)) member,
          ],
          [
            for (final member in group.members)
              if (leaves(member)) member,
          ],
        ],
        idOf: (_) => '${group.id}:sync',
      );
      groups.addAll(parted.groups);
      copiers.addAll(parted.copiers);
    }

    final taken = _copies.take(project, copiers);
    snapshotRegistry(project);
    repository.updateProject(
      (current) => current.copyWith(
        linkRegistry: current.linkRegistry.copyWith(groups: groups),
      ),
    );
    _copies.keep(taken);
    markExecuted();
  }

  /// Remove the forked cels FIRST (keys still self-resolving), then
  /// restore the registry — reads flow back to the canonical cels. The
  /// template fixes that order (see [LinkRegistrySnapshotCommand.undo]).
  @override
  void undoBeforeRegistry() => _copies.takeBack();
}

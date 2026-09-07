import '../../models/attached_layer_resolve.dart';
import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../../models/layer_link_registry.dart';
import '../brush_frame_store.dart';
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
    required this.brushFrameStore,
    required this.cutId,
    required this.sourceLayerId,
  });

  final BrushFrameStore brushFrameStore;
  final CutId cutId;

  /// Any member of the group to unlink (resolves to its base).
  final LayerId sourceLayerId;

  /// The cels forked at execute — undo removes exactly these.
  final List<(BrushFrameKey, BitmapSurface)> _forkedCels = [];

  @override
  String get description => 'Unlink layer $sourceLayerId';

  @override
  void execute() {
    final project = repository.requireProject();
    final position = requireCutPosition(project, cutId);
    final track = position.track;
    final cut = position.cut;
    final source = requireLayer(project, cutId: cutId, layerId: sourceLayerId);
    final baseId = attachBaseIdOf(source);
    final members = attachedGroupSlice(baseId, cut.layers);
    if (members.isEmpty) {
      throw StateError('Attach base not found: $baseId');
    }

    // 1. Capture the shared pixels THROUGH the still-linked member keys
    //    (they resolve to the canonical cels).
    _forkedCels.clear();
    for (final member in members) {
      if (project.linkRegistry.groupOf(cutId: cutId, layerId: member.id) ==
          null) {
        continue;
      }
      for (final frame in member.frames) {
        final memberKey = BrushFrameKey(
          projectId: project.id,
          trackId: track.id,
          cutId: cutId,
          layerId: member.id,
          frameId: frame.id,
        );
        final surface = brushFrameStore.bakedSurfaceOrNull(memberKey);
        if (surface != null) {
          _forkedCels.add((memberKey, surface));
        }
      }
    }

    // 2. Leave the link groups (singleton leftovers dissolve).
    snapshotRegistry(project);
    repository.updateProject((current) {
      final memberIds = {for (final member in members) member.id};
      final groups = <LayerLinkGroup>[];
      for (final group in current.linkRegistry.groups) {
        final remaining = [
          for (final groupMember in group.members)
            if (!(groupMember.cutId == cutId &&
                memberIds.contains(groupMember.layerId)))
              groupMember,
        ];
        if (remaining.length >= 2) {
          groups.add(group.copyWith(members: remaining));
        }
      }
      return current.copyWith(
        linkRegistry: LayerLinkRegistry(groups: groups),
      );
    });

    // 3. The member keys now resolve to THEMSELVES — store the captured
    //    pixels as the layer's own cels (surfaces are immutable, sharing
    //    the object is a true copy-on-write fork).
    for (final (key, surface) in _forkedCels) {
      brushFrameStore.storeBakedSurface(key, surface);
    }
    markExecuted();
  }

  /// Remove the forked cels FIRST (keys still self-resolving), then
  /// restore the registry — reads flow back to the canonical cels. The
  /// template fixes that order (see [LinkRegistrySnapshotCommand.undo]).
  @override
  void undoBeforeRegistry() {
    for (final (key, surface) in _forkedCels) {
      brushFrameStore.storeBakedSurface(
        key,
        BitmapSurface(canvasSize: surface.canvasSize),
      );
    }
  }
}

import '../../models/attached_layer_resolve.dart';
import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_link_registry.dart';
import '../../models/project.dart';
import '../command.dart';
import '../project_lookup.dart';
import '../project_repository.dart';

/// 링크 복제 (L2): duplicates a layer's WHOLE attach group as a FREE
/// group whose members share the originals' cel banks — the pictures
/// exist once; the copies are windows onto them.
///
/// Per the confirmed design:
/// - The unit is the attach group (a lone base is a group of one); the
///   member selected can be any row of it.
/// - Copies keep the SAME FrameIds (the link mechanism: the store's
///   canonical resolution rewrites only the cut/layer address) and the
///   SAME names ("linked ⇒ same name" stays true by construction).
/// - Timelines and FX lanes COPY (lanes are per-use — the stamp starts
///   where the original is and diverges freely).
/// - The copied group is FREE: internal attach linkage remaps onto the
///   copied base; nothing attaches to the ORIGINAL group.
/// - The registry gains one link pair per member (extending the member's
///   existing group when it is already linked).
class LinkDuplicateLayerCommand implements Command {
  LinkDuplicateLayerCommand({
    required this.repository,
    required this.cutId,
    required this.sourceLayerId,
    required this.layerIdMap,
    required this.newGroupIdBySource,
  });

  final ProjectRepository repository;
  final CutId cutId;

  /// Any member of the group to duplicate (resolves to its base).
  final LayerId sourceLayerId;

  /// Planned ids: source member id → its copy's id (planner-assigned so
  /// redo reproduces the exact state).
  final Map<LayerId, LayerId> layerIdMap;

  /// Planned registry group ids per source member — used only for
  /// members not already in a link group.
  final Map<LayerId, String> newGroupIdBySource;

  LayerLinkRegistry? _registryBefore;
  bool _hasExecuted = false;

  @override
  String get description => 'Link-duplicate layer $sourceLayerId';

  @override
  void execute() {
    repository.updateProject((project) {
      final track = requireTrackOfCut(project, cutId);
      final cut = requireCut(project, cutId);
      final source = requireLayer(
        project,
        cutId: cutId,
        layerId: sourceLayerId,
      );
      // Resolve to the group's base, then take the contiguous run —
      // below-side rows and organizer folder rows included.
      final baseId = source.attachedToLayerId ?? source.id;
      if (!cut.layers.any((layer) => layer.id == baseId)) {
        throw StateError('Attach base not found: $baseId');
      }
      final startIndex = attachedGroupStartIndex(baseId, cut.layers);
      final endIndex = attachedGroupEndIndex(baseId, cut.layers);
      final members = cut.layers.sublist(startIndex, endIndex);

      final copies = <Layer>[
        for (final member in members)
          () {
            final copy = member.copyWith(
              id: _requireCopyId(member.id),
              // The copied group is FREE, but its INTERNAL attach glue
              // stays: members re-attach to the copied base.
              attachedToLayerId: member.attachedToLayerId == null
                  ? null
                  : _requireCopyId(member.attachedToLayerId!),
              // Frames / timeline / FX all carry over via copyWith
              // defaults — same FrameIds IS the link.
            );
            // An ORGANIZER folder copied with the group re-parents its
            // member copies onto the copied folder row; folder pointers
            // OUT of the slice (the group's shared outer folder) carry
            // over unchanged.
            final remappedFolderId = member.folderId == null
                ? null
                : layerIdMap[member.folderId!];
            return remappedFolderId == null
                ? copy
                : copy.copyWith(folderId: remappedFolderId);
          }(),
      ];

      final nextLayers = [...cut.layers]..insertAll(endIndex, copies);

      _registryBefore = project.linkRegistry;
      var groups = [...project.linkRegistry.groups];
      for (final member in members) {
        // FOLDER rows (organizers riding in the slice) never join link
        // groups: linking shares cel banks, and a folder has none —
        // joining the ORIGINAL organizer's group would make deleting the
        // copy dissolve the original's mirror in another cut.
        if (layerKindGroupsLayers(member.kind)) {
          continue;
        }
        final copyMember = LayerLinkMember(
          trackId: track.id,
          cutId: cutId,
          layerId: _requireCopyId(member.id),
        );
        final existingIndex = groups.indexWhere(
          (group) => group.contains(cutId: cutId, layerId: member.id),
        );
        if (existingIndex != -1) {
          final existing = groups[existingIndex];
          groups[existingIndex] = existing.copyWith(
            members: [...existing.members, copyMember],
          );
        } else {
          groups.add(
            LayerLinkGroup(
              id: newGroupIdBySource[member.id] ??
                  (throw StateError(
                    'No planned group id for ${member.id}',
                  )),
              members: [
                LayerLinkMember(
                  trackId: track.id,
                  cutId: cutId,
                  layerId: member.id,
                ),
                copyMember,
              ],
            ),
          );
        }
      }

      return _projectWithCutLayers(
        project,
        cutId: cutId,
        layers: nextLayers,
      ).copyWith(linkRegistry: LayerLinkRegistry(groups: groups));
    });
    _hasExecuted = true;
  }

  @override
  void undo() {
    final registryBefore = _registryBefore;
    if (!_hasExecuted || registryBefore == null) {
      throw StateError('Command has not been executed.');
    }
    repository.updateProject((project) {
      final cut = requireCut(project, cutId);
      final copyIds = layerIdMap.values.toSet();
      return _projectWithCutLayers(
        project,
        cutId: cutId,
        layers: [
          for (final layer in cut.layers)
            if (!copyIds.contains(layer.id)) layer,
        ],
      ).copyWith(linkRegistry: registryBefore);
    });
  }

  LayerId _requireCopyId(LayerId sourceId) {
    final copyId = layerIdMap[sourceId];
    if (copyId == null) {
      throw StateError('No planned copy id for $sourceId');
    }
    return copyId;
  }
}

/// [project] with [cutId]'s layer list replaced.
Project _projectWithCutLayers(
  Project project, {
  required CutId cutId,
  required List<Layer> layers,
}) {
  return project.copyWith(
    tracks: [
      for (final track in project.tracks)
        track.copyWith(
          cuts: [
            for (final cut in track.cuts)
              cut.id == cutId ? cut.copyWith(layers: layers) : cut,
          ],
        ),
    ],
  );
}

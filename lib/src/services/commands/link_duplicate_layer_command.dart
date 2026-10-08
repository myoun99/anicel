import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_link_join.dart';
import '../../models/layer_link_registry.dart';
import '../../models/new_row_placement.dart';
import '../command.dart';
import '../project_lookup.dart';
import '../project_tree_editor.dart';
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
/// - The copies land where a NEW row would, asked for [insertionIndex]
///   ([newRowPlacement] — never inside another attach group, and in the
///   folder of the row below). ↩️They landed directly above their source
///   group while the layer menu's 「링크해서 복제」 was the only door; it
///   is a PASTE's now (I-77), and a paste lands where it is pressed.
class LinkDuplicateLayerCommand implements Command {
  LinkDuplicateLayerCommand({
    required this.repository,
    required this.cutId,
    required this.sourceLayerId,
    required this.insertionIndex,
    required this.layerIdMap,
    required this.newGroupIdBySource,
  });

  final ProjectRepository repository;
  final CutId cutId;

  /// Any member of the group to duplicate (resolves to its base).
  final LayerId sourceLayerId;

  /// The seat in the cut's stack the copies are aimed at.
  final int insertionIndex;

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
      final group = requireAttachedGroup(
        project,
        cutId: cutId,
        layerId: sourceLayerId,
      );
      final track = group.track;
      final cut = group.cut;
      final members = group.members;
      final placement = newRowPlacement(cut.layers, insertionIndex);

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
            // member copies onto the copied folder row. A folder pointer
            // OUT of the slice — the folder the group stood in — is the
            // landing's: the copies join the folder they are put down in.
            final copiedFolderId = member.folderId == null
                ? null
                : layerIdMap[member.folderId!];
            return copy.copyWith(
              folderId: copiedFolderId ?? placement.folderId,
            );
          }(),
      ];

      final nextLayers = [...cut.layers]..insertAll(placement.index, copies);

      _registryBefore = project.linkRegistry;
      var groups = [...project.linkRegistry.groups];
      for (final member in members) {
        // FOLDER rows (organizers riding in the slice) never join link
        // groups: linking shares cel banks, and a folder has none —
        // joining the ORIGINAL organizer's group would make deleting the
        // copy dissolve the original's mirror in another cut.
        if (member.kind.groupsLayers) {
          continue;
        }
        groups = linkGroupsJoined(
          groups,
          origin: LayerLinkMember(
            trackId: track.id,
            cutId: cutId,
            layerId: member.id,
          ),
          joiner: LayerLinkMember(
            trackId: track.id,
            cutId: cutId,
            layerId: _requireCopyId(member.id),
          ),
          plannedGroupId: newGroupIdBySource[member.id],
        );
      }

      final next =
          updateCutAnywhere(
            project,
            cutId,
            (cut) => cut.copyWith(layers: nextLayers),
          ) ??
          (throw StateError('Cut not found: $cutId'));
      return next.copyWith(linkRegistry: LayerLinkRegistry(groups: groups));
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
      final copyIds = layerIdMap.values.toSet();
      final next =
          updateCutAnywhere(
            project,
            cutId,
            (cut) => cut.copyWith(
              layers: [
                for (final layer in cut.layers)
                  if (!copyIds.contains(layer.id)) layer,
              ],
            ),
          ) ??
          (throw StateError('Cut not found: $cutId'));
      return next.copyWith(linkRegistry: registryBefore);
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

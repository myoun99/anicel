import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/layer_effect.dart' show effectsWithRowsRenamed;
import '../../models/layer_id.dart';
import '../../models/layer_link_join.dart';
import '../../models/layer_link_registry.dart';
import '../../models/new_row_placement.dart';
import '../../models/project.dart';
import '../command.dart';
import '../project_lookup.dart';
import '../project_tree_editor.dart';
import '../project_repository.dart';
import 'link_mirror.dart' show linkCounterpartIn, mirroredInsertionIndex;

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
/// - In a 겸용 cut each sibling copies ITS row of the source the same way,
///   aimed where its own stands ([siblings]): a pasted row is an added
///   row, and an added row's existence is the cuts' to share (F-398).
class LinkDuplicateLayerCommand implements Command {
  LinkDuplicateLayerCommand({
    required this.repository,
    required this.cutId,
    required this.sourceLayerId,
    required this.insertionIndex,
    required this.layerIdMap,
    required this.newGroupIdBySource,
    this.siblings = const [],
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
  /// members not already in a link group. A FOLDER member's names the
  /// group its copies in the cuts are tied by.
  final Map<LayerId, String> newGroupIdBySource;

  /// The 겸용 siblings' shares, planned like [cutId]'s own.
  final List<LinkDuplicateUse> siblings;

  LayerLinkRegistry? _registryBefore;
  bool _hasExecuted = false;

  List<LinkDuplicateUse> get _uses => [
    (
      cutId: cutId,
      sourceLayerId: sourceLayerId,
      layerIdMap: layerIdMap,
      newGroupIdBySource: newGroupIdBySource,
    ),
    ...siblings,
  ];

  @override
  String get description => 'Link-duplicate layer $sourceLayerId';

  @override
  void execute() {
    repository.updateProject((project) {
      _registryBefore = project.linkRegistry;
      final source = requireCut(project, cutId);
      final seat = newRowPlacement(source.layers, insertionIndex).index;
      var laid = (project: project, groups: project.linkRegistry.groups);
      for (final use in _uses) {
        laid = _laid(
          laid,
          use,
          aimedAt: use.cutId == cutId
              ? insertionIndex
              : mirroredInsertionIndex(
                  project,
                  source: source,
                  sourceIndex: seat,
                  sibling: requireCut(project, use.cutId),
                ),
        );
      }
      return laid.project.copyWith(
        linkRegistry: LayerLinkRegistry(
          groups: [
            ...laid.groups,
            ..._copiedFoldersTied(project, laid.project),
          ],
        ),
      );
    });
    _hasExecuted = true;
  }

  /// [use]'s group copied in its cut, the copies laid where a NEW row would
  /// be asked for [aimedAt], and each joined to the group of the row it
  /// copies.
  static ({Project project, List<LayerLinkGroup> groups}) _laid(
    ({Project project, List<LayerLinkGroup> groups}) laid,
    LinkDuplicateUse use, {
    required int aimedAt,
  }) {
    final group = requireAttachedGroup(
      laid.project,
      cutId: use.cutId,
      layerId: use.sourceLayerId,
    );
    final placement = newRowPlacement(group.cut.layers, aimedAt);
    LayerId copyOf(LayerId id) =>
        use.layerIdMap[id] ?? (throw StateError('No planned copy id for $id'));
    LayerLinkMember inCut(LayerId id) =>
        LayerLinkMember(trackId: group.track.id, cutId: use.cutId, layerId: id);

    final copies = <Layer>[
      for (final member in group.members)
        member.copyWith(
          id: copyOf(member.id),
          // The copied group is FREE, but its INTERNAL attach glue stays:
          // members re-attach to the copied base. Frames, timeline and FX
          // carry over — same FrameIds IS the link.
          attachedToLayerId: member.attachedToLayerId == null
              ? null
              : copyOf(member.attachedToLayerId!),
          // So do the rows its effects name: a member's copy, and a row
          // out of the group the row it was.
          effects: effectsWithRowsRenamed(
            member.effects,
            (row) => use.layerIdMap[row] ?? row,
          ),
          // An ORGANIZER folder copied with the group re-parents its member
          // copies onto the copied folder row. A folder pointer OUT of the
          // slice — the folder the group stood in — is the landing's: the
          // copies join the folder they are put down in.
          folderId: _copiedFolderOf(member, use) ?? placement.folderId,
        ),
    ];
    var groups = laid.groups;
    for (final member in group.members) {
      // FOLDER rows (organizers riding in the slice) never join link
      // groups: linking shares cel banks, and a folder has none — joining
      // the ORIGINAL organizer's group would make deleting the copy
      // dissolve the original's mirror in another cut.
      if (member.kind.groupsLayers) {
        continue;
      }
      groups = linkGroupsJoined(
        groups,
        origin: inCut(member.id),
        joiner: inCut(copyOf(member.id)),
        plannedGroupId: use.newGroupIdBySource[member.id],
      );
    }
    final project =
        updateCutAnywhere(
          laid.project,
          use.cutId,
          (cut) => cut.copyWith(
            layers: [...cut.layers]..insertAll(placement.index, copies),
          ),
        ) ??
        (throw StateError('Cut not found: ${use.cutId}'));
    return (project: project, groups: groups);
  }

  /// The copy of the folder [member] stands in, when the group carried it.
  static LayerId? _copiedFolderOf(Layer member, LinkDuplicateUse use) =>
      switch (member.folderId) {
        final folder? => use.layerIdMap[folder],
        null => null,
      };

  /// The folder rows the group carried, copied in more than one cut, tied
  /// to each other as an added folder row is to its siblings' — and never
  /// to the folder they copy ([_laid]).
  List<LayerLinkGroup> _copiedFoldersTied(Project before, Project laid) {
    final members = requireAttachedGroup(
      before,
      cutId: cutId,
      layerId: sourceLayerId,
    ).members;
    return [
      for (final folder in members)
        if (folder.kind.groupsLayers)
          if (_folderCopies(before, laid, folder.id) case final tied
              when tied.length > 1)
            LayerLinkGroup(id: newGroupIdBySource[folder.id]!, members: tied),
    ];
  }

  /// Every cut's copy of [cutId]'s folder row [folder], where its cut holds
  /// that row.
  List<LayerLinkMember> _folderCopies(
    Project before,
    Project laid,
    LayerId folder,
  ) => [
    for (final use in _uses)
      if (use.cutId == cutId
              ? folder
              : linkCounterpartIn(
                  before,
                  cutId: cutId,
                  layerId: folder,
                  targetCutId: use.cutId,
                )
          case final there?)
        if (use.layerIdMap[there] case final copy?)
          LayerLinkMember(
            trackId: requireCutPosition(laid, use.cutId).trackId,
            cutId: use.cutId,
            layerId: copy,
          ),
  ];

  @override
  void undo() {
    final registryBefore = _registryBefore;
    if (!_hasExecuted || registryBefore == null) {
      throw StateError('Command has not been executed.');
    }
    repository.updateProject((project) {
      var next = project;
      for (final use in _uses) {
        final copyIds = use.layerIdMap.values.toSet();
        next =
            updateCutAnywhere(
              next,
              use.cutId,
              (cut) => cut.copyWith(
                layers: [
                  for (final layer in cut.layers)
                    if (!copyIds.contains(layer.id)) layer,
                ],
              ),
            ) ??
            (throw StateError('Cut not found: ${use.cutId}'));
      }
      return next.copyWith(linkRegistry: registryBefore);
    });
  }
}

/// One cut's share of a 링크 복제: the row of the source it holds, and the
/// planned ids of its group's copies there ([LinkDuplicateLayerCommand]).
typedef LinkDuplicateUse = ({
  CutId cutId,
  LayerId sourceLayerId,
  Map<LayerId, LayerId> layerIdMap,
  Map<LayerId, String> newGroupIdBySource,
});

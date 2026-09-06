import '../../models/cut_id.dart';
import '../../models/layer_folder.dart';
import '../../models/layer_id.dart';
import '../../models/layer_link_registry.dart';
import '../command.dart';
import '../project_lookup.dart';
import '../project_repository.dart';
import 'folder_mirror.dart';

/// 폴더 생성: folds [memberLayerIds] (a contiguous stack run — the
/// coordinator hands whole attach groups) into a new FOLDER LAYER inserted
/// directly above the run.
///
/// In 겸용 cuts the same folder appears around the members' counterparts in
/// the SAME command, and the folder rows join ONE link group — so from here
/// on the folder's eye, static opacity, blend and name mirror through the
/// ordinary layer machinery, with its FX lanes and twirl staying per-use
/// exactly like any other layer's. One undo removes them everywhere.
class CreateFolderCommand implements Command {
  CreateFolderCommand({
    required this.repository,
    required this.cutId,
    required this.name,
    required this.memberLayerIds,
    required this.folderIdByCut,
    required this.groupId,
  });

  final ProjectRepository repository;
  final CutId cutId;
  final String name;
  final List<LayerId> memberLayerIds;

  /// Planned new folder-layer id per cut (the origin AND every mirror cut)
  /// — ids are per-cut, planned up front so redo reuses them.
  final Map<CutId, LayerId> folderIdByCut;

  /// Planned registry group id tying the folder rows together (unused when
  /// there is no mirror cut).
  final String groupId;

  /// (cut, layer) → previous folderId, for undo.
  List<({CutId cutId, LayerId layerId, LayerId? previousFolderId})>? _moved;
  LayerLinkRegistry? _registryBefore;

  @override
  String get description => 'Create folder "$name"';

  @override
  void execute() {
    final project = repository.requireProject();
    final targets = <({CutId cutId, List<LayerId> members})>[
      (cutId: cutId, members: memberLayerIds),
      for (final mirror in folderMirrorCuts(
        project,
        cutId: cutId,
        memberLayerIds: memberLayerIds,
      ))
        if (folderIdByCut.containsKey(mirror.cutId))
          (
            cutId: mirror.cutId,
            members: [
              for (final memberId in memberLayerIds)
                mirror.counterpartOf[memberId]!,
            ],
          ),
    ];

    final moved =
        <({CutId cutId, LayerId layerId, LayerId? previousFolderId})>[];
    _registryBefore ??= project.linkRegistry;
    final folderMembers = <LayerLinkMember>[];
    for (final target in targets) {
      final cut = requireCut(project, target.cutId);
      final newFolderId = folderIdByCut[target.cutId]!;
      // The new folder nests under the members' common CURRENT folder
      // (null → top level; disagreement → top level, defensively) and
      // sits DIRECTLY ABOVE the member run, which is the stack position
      // the group buffer reads.
      LayerId? parentId;
      var first = true;
      var insertionIndex = 0;
      for (final memberId in target.members) {
        final index = cut.layers.indexWhere((layer) => layer.id == memberId);
        final member = cut.layers[index];
        if (index + 1 > insertionIndex) {
          insertionIndex = index + 1;
        }
        if (first) {
          parentId = member.folderId;
          first = false;
        } else if (parentId != member.folderId) {
          parentId = null;
        }
      }
      repository.insertLayer(
        cutId: target.cutId,
        layer: createFolderLayer(
          id: newFolderId,
          name: name,
          parentId: parentId,
        ),
        index: insertionIndex,
      );
      for (final memberId in target.members) {
        final member = cut.layers.firstWhere((layer) => layer.id == memberId);
        moved.add((
          cutId: target.cutId,
          layerId: memberId,
          previousFolderId: member.folderId,
        ));
        repository.updateLayerFolderId(
          cutId: target.cutId,
          layerId: memberId,
          folderId: newFolderId,
        );
      }
      folderMembers.add(
        LayerLinkMember(
          trackId: requireCutPosition(project, target.cutId).trackId,
          cutId: target.cutId,
          layerId: newFolderId,
        ),
      );
    }
    if (folderMembers.length > 1) {
      repository.updateProject(
        (current) => current.copyWith(
          linkRegistry: LayerLinkRegistry(
            groups: [
              ...current.linkRegistry.groups,
              LayerLinkGroup(id: groupId, members: folderMembers),
            ],
          ),
        ),
      );
    }
    _moved ??= moved;
  }

  @override
  void undo() {
    final moved = _moved;
    final registryBefore = _registryBefore;
    if (moved == null || registryBefore == null) {
      throw StateError('Command has not been executed.');
    }
    for (final move in moved) {
      repository.updateLayerFolderId(
        cutId: move.cutId,
        layerId: move.layerId,
        folderId: move.previousFolderId,
      );
    }
    for (final entry in folderIdByCut.entries) {
      // Tolerant like the old table filter: execute() recomputes its mirror
      // targets from the live project, so a planned row may legitimately
      // never have been created.
      final cut = requireCut(repository.requireProject(), entry.key);
      if (cut.layers.any((layer) => layer.id == entry.value)) {
        repository.deleteLayer(cutId: entry.key, layerId: entry.value);
      }
    }
    repository.restoreLinkRegistry(registryBefore);
  }
}

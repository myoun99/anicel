import '../../models/attached_layer_resolve.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/layer_folder.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/project.dart';
import '../../models/timeline_repeat.dart';
import '../clipboard/layer_copy_payload.dart';
import 'convert_to_linked_cut_plan.dart';
import 'folder_mirror.dart';

class CreateCutCommandInputPlan {
  const CreateCutCommandInputPlan({required this.cutId, required this.layerId});

  final CutId cutId;
  final LayerId layerId;
}

class DeleteLastCutReplacementInputPlan {
  const DeleteLastCutReplacementInputPlan({
    required this.replacementCutId,
    required this.replacementLayerId,
  });

  final CutId replacementCutId;
  final LayerId replacementLayerId;
}

class PasteLayerCommandInputPlan {
  PasteLayerCommandInputPlan({
    required this.newLayerId,
    required Map<FrameId, FrameId> frameIdMap,
    required this.layer,
    required this.insertionIndex,
  }) : frameIdMap = Map.unmodifiable(frameIdMap);

  final LayerId newLayerId;
  final Map<FrameId, FrameId> frameIdMap;
  final Layer layer;
  final int insertionIndex;
}

class DuplicateCutCommandInputPlan {
  DuplicateCutCommandInputPlan({
    required this.newCutId,
    required Map<LayerId, LayerId> layerIdMap,
    required Map<FrameId, FrameId> frameIdMap,
  }) : layerIdMap = Map.unmodifiable(layerIdMap),
       frameIdMap = Map.unmodifiable(frameIdMap);

  final CutId newCutId;
  final Map<LayerId, LayerId> layerIdMap;
  final Map<FrameId, FrameId> frameIdMap;
}

CreateCutCommandInputPlan planCreateCutCommandInput(Project project) {
  final ids = _ProjectIdSnapshot.fromProject(project);
  return CreateCutCommandInputPlan(
    cutId: CutId(_firstAvailableId(prefix: 'cut', usedIds: ids.cutIds)),
    layerId: LayerId(_firstAvailableId(prefix: 'layer', usedIds: ids.layerIds)),
  );
}

DeleteLastCutReplacementInputPlan planDeleteLastCutReplacementInput(
  Project project,
) {
  final ids = _ProjectIdSnapshot.fromProject(project);
  return DeleteLastCutReplacementInputPlan(
    replacementCutId: CutId(
      _firstAvailableId(prefix: 'cut', usedIds: ids.cutIds),
    ),
    replacementLayerId: LayerId(
      _firstAvailableId(prefix: 'layer', usedIds: ids.layerIds),
    ),
  );
}

DuplicateCutCommandInputPlan planDuplicateCutCommandInput({
  required Project project,
  required Cut sourceCut,
}) {
  final ids = _ProjectIdSnapshot.fromProject(project);
  ids.includeCut(sourceCut);

  final newCutId = CutId(_firstAvailableId(prefix: 'cut', usedIds: ids.cutIds));
  ids.cutIds.add(newCutId.value);

  final layerIdMap = <LayerId, LayerId>{};
  final frameIdMap = <FrameId, FrameId>{};

  for (final layer in sourceCut.layers) {
    final newLayerId = LayerId(
      _firstAvailableId(prefix: 'layer', usedIds: ids.layerIds),
    );
    ids.layerIds.add(newLayerId.value);
    layerIdMap[layer.id] = newLayerId;

    for (final frame in layer.frames) {
      if (frameIdMap.containsKey(frame.id)) {
        continue;
      }
      final newFrameId = FrameId(
        _firstAvailableId(prefix: 'frame', usedIds: ids.frameIds),
      );
      ids.frameIds.add(newFrameId.value);
      frameIdMap[frame.id] = newFrameId;
    }

    for (final exposure in layer.timeline.values) {
      final frameId = exposure.frameId;
      if (frameId == null || frameIdMap.containsKey(frameId)) {
        continue;
      }
      final newFrameId = FrameId(
        _firstAvailableId(prefix: 'frame', usedIds: ids.frameIds),
      );
      ids.frameIds.add(newFrameId.value);
      frameIdMap[frameId] = newFrameId;
    }
  }

  return DuplicateCutCommandInputPlan(
    newCutId: newCutId,
    layerIdMap: layerIdMap,
    frameIdMap: frameIdMap,
  );
}

PasteLayerCommandInputPlan planPasteLayerCommandInput({
  required Project project,
  required Cut targetCut,
  required LayerCopyPayload payload,
  required int insertionIndex,
}) {
  final ids = _ProjectIdSnapshot.fromProject(project)..includeCut(targetCut);
  final newLayerId = LayerId(
    _firstAvailableId(prefix: 'layer', usedIds: ids.layerIds),
  );
  ids.layerIds.add(newLayerId.value);

  final frameIdMap = <FrameId, FrameId>{};
  for (final frame in payload.frames) {
    frameIdMap.putIfAbsent(frame.id, () {
      final id = FrameId(
        _firstAvailableId(prefix: 'frame', usedIds: ids.frameIds),
      );
      ids.frameIds.add(id.value);
      return id;
    });
  }
  for (final exposure in payload.timeline.values) {
    final frameId = exposure.frameId;
    if (frameId == null) continue;
    frameIdMap.putIfAbsent(frameId, () {
      final id = FrameId(
        _firstAvailableId(prefix: 'frame', usedIds: ids.frameIds),
      );
      ids.frameIds.add(id.value);
      return id;
    });
  }

  final hasStoryboardLayer = targetCut.layers.any(
    (layer) => layer.kind == LayerKind.storyboard,
  );
  // Kinds survive the paste except storyboard (unique per cut — extra copies
  // land as animation) and camera (refused upstream).
  final pastedKind = switch (payload.kind) {
    LayerKind.storyboard =>
      hasStoryboardLayer ? LayerKind.animation : LayerKind.storyboard,
    LayerKind.camera => LayerKind.animation,
    final kind => kind,
  };
  final layer = Layer(
    id: newLayerId,
    name: payload.name,
    frames: payload.frames
        .map((frame) => frame.copyWith(id: frameIdMap[frame.id]))
        .toList(),
    timeline: payload.timeline.map((index, exposure) {
      final sourceFrameId = exposure.frameId;
      final newFrameId = sourceFrameId == null
          ? null
          : frameIdMap[sourceFrameId];
      if (sourceFrameId == null || newFrameId == null) {
        throw ArgumentError.value(
          frameIdMap,
          'frameIdMap',
          'Missing mapped FrameId for timeline exposure ${exposure.frameId}.',
        );
      }
      return MapEntry(index, exposure.copyWith(frameId: newFrameId));
    }),
    // Instruction spans only belong on instruction rows and audio clips on
    // SE rows; cross-kind pastes drop them.
    instructions: pastedKind == LayerKind.instruction
        ? payload.instructions
        : const {},
    audioClips: pastedKind == LayerKind.se ? payload.audioClips : const [],
    isVisible: payload.isVisible,
    opacity: payload.opacity,
    kind: pastedKind,
    // The reference is kind-agnostic (§6-z23's second axis): the pasted
    // copy shows the same library asset.
    mediaReference: payload.mediaReference,
    // A copy looks like the row it came from (user, 07-30 "합성포함해서
    // 싹다"): the composite-time state travels with the artwork.
    blendMode: payload.blendMode,
    transformTrack: payload.transformTrack,
    transformEnabled: payload.transformEnabled,
    effects: payload.effects,
    mark: payload.mark,
    onTimesheet: payload.onTimesheet,
    isFillReference: payload.isFillReference,
    // Run behaviours are addressed by FRAME ID, so their anchors remap onto
    // the copied frames — carrying them verbatim would name blocks this
    // copy does not have, and the next rederive would drop them.
    runBehaviors: [
      for (final behavior in payload.runBehaviors)
        TimelineRunBehavior(
          anchorFrameId:
              frameIdMap[behavior.anchorFrameId] ?? behavior.anchorFrameId,
          side: behavior.side,
          mode: behavior.mode,
          patternAnchorFrameId: behavior.patternAnchorFrameId == null
              ? null
              : (frameIdMap[behavior.patternAnchorFrameId!] ??
                    behavior.patternAnchorFrameId),
        ),
    ],
  );

  return PasteLayerCommandInputPlan(
    newLayerId: newLayerId,
    frameIdMap: frameIdMap,
    layer: layer,
    insertionIndex: insertionIndex,
  );
}

class CreateLinkedCutCommandInputPlan {
  const CreateLinkedCutCommandInputPlan({
    required this.newCutId,
    required this.layerIdMap,
    required this.newGroupIdBySource,
  });

  final CutId newCutId;

  /// Source row → linked copy's id, FOLDER ROWS INCLUDED (a folder is a
  /// layer, so it needs no id map of its own — [Layer.folderId] maps
  /// through this one).
  final Map<LayerId, LayerId> layerIdMap;
  final Map<LayerId, String> newGroupIdBySource;
}

/// Whether a row of [kind] copies into a 겸용컷: the drawing layers whose
/// pictures are shared — IMAGE rows included (the shared BG is the
/// classic 겸용 case; the linked copy shares the cel id and the covering
/// normalization re-covers it) and TEXT rows too (§6-z5: "레이어는 모두
/// 겸용컷에서 공유된다" — the escape hatch for per-cut cut numbers is the
/// ordinary 독립시키기) — plus the folder rows that hold them ("폴더
/// 존재/멤버십은 공유 구조"). SE/instruction/camera rows are per-use
/// fixtures.
bool _linksIntoLinkedCut(LayerKind kind) => layerKindLinksIntoLinkedCut(kind);

/// Plans a 겸용컷 생성 (L2): a new cut id, one linked-copy id per linked
/// row of [sourceCut] (drawing layers and their folders), and registry
/// group ids. FrameIds are NOT mapped — identity is the link.
CreateLinkedCutCommandInputPlan planCreateLinkedCutCommandInput({
  required Project project,
  required Cut sourceCut,
}) {
  final ids = _ProjectIdSnapshot.fromProject(project);
  final newCutId = CutId(_firstAvailableId(prefix: 'cut', usedIds: ids.cutIds));
  ids.cutIds.add(newCutId.value);

  final layerIdMap = <LayerId, LayerId>{};
  for (final layer in sourceCut.layers) {
    if (!_linksIntoLinkedCut(layer.kind)) {
      continue;
    }
    final copyId = LayerId(
      _firstAvailableId(prefix: 'layer', usedIds: ids.layerIds),
    );
    ids.layerIds.add(copyId.value);
    layerIdMap[layer.id] = copyId;
  }

  final usedGroupIds = <String>{
    for (final group in project.linkRegistry.groups) group.id,
  };
  final newGroupIdBySource = <LayerId, String>{};
  for (final layer in sourceCut.layers) {
    if (!_linksIntoLinkedCut(layer.kind)) {
      continue;
    }
    final groupId = _firstAvailableId(prefix: 'link', usedIds: usedGroupIds);
    usedGroupIds.add(groupId);
    newGroupIdBySource[layer.id] = groupId;
  }

  return CreateLinkedCutCommandInputPlan(
    newCutId: newCutId,
    layerIdMap: layerIdMap,
    newGroupIdBySource: newGroupIdBySource,
  );
}

class ConvertToLinkedCutCommandInputPlan {
  const ConvertToLinkedCutCommandInputPlan({
    required this.unionLayerIdMap,
    required this.newGroupIdBySource,
  });

  /// (owning cut, source layer) → new copy id in the OTHER cut.
  final Map<(CutId, LayerId), LayerId> unionLayerIdMap;

  /// Planned registry group id per newly-linked source layer.
  final Map<LayerId, String> newGroupIdBySource;
}

/// Plans a 겸용 변경 (L2b): copy ids for the one-side-only layers that
/// UNION into the other cut, and registry group ids for every pair/union
/// that is not linked yet.
ConvertToLinkedCutCommandInputPlan planConvertToLinkedCutCommandInput({
  required Project project,
  required Cut originCut,
  required Cut targetCut,
}) {
  final plan = planConvertToLinkedCut(
    project: project,
    originCut: originCut,
    targetCut: targetCut,
  );
  final ids = _ProjectIdSnapshot.fromProject(project);
  final usedGroupIds = <String>{
    for (final group in project.linkRegistry.groups) group.id,
  };

  final unionLayerIdMap = <(CutId, LayerId), LayerId>{};
  final newGroupIdBySource = <LayerId, String>{};

  String nextGroupId() {
    final id = _firstAvailableId(prefix: 'link', usedIds: usedGroupIds);
    usedGroupIds.add(id);
    return id;
  }

  LayerId nextLayerId() {
    final id = LayerId(_firstAvailableId(prefix: 'layer', usedIds: ids.layerIds));
    ids.layerIds.add(id.value);
    return id;
  }

  for (final pair in plan.layerPairs) {
    newGroupIdBySource[pair.originLayerId] = nextGroupId();
  }
  for (final originLayerId in plan.originOnlyLayerIds) {
    unionLayerIdMap[(originCut.id, originLayerId)] = nextLayerId();
    newGroupIdBySource[originLayerId] = nextGroupId();
  }
  for (final targetLayerId in plan.targetOnlyLayerIds) {
    unionLayerIdMap[(targetCut.id, targetLayerId)] = nextLayerId();
    newGroupIdBySource[targetLayerId] = nextGroupId();
  }

  return ConvertToLinkedCutCommandInputPlan(
    unionLayerIdMap: unionLayerIdMap,
    newGroupIdBySource: newGroupIdBySource,
  );
}

class LinkDuplicateLayerCommandInputPlan {
  const LinkDuplicateLayerCommandInputPlan({
    required this.layerIdMap,
    required this.newGroupIdBySource,
  });

  /// Source member id → its copy's id, over the whole attach group.
  final Map<LayerId, LayerId> layerIdMap;

  /// Planned registry group id per source member (used only for members
  /// that are not in a link group yet).
  final Map<LayerId, String> newGroupIdBySource;
}

/// Plans a 링크 복제 (L2): one copy id per member of [sourceLayerId]'s
/// attach group, plus fresh registry group ids. FrameIds are NOT mapped —
/// keeping them identical IS the link.
LinkDuplicateLayerCommandInputPlan planLinkDuplicateLayerCommandInput({
  required Project project,
  required Cut cut,
  required LayerId sourceLayerId,
}) {
  final ids = _ProjectIdSnapshot.fromProject(project);
  final source = cut.layers.firstWhere((layer) => layer.id == sourceLayerId);
  final baseId = source.attachedToLayerId ?? source.id;
  final members = cut.layers.sublist(
    attachedGroupStartIndex(baseId, cut.layers),
    attachedGroupEndIndex(baseId, cut.layers),
  );

  final layerIdMap = <LayerId, LayerId>{};
  for (final member in members) {
    final copyId = LayerId(
      _firstAvailableId(prefix: 'layer', usedIds: ids.layerIds),
    );
    ids.layerIds.add(copyId.value);
    layerIdMap[member.id] = copyId;
  }

  final usedGroupIds = <String>{
    for (final group in project.linkRegistry.groups) group.id,
  };
  final newGroupIdBySource = <LayerId, String>{};
  for (final member in members) {
    final groupId = _firstAvailableId(prefix: 'link', usedIds: usedGroupIds);
    usedGroupIds.add(groupId);
    newGroupIdBySource[member.id] = groupId;
  }

  return LinkDuplicateLayerCommandInputPlan(
    layerIdMap: layerIdMap,
    newGroupIdBySource: newGroupIdBySource,
  );
}

class CreateFolderCommandInputPlan {
  const CreateFolderCommandInputPlan({
    required this.folderIdByCut,
    required this.folderGroupId,
  });

  /// Planned new folder-LAYER id for the origin cut AND each 겸용 mirror
  /// cut (ids are per-cut; planned up front so redo reuses them).
  final Map<CutId, LayerId> folderIdByCut;

  /// Planned registry group id tying those folder rows together, so the
  /// folder's shared properties mirror through the ordinary layer path.
  final String folderGroupId;
}

/// Plans a 폴더 생성: one fresh folder-layer id per cut the command will
/// touch (the origin plus every mirror cut of [memberLayerIds]), plus the
/// link group they join.
CreateFolderCommandInputPlan planCreateFolderCommandInput({
  required Project project,
  required CutId cutId,
  required List<LayerId> memberLayerIds,
}) {
  final ids = _ProjectIdSnapshot.fromProject(project);
  LayerId next() {
    final id = LayerId(
      _firstAvailableId(prefix: 'folder', usedIds: ids.layerIds),
    );
    ids.layerIds.add(id.value);
    return id;
  }

  return CreateFolderCommandInputPlan(
    folderIdByCut: {
      cutId: next(),
      for (final mirror in folderMirrorCuts(
        project,
        cutId: cutId,
        memberLayerIds: memberLayerIds,
      ))
        mirror.cutId: next(),
    },
    folderGroupId: _firstAvailableId(
      prefix: 'link',
      usedIds: {for (final group in project.linkRegistry.groups) group.id},
    ),
  );
}

/// "Folder N" with the first free N among [cut]'s folder rows.
String nextFolderName(Cut cut) {
  final used = {for (final folder in cut.layers.folderLayers) folder.name};
  var number = 1;
  while (used.contains('Folder $number')) {
    number += 1;
  }
  return 'Folder $number';
}

String _firstAvailableId({
  required String prefix,
  required Set<String> usedIds,
}) {
  var candidateNumber = 1;
  while (true) {
    final candidate = '$prefix-$candidateNumber';
    if (!usedIds.contains(candidate)) {
      return candidate;
    }
    candidateNumber += 1;
  }
}

class _ProjectIdSnapshot {
  _ProjectIdSnapshot({
    required this.cutIds,
    required this.layerIds,
    required this.frameIds,
  });

  factory _ProjectIdSnapshot.fromProject(Project project) {
    final snapshot = _ProjectIdSnapshot(
      cutIds: <String>{},
      layerIds: <String>{},
      frameIds: <String>{},
    );

    for (final track in project.tracks) {
      for (final cut in track.cuts) {
        snapshot.includeCut(cut);
      }
    }

    return snapshot;
  }

  final Set<String> cutIds;
  final Set<String> layerIds;
  final Set<String> frameIds;

  void includeCut(Cut cut) {
    cutIds.add(cut.id.value);
    for (final layer in cut.layers) {
      layerIds.add(layer.id.value);
      for (final frame in layer.frames) {
        frameIds.add(frame.id.value);
      }
      for (final exposure in layer.timeline.values) {
        final frameId = exposure.frameId;
        if (frameId != null) {
          frameIds.add(frameId.value);
        }
      }
    }
  }
}

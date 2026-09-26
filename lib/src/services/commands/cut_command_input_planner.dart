import '../../models/attached_layer_resolve.dart';
import '../../models/conte/conte_ink_keys.dart'
    show conteHandwritingOfACopy, conteInkRowLayerId;
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/layer_folder.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/project.dart';
import '../clipboard/layer_copy_payload.dart';
import '../editing/cut_duplicate_helpers.dart' show remapTimelineExposure;
import '../editing/run_id_mint.dart' show mintCutId, mintFrameId;
import '../project_lookup.dart' show requireCut;
import '../project_repository.dart';
import 'add_layer_command.dart';
import 'convert_to_linked_cut_plan.dart';
import 'folder_mirror.dart';
import 'link_mirror.dart';

class CreateCutCommandInputPlan {
  const CreateCutCommandInputPlan({required this.cutId, required this.layerId});

  final CutId cutId;
  final LayerId layerId;
}


class PasteLayerCommandInputPlan {
  PasteLayerCommandInputPlan({
    required this.newLayerId,
    required Map<FrameId, FrameId> frameIdMap,
    required this.layer,
    required this.insertionIndex,
    Map<String, String> handwriting = const {},
  }) : frameIdMap = Map.unmodifiable(frameIdMap),
       handwriting = Map.unmodifiable(handwriting);

  final LayerId newLayerId;
  final Map<FrameId, FrameId> frameIdMap;
  final Layer layer;
  final int insertionIndex;

  /// By each of the pasted blocks' handwriting ids, the one it starts as a
  /// copy of ([conteHandwritingOfACopy]).
  final Map<String, String> handwriting;
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
    cutId: mintCutId(),
    layerId: LayerId(_firstAvailableId(prefix: 'layer', usedIds: ids.layerIds)),
  );
}


DuplicateCutCommandInputPlan planDuplicateCutCommandInput({
  required Project project,
  required Cut sourceCut,
}) {
  final ids = _ProjectIdSnapshot.fromProject(project);
  ids.includeCut(sourceCut);

  final newCutId = mintCutId();

  final layerIdMap = <LayerId, LayerId>{};
  final frameIdMap = <FrameId, FrameId>{};

  for (final layer in sourceCut.layers) {
    final newLayerId = LayerId(
      _firstAvailableId(prefix: 'layer', usedIds: ids.layerIds),
    );
    ids.layerIds.add(newLayerId.value);
    layerIdMap[layer.id] = newLayerId;

    for (final frame in layer.frames) {
      _copyOf(frame.id, on: newLayerId, into: frameIdMap);
    }

    for (final exposure in layer.timeline.values) {
      final frameId = exposure.frameId;
      if (frameId == null) {
        continue;
      }
      _copyOf(frameId, on: newLayerId, into: frameIdMap);
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
    _copyOf(frame.id, on: newLayerId, into: frameIdMap);
  }
  for (final exposure in payload.timeline.values) {
    final frameId = exposure.frameId;
    if (frameId == null) continue;
    _copyOf(frameId, on: newLayerId, into: frameIdMap);
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
  // Every block of the copy writes on the conte for itself: a row pasted
  // beside its source must not share its source's handwriting.
  final written = conteHandwritingOfACopy(
    payload.timeline.map(
      (index, exposure) => MapEntry(
        index,
        remapTimelineExposure(exposure: exposure, frameIdMap: frameIdMap),
      ),
    ),
    () => mintFrameId(conteInkRowLayerId).value,
  );
  final layer = Layer(
    id: newLayerId,
    name: payload.name,
    frames: payload.frames
        .map((frame) => frame.copyWith(id: frameIdMap[frame.id]))
        .toList(),
    timeline: written.exposures,
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
  );

  return PasteLayerCommandInputPlan(
    newLayerId: newLayerId,
    frameIdMap: frameIdMap,
    layer: layer,
    insertionIndex: insertionIndex,
    handwriting: written.copies,
  );
}

class CreateLinkedCutCommandInputPlan {
  const CreateLinkedCutCommandInputPlan({
    required this.newCutId,
    required this.layerIdMap,
    required this.newGroupIdBySource,
    required this.coveringFrameIdBySource,
  });

  final CutId newCutId;

  /// Source row → linked copy's id, FOLDER ROWS INCLUDED (a folder is a
  /// layer, so it needs no id map of its own — [Layer.folderId] maps
  /// through this one).
  final Map<LayerId, LayerId> layerIdMap;
  final Map<LayerId, String> newGroupIdBySource;

  /// The fresh panel each row that cannot stand empty is born with in the
  /// new cut (F-99), keyed by its source row.
  final Map<LayerId, FrameId> coveringFrameIdBySource;
}

/// A fresh layer id and a fresh link-group id for each of [sources],
/// minted against what [project] and [ids] already hold.
///
/// ⛔THE TWO MAPS MUST BE KEYED BY THE SAME SOURCES. The command reads one
/// to build the copy and the other to register the link, so a planner that
/// walked its sources twice — filtering each time — could register a group
/// for a layer it never copied the moment the two filters drifted apart.
/// Both link planners did exactly that walk.
({Map<LayerId, LayerId> layerIdMap, Map<LayerId, String> newGroupIdBySource})
_mintLinkIds(
  Project project,
  _ProjectIdSnapshot ids,
  Iterable<Layer> sources,
) {
  final usedGroupIds = <String>{
    for (final group in project.linkRegistry.groups) group.id,
  };
  final layerIdMap = <LayerId, LayerId>{};
  final newGroupIdBySource = <LayerId, String>{};
  for (final source in sources) {
    final copyId = LayerId(
      _firstAvailableId(prefix: 'layer', usedIds: ids.layerIds),
    );
    ids.layerIds.add(copyId.value);
    layerIdMap[source.id] = copyId;

    final groupId = _firstAvailableId(prefix: 'link', usedIds: usedGroupIds);
    usedGroupIds.add(groupId);
    newGroupIdBySource[source.id] = groupId;
  }
  return (layerIdMap: layerIdMap, newGroupIdBySource: newGroupIdBySource);
}

/// Plans a 겸용컷 생성 (L2): a new cut id, one linked-copy id per linked
/// row of [sourceCut] (every kind that links — drawing rows, their folders,
/// the conte row and the camera row), and registry group ids. FrameIds are
/// NOT mapped — identity is the link — except the fresh panel a row that
/// cannot stand empty is born with (F-99).
CreateLinkedCutCommandInputPlan planCreateLinkedCutCommandInput({
  required Project project,
  required Cut sourceCut,
}) {
  final ids = _ProjectIdSnapshot.fromProject(project);
  final newCutId = mintCutId();

  final minted = _mintLinkIds(project, ids, [
    for (final layer in sourceCut.layers)
      if (layer.kind.linksIntoLinkedCut) layer,
  ]);

  return CreateLinkedCutCommandInputPlan(
    newCutId: newCutId,
    layerIdMap: minted.layerIdMap,
    newGroupIdBySource: minted.newGroupIdBySource,
    coveringFrameIdBySource: {
      for (final layer in sourceCut.layers)
        if (minted.layerIdMap.containsKey(layer.id) &&
            _bornWithAFreshPanel(layer))
          layer.id: mintFrameId(minted.layerIdMap[layer.id]!),
    },
  );
}

/// Whether [layer]'s copy in another cut is born covering that cut with a
/// panel of its own (F-99): a COVERING row is — the conte row. The image row
/// covers too, but its ONE cel is the picture it shares, and the write
/// normalization re-covers the row from it (D22).
bool _bornWithAFreshPanel(Layer layer) =>
    layer.kind.coversWithoutGaps && !layer.kind.holdsSingleCel;

class ConvertToLinkedCutCommandInputPlan {
  const ConvertToLinkedCutCommandInputPlan({
    required this.unionLayerIdMap,
    required this.newGroupIdBySource,
    required this.coveringFrameIdBySource,
  });

  /// (owning cut, source layer) → new copy id in the OTHER cut.
  final Map<(CutId, LayerId), LayerId> unionLayerIdMap;

  /// Planned registry group id per newly-linked source layer.
  final Map<LayerId, String> newGroupIdBySource;

  /// The fresh panel each union copy of a row that cannot stand empty is
  /// born with (F-99), keyed like [unionLayerIdMap].
  final Map<(CutId, LayerId), FrameId> coveringFrameIdBySource;
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
  final coveringFrameIdBySource = <(CutId, LayerId), FrameId>{};

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

  void planUnion(Cut owner, LayerId layerId) {
    unionLayerIdMap[(owner.id, layerId)] = nextLayerId();
    newGroupIdBySource[layerId] = nextGroupId();
    if (_bornWithAFreshPanel(
      owner.layers.firstWhere((layer) => layer.id == layerId),
    )) {
      coveringFrameIdBySource[(owner.id, layerId)] = mintFrameId(
        unionLayerIdMap[(owner.id, layerId)]!,
      );
    }
  }

  for (final pair in plan.layerPairs) {
    newGroupIdBySource[pair.originLayerId] = nextGroupId();
  }
  for (final originLayerId in plan.originOnlyLayerIds) {
    planUnion(originCut, originLayerId);
  }
  for (final targetLayerId in plan.targetOnlyLayerIds) {
    planUnion(targetCut, targetLayerId);
  }

  return ConvertToLinkedCutCommandInputPlan(
    unionLayerIdMap: unionLayerIdMap,
    newGroupIdBySource: newGroupIdBySource,
    coveringFrameIdBySource: coveringFrameIdBySource,
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
  final members = attachedGroupSlice(attachBaseIdOf(source), cut.layers);

  final minted = _mintLinkIds(project, ids, members);

  return LinkDuplicateLayerCommandInputPlan(
    layerIdMap: minted.layerIdMap,
    newGroupIdBySource: minted.newGroupIdBySource,
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

class AddLayerCommandInputPlan {
  const AddLayerCommandInputPlan({
    required this.mirrors,
    required this.linkGroupId,
  });

  static const AddLayerCommandInputPlan none = AddLayerCommandInputPlan(
    mirrors: [],
    linkGroupId: null,
  );

  /// The 겸용 sibling cuts this layer also appears in, with their planned
  /// per-cut ids.
  final List<AddLayerMirror> mirrors;

  /// Planned registry group id tying the new rows together; null when
  /// nothing mirrors.
  final String? linkGroupId;
}

/// Plans a layer CREATION across 겸용 cuts: one fresh layer id per sibling
/// cut, its anchors resolved to that cut's own rows, plus the link group
/// they join.
///
/// Kinds that do not link into a 겸용 cut plan no mirrors — the per-use SE
/// and direction fixtures already exist in every cut
/// ([LayerKind.linksIntoLinkedCut] is the one predicate for that question).
/// A SINGLETON kind — the conte row, the camera row — mirrors only into a
/// sibling that has none: a cut holds one ([LayerKind.isSingletonPerCut]),
/// so a sibling with its own keeps it and the new row stays this cut's.
///
/// A sibling whose counterpart for an anchor is missing is DROPPED rather
/// than guessed at (folder_mirror's rule): a row inheriting a folder that
/// only exists in the origin cut would break the sibling's folder
/// invariant, and an attach row without its base is not a row at all.
AddLayerCommandInputPlan planAddLayerCommandInput({
  required Project project,
  required CutId cutId,
  required Layer layer,
}) {
  if (!layer.kind.linksIntoLinkedCut) {
    return AddLayerCommandInputPlan.none;
  }
  final siblings = linkedCutSiblings(project, cutId: cutId);
  if (siblings.isEmpty) {
    return AddLayerCommandInputPlan.none;
  }

  final ids = _ProjectIdSnapshot.fromProject(project);
  LayerId next() {
    final id = LayerId(
      _firstAvailableId(prefix: 'layer', usedIds: ids.layerIds),
    );
    ids.layerIds.add(id.value);
    return id;
  }

  LayerId? counterpart(LayerId anchor, CutId sibling) => linkCounterpartIn(
    project,
    cutId: cutId,
    layerId: anchor,
    targetCutId: sibling,
  );

  final mirrors = <AddLayerMirror>[];
  for (final sibling in siblings) {
    if (layer.kind.isSingletonPerCut &&
        requireCut(
          project,
          sibling,
        ).layers.any((row) => row.kind == layer.kind)) {
      continue;
    }
    final folder = layer.folderId;
    final base = layer.attachedToLayerId;
    final mirroredFolder = folder == null ? null : counterpart(folder, sibling);
    final mirroredBase = base == null ? null : counterpart(base, sibling);
    if ((folder != null && mirroredFolder == null) ||
        (base != null && mirroredBase == null)) {
      continue;
    }
    mirrors.add(
      AddLayerMirror(
        cutId: sibling,
        layerId: next(),
        folderId: mirroredFolder,
        attachedToLayerId: mirroredBase,
      ),
    );
  }
  if (mirrors.isEmpty) {
    return AddLayerCommandInputPlan.none;
  }

  return AddLayerCommandInputPlan(
    mirrors: mirrors,
    linkGroupId: _firstAvailableId(
      prefix: 'link',
      usedIds: {for (final group in project.linkRegistry.groups) group.id},
    ),
  );
}

/// [layer] added to [cutId] at [insertionIndex], and to the 겸용 siblings
/// [planAddLayerCommandInput] plans against the project as it stands.
///
/// ONE recipe for every way a row is added to a cut: the layer panel's Add
/// Layer, on the cut the canvas stands on, and the conte row a picture's
/// first stroke makes, on the picture's cut.
AddLayerCommand plannedAddLayerCommand({
  required ProjectRepository repository,
  required CutId cutId,
  required Layer layer,
  int? insertionIndex,
}) {
  final plan = planAddLayerCommandInput(
    project: repository.requireProject(),
    cutId: cutId,
    layer: layer,
  );
  return AddLayerCommand(
    repository: repository,
    cutId: cutId,
    layer: layer,
    insertionIndex: insertionIndex,
    mirrors: plan.mirrors,
    linkGroupId: plan.linkGroupId,
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

/// The layer ids the project holds — what a new row's first free
/// `layer-N` steps past.
///
/// ⛔No cut or frame ids here any more: a cut's sheets and a cel's picture
/// are kept by the SESSION under those ids after an undo or a delete, so a
/// copy takes them from the run ([mintCutId], [mintFrameId]) rather than as
/// the first the project has free (card `undone-paste-reuses-ids`). The
/// stores key a row's pictures by its cels' ids, so a row's own id may
/// still be the first free.
class _ProjectIdSnapshot {
  _ProjectIdSnapshot({required this.layerIds});

  factory _ProjectIdSnapshot.fromProject(Project project) {
    final snapshot = _ProjectIdSnapshot(layerIds: <String>{});
    for (final track in project.tracks) {
      for (final cut in track.cuts) {
        snapshot.includeCut(cut);
      }
    }
    return snapshot;
  }

  final Set<String> layerIds;

  void includeCut(Cut cut) {
    for (final layer in cut.layers) {
      layerIds.add(layer.id.value);
    }
  }
}

/// The fresh id [source] copies to on the row [on], minted on first sight
/// and remembered in [into] after that — one cel exposed twice must come
/// out as one cel, not two that look alike. Both copying planners mint
/// this way.
FrameId _copyOf(
  FrameId source, {
  required LayerId on,
  required Map<FrameId, FrameId> into,
}) => into.putIfAbsent(source, () => mintFrameId(on));

import '../../core/inserted_at.dart';
import '../../models/attached_layer_mount.dart' show LayerAttachDrop;
import '../../models/attached_layer_resolve.dart';
import '../../models/attached_placement.dart';
import '../../models/conte_group.dart';
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
import '../../models/track.dart';
import '../clipboard/layer_copy_payload.dart';
import '../command.dart';
import '../editing/cut_duplicate_helpers.dart' show remapTimelineExposure;
import '../editing/run_id_mint.dart' show mintCutId, mintFrameId;
import '../project_lookup.dart' show requireCut;
import '../project_repository.dart';
import 'add_layer_command.dart';
import 'convert_to_linked_cut_plan.dart';
import 'folder_mirror.dart';
import 'link_mirror.dart';

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

  final hasStoryboardLayer = storyboardLayerForCut(targetCut) != null;
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

  /// The fresh panel each row born with a frame is born with in the new
  /// cut (F-99), keyed by its source row.
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
/// NOT mapped — identity is the link — except the fresh panel a row born
/// with a frame is born with (F-99).
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
/// panel of its own (F-99): a COVERING row is — the conte row, and the image
/// row, both born with a frame wherever they are made.
///
/// ↩️The image row was left out: its one cel was 「the picture it shares」,
/// and the write normalization re-covered the copy from it — an UNNAMED
/// picture linked across 겸용 cuts. 유저 2026-09-12 (F-98): 「이미지 레이어는
/// 이름이 없는 상태인데도 겸용컷이랑 링크되는데, 그게아니라 애니메이션
/// 레이어랑 똑같이 이름이 같아야만 링크되도록. 이름 안정해지면 별개것임」,
/// and 2026-10-04: 「물론 이름이 없으면 독립적인 그림이니까 링크 안되는게
/// 맞음」. So the copy is born with a frame of its own, by the law F-99
/// already reuses for the conte row (「생성시 기본적으로 프레임 생성되는데 그
/// 법 그대로 재사용/통일」), and the two link when they are NAMED alike.
///
/// ⛔Not an ATTACH row, whatever kind it took from its base: an attach row is
/// born EMPTY (`FoldersAndAttachments.addAttachedLayer`) — a synced one
/// mirrors its base and stores no lane at all. It was asked by kind alone,
/// which handed the conte row's attach rows a panel nothing shows.
bool _bornWithAFreshPanel(Layer layer) =>
    layer.kind.coversWithoutGaps && !isAttachedLayer(layer);

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

  /// The fresh panel each union copy of a row born with a frame is born
  /// with (F-99), keyed like [unionLayerIdMap].
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
/// cut, its anchors resolved to that cut's own rows, the fresh panel a row
/// born with a frame is born with there ([_bornWithAFreshPanel]), plus the
/// link group they join.
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
}) => _planAddLayerMirrors(_Planting(project), cutId: cutId, layer: layer);

/// What the rows ONE step plants share: the project they are planned
/// against, the ids minted so far — no two rows of the step take the same
/// one — and the cuts the step has already put its row in.
class _Planting {
  _Planting(this.project) : ids = _ProjectIdSnapshot.fromProject(project);

  final Project project;
  final _ProjectIdSnapshot ids;
  final Set<CutId> planted = {};
}

/// [planAddLayerCommandInput] as one of the rows [step] plants: its ids are
/// the step's.
AddLayerCommandInputPlan _planAddLayerMirrors(
  _Planting step, {
  required CutId cutId,
  required Layer layer,
}) {
  final project = step.project;
  if (!layer.kind.linksIntoLinkedCut) {
    return AddLayerCommandInputPlan.none;
  }
  final siblings = linkedCutSiblings(project, cutId: cutId);
  if (siblings.isEmpty) {
    return AddLayerCommandInputPlan.none;
  }

  LayerId? counterpart(LayerId anchor, CutId sibling) => linkCounterpartIn(
    project,
    cutId: cutId,
    layerId: anchor,
    targetCutId: sibling,
  );

  final mirrors = <AddLayerMirror>[];
  for (final sibling in siblings) {
    // The ONE row of its kind, that is — a row riding another is not it
    // ([holdsSingletonOfKind]), so the conte row's attach rows mirror like
    // any drawing row's.
    if (layer.kind.isSingletonPerCut &&
        !isAttachedLayer(layer) &&
        holdsSingletonOfKind(
          requireCut(project, sibling).layers,
          layer.kind,
        )) {
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
    final mirrorId = step.ids.nextLayerId();
    mirrors.add(
      AddLayerMirror(
        cutId: sibling,
        layerId: mirrorId,
        folderId: mirroredFolder,
        attachedToLayerId: mirroredBase,
        coveringFrameId: _bornWithAFreshPanel(layer)
            ? mintFrameId(mirrorId)
            : null,
      ),
    );
  }
  if (mirrors.isEmpty) {
    return AddLayerCommandInputPlan.none;
  }

  return AddLayerCommandInputPlan(
    mirrors: mirrors,
    linkGroupId: step.ids.nextLinkGroupId(),
  );
}

/// [layer] added to [cutId] at [insertionIndex], and to the 겸용 siblings
/// [planAddLayerCommandInput] plans against the project as it stands.
///
/// ONE recipe for every way a row is added to a cut: the layer panel's Add
/// Layer, on the cut the canvas stands on, and the conte row a picture's
/// first stroke makes, on the picture's cut.
///
/// 🚨A ROW OF A TRACK'S CONTE IS PLANTED IN EVERY CUT'S (I-73). The drawn
/// proposal 유저 took on 2026-10-08 lists what a track's conte rows have
/// as one — 「머리 — 이름 · 라벨 · 블렌드 · 불투명도 · 눈 · 어태치 구성 ·
/// fx 구성 — 트랙의 모든 컷이 하나」 — and the attach rows a conte carries
/// are in it. So, in the one undo step:
///
/// - an attach row added to a cut's conte is added to the conte of every
///   other cut of the track ([_conteFamilyRowsOf]);
/// - a conte born into a track whose contes carry attach rows is born
///   carrying them ([_conteAttachRowsBornWith]);
/// - and each of those rows arrives wearing the head of the seat it lands
///   on ([conteBornWearingItsHead]).
///
/// ⛔They join no link group for it (the proposal: 「머리의 통일은 링크
/// 그룹으로 만들지 않습니다」) — a link group is one cel bank, and two
/// cuts' rows in one would make every pair of same-named cels one picture.
/// A planted row's 겸용 siblings still take it AS the same layer: that is
/// the cuts' own relation, planned row by row.
Command plannedAddLayerCommand({
  required ProjectRepository repository,
  required CutId cutId,
  required Layer layer,
  int? insertionIndex,
}) {
  final step = _Planting(repository.requireProject());
  final born = conteBornWearingItsHead(
    step.project,
    cutId: cutId,
    layer: layer,
  );
  final first = _planted(step, repository, (
    cutId: cutId,
    layer: born,
    index: insertionIndex,
  ));
  return oneStepOf(first.description, [
    first,
    for (final row in _conteFamilyRowsOf(step, cutId, born, insertionIndex))
      _planted(step, repository, row),
    ..._conteAttachRowsBornWith(step, first),
  ])!;
}

/// One row a step plants: the cut, the row as it is born there, and where
/// in that cut's stack (null: its top).
typedef _PlantedRow = ({CutId cutId, Layer layer, int? index});

/// [layer] as it is born into [cutId]: wearing the head of the SEAT of its
/// track's conte it lands on (I-73 — [layerWearingHeadOf]) — a cut's conte
/// itself, or an attach row added to it. The one head is there before this
/// row is, so the row arrives in it rather than with a kind's defaults that
/// the next head edit would have to overwrite. The first row at a seat —
/// and every row that lands on none — is born as it is.
Layer conteBornWearingItsHead(
  Project project, {
  required CutId cutId,
  required Layer layer,
}) {
  final track = _trackHolding(project, cutId);
  final seat = track == null
      ? null
      : _conteSeatBornAt(requireCut(project, cutId), layer);
  if (track == null || seat == null) {
    return layer;
  }
  final head = conteHeadRowAt(
    track.cuts.where((cut) => cut.id != cutId),
    seat,
  );
  return head == null ? layer : layerWearingHeadOf(head, layer);
}

Track? _trackHolding(Project project, CutId cutId) {
  for (final track in project.tracks) {
    if (track.cuts.any((cut) => cut.id == cutId)) {
      return track;
    }
  }
  return null;
}

/// The seat of [cut]'s conte group a row being ADDED lands on: 0 for the
/// conte itself; for an attach row put at the end of its side of the group
/// ([newAttachedRowIndex]), the seat past the farthest one there. Null for
/// a row that lands on none — any other row, and an attach row filed into
/// an organizer folder, which stands where the folder does.
int? _conteSeatBornAt(Cut cut, Layer layer) {
  if (isConteBase(layer)) {
    return 0;
  }
  final base = storyboardLayerForCut(cut);
  if (base == null ||
      layer.attachedToLayerId != base.id ||
      layer.folderId != base.folderId) {
    return null;
  }
  final group = conteGroupOf(cut);
  return layer.attachedPlacement == AttachedPlacement.above
      ? group.first.seat + 1
      : group.last.seat - 1;
}

/// The rows an attach row [added] to [cutId]'s conte is planted as in the
/// OTHER cuts of the track: one riding each cut's own conte, where that
/// conte's group is exactly the one row short — so the new row lands on the
/// same seat in every cut. A cut whose group is shaped otherwise is left as
/// it is: a row added there would land on another seat, and wear another
/// head.
///
/// ⚠️LAZY, and it has to be: a row is planned once the one before it is
/// PLANTED. Planting marks the cuts it put the row in — the pressed cut,
/// and every 겸용 sibling that took it as the same layer — and a marked cut
/// already holds the row.
///
/// The seat is where [added] lands at [index] — the end of its side, or
/// inside the group: an organizer folder's row too (I-73-one-head-Q2,
/// 유저 2026-10-09: 「넷 다 모든 컷에 함께」 — 오거나이저 안 추가), whose
/// copy in a plain group rides the conte without a folder.
Iterable<_PlantedRow> _conteFamilyRowsOf(
  _Planting step,
  CutId cutId,
  Layer added,
  int? index,
) {
  if (!isAttachedLayer(added)) {
    return const [];
  }
  final cut = requireCut(step.project, cutId);
  final seat = conteSeatOf(
    cut.copyWith(layers: insertedAt(cut.layers, added, index)),
    added.id,
  );
  return seat == null
      ? const []
      : _conteSeatRowsOf(
          step,
          cutId,
          head: added,
          seat: seat,
          seats: [for (final entry in conteGroupOf(cut)) entry.seat],
        );
}

/// A row born at [seat] of [cutId]'s conte group as the track's other cuts
/// take it: an empty row wearing [head]'s head at the same seat of each
/// one whose group held the same seats on that side ([seats], the born
/// cut's before it — [conteSeatInsertIndex]). Lazy, as its callers'
/// planting is.
Iterable<_PlantedRow> _conteSeatRowsOf(
  _Planting step,
  CutId cutId, {
  required Layer head,
  required int seat,
  required List<int> seats,
}) sync* {
  final track = _trackHolding(step.project, cutId);
  if (track == null) {
    return;
  }
  for (final cut in track.cuts) {
    final base = step.planted.contains(cut.id)
        ? null
        : storyboardLayerForCut(cut);
    final index = base == null
        ? null
        : conteSeatInsertIndex(cut, seat, seats: seats);
    if (base == null || index == null) {
      continue;
    }
    yield (
      cutId: cut.id,
      layer: layerWearingHeadOf(
        head,
        Layer(
          id: step.ids.nextLayerId(),
          name: head.name,
          frames: const [],
          timeline: const {},
          kind: head.kind,
          onTimesheet: head.onTimesheet,
          attachedToLayerId: base.id,
          attachedPlacement: seat > 0
              ? AttachedPlacement.above
              : AttachedPlacement.below,
          attachedMode: head.attachedMode,
          folderId: base.folderId,
        ),
      ),
      index: index,
    );
  }
}

/// The commands that plant a row MOUNTED on [cutId]'s conte by a drag
/// ([attach], landing in [order]) into the track's other cuts: empty,
/// wearing its head, on the seat it landed on, each with its 겸용
/// siblings' as an added row's are (I-73-one-head-Q2 — 끌어서 장착). None
/// for a drop that mounts nothing on the conte, or more than one row (a
/// folder's members, which stand where the folder does).
List<Command> conteMountBirthCommands({
  required ProjectRepository repository,
  required CutId cutId,
  required List<LayerId> order,
  required LayerAttachDrop attach,
}) {
  final step = _Planting(repository.requireProject());
  final cut = requireCut(step.project, cutId);
  final base = storyboardLayerForCut(cut);
  final mount = attach.mounts.length == 1 ? attach.mounts.single : null;
  if (base == null || mount == null || mount.baseId != base.id) {
    return const [];
  }
  final byId = {for (final layer in cut.layers) layer.id: layer};
  final mounted = byId[mount.layerId];
  if (mounted == null || mounted.kind.groupsLayers) {
    return const [];
  }
  final landed = mounted.copyWith(
    attachedToLayerId: base.id,
    attachedPlacement: mount.placement,
    folderId: base.folderId,
  );
  final seat = conteSeatOf(
    cut.copyWith(
      layers: [
        for (final id in order)
          if (id == mounted.id) landed else ?byId[id],
      ],
    ),
    mounted.id,
  );
  if (seat == null) {
    return const [];
  }
  // The cut it landed in, and its 겸용 siblings, hold it already.
  step.planted
    ..add(cutId)
    ..addAll(linkedCutSiblings(step.project, cutId: cutId));
  return [
    for (final row in _conteSeatRowsOf(
      step,
      cutId,
      head: landed,
      seat: seat,
      seats: [for (final entry in conteGroupOf(cut)) entry.seat],
    ))
      _planted(step, repository, row),
  ];
}

/// [row] as an add command of [step], with the 겸용 siblings that take it
/// as the same layer — and the cuts it reaches marked planted, so the next
/// row of the step passes them by.
AddLayerCommand _planted(
  _Planting step,
  ProjectRepository repository,
  _PlantedRow row,
) {
  final plan = _planAddLayerMirrors(step, cutId: row.cutId, layer: row.layer);
  step.planted
    ..add(row.cutId)
    ..addAll([for (final mirror in plan.mirrors) mirror.cutId]);
  return AddLayerCommand(
    repository: repository,
    cutId: row.cutId,
    layer: row.layer,
    insertionIndex: row.index,
    mirrors: plan.mirrors,
    linkGroupId: plan.linkGroupId,
  );
}

/// The attach rows a conte is BORN with: one for every seat the track's
/// other contes carry a row at, wearing that seat's head and holding
/// nothing — added after [conte] itself, around where it lands
/// ([_seatsBornAround]). Each is mirrored into the cuts the conte is
/// mirrored into, riding the conte's copy there.
List<AddLayerCommand> _conteAttachRowsBornWith(
  _Planting step,
  AddLayerCommand conte,
) {
  final track = _trackHolding(step.project, conte.cutId);
  if (track == null || !isConteBase(conte.layer)) {
    return const [];
  }
  final others = [
    for (final cut in track.cuts)
      if (cut.id != conte.cutId) cut,
  ];
  // Where the conte lands — an index past the stack's end lands at its
  // end ([insertedAt]).
  final stack = requireCut(step.project, conte.cutId).layers.length;
  final asked = conte.insertionIndex ?? stack;
  return [
    for (final (:seat, :index) in _seatsBornAround(
      conteSeatsOf(others),
      baseIndex: asked < 0 ? 0 : (asked > stack ? stack : asked),
    ))
      _conteAttachRowBorn(step, conte, conteHeadRowAt(others, seat)!, index),
  ];
}

/// Each attach seat of [seats] with the index its row is added at, in the
/// order they are added, around a conte standing at [baseIndex]: the rows
/// below it first, nearest first — each goes in under the conte, which it
/// pushes up a place — then the rows above it, each over the last.
List<({int seat, int index})> _seatsBornAround(
  List<int> seats, {
  required int baseIndex,
}) {
  final below = [
    for (final seat in seats)
      if (seat < 0) seat,
  ]..sort((a, b) => b.compareTo(a));
  final above = [
    for (final seat in seats)
      if (seat > 0) seat,
  ]..sort();
  return [
    for (final seat in below) (seat: seat, index: baseIndex),
    for (final (place, seat) in above.indexed)
      (seat: seat, index: baseIndex + below.length + 1 + place),
  ];
}

/// One attach row [conte] is born with: riding it at [index], wearing
/// [head] and holding nothing, and mirrored into each cut the conte is
/// mirrored into as the same layer.
AddLayerCommand _conteAttachRowBorn(
  _Planting step,
  AddLayerCommand conte,
  Layer head,
  int index,
) {
  final mirrors = [
    for (final mirror in conte.mirrors)
      AddLayerMirror(
        cutId: mirror.cutId,
        layerId: step.ids.nextLayerId(),
        folderId: mirror.folderId,
        attachedToLayerId: mirror.layerId,
      ),
  ];
  return AddLayerCommand(
    repository: conte.repository,
    cutId: conte.cutId,
    layer: layerWearingHeadOf(
      head,
      Layer(
        id: step.ids.nextLayerId(),
        name: head.name,
        frames: const [],
        timeline: const {},
        kind: head.kind,
        onTimesheet: false,
        attachedToLayerId: conte.layer.id,
        attachedPlacement: head.attachedPlacement,
        attachedMode: head.attachedMode,
        folderId: conte.layer.folderId,
      ),
    ),
    insertionIndex: index,
    mirrors: mirrors,
    linkGroupId: mirrors.isEmpty ? null : step.ids.nextLinkGroupId(),
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
  _ProjectIdSnapshot({required this.layerIds, required this.linkGroupIds});

  factory _ProjectIdSnapshot.fromProject(Project project) {
    final snapshot = _ProjectIdSnapshot(
      layerIds: <String>{},
      linkGroupIds: {for (final group in project.linkRegistry.groups) group.id},
    );
    for (final track in project.tracks) {
      for (final cut in track.cuts) {
        snapshot.includeCut(cut);
      }
    }
    return snapshot;
  }

  final Set<String> layerIds;

  /// The link groups' ids — the registry's, and the ones a step has planned
  /// since ([nextLinkGroupId]).
  final Set<String> linkGroupIds;

  /// A fresh layer id, kept so the next one asked for is another.
  LayerId nextLayerId() {
    final id = LayerId(_firstAvailableId(prefix: 'layer', usedIds: layerIds));
    layerIds.add(id.value);
    return id;
  }

  /// A fresh link-group id, kept likewise: a step that plants several rows
  /// plans a group for each.
  String nextLinkGroupId() {
    final id = _firstAvailableId(prefix: 'link', usedIds: linkGroupIds);
    linkGroupIds.add(id);
    return id;
  }

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

import '../../models/attached_layer_resolve.dart';
import '../../models/conte_group.dart';
import '../../models/conte/conte_ink_keys.dart'
    show conteHandwritingOfACopy, conteInkRowLayerId;
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/layer_folder.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_effect.dart' show effectsWithRowsRenamed;
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/project.dart';
import '../clipboard/layer_copy_payload.dart';
import '../command.dart';
import '../editing/cut_duplicate_helpers.dart' show remapTimelineExposure;
import '../editing/run_id_mint.dart' show mintCutId, mintFrameId;
import '../project_lookup.dart' show requireCut;
import '../project_repository.dart';
import 'add_layer_command.dart';
import 'convert_to_linked_cut_plan.dart';
import 'link_duplicate_layer_command.dart' show LinkDuplicateUse;
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
    clipsToBelow: payload.clipsToBelow,
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
/// minted against what [ids] already holds — one [ids] for every cut a
/// step mints in, so no two of its copies or groups share an id.
///
/// ⛔THE TWO MAPS MUST BE KEYED BY THE SAME SOURCES. The command reads one
/// to build the copy and the other to register the link, so a planner that
/// walked its sources twice — filtering each time — could register a group
/// for a layer it never copied the moment the two filters drifted apart.
/// Both link planners did exactly that walk.
({Map<LayerId, LayerId> layerIdMap, Map<LayerId, String> newGroupIdBySource})
_mintLinkIds(
  _ProjectIdSnapshot ids,
  Iterable<Layer> sources,
) {
  final layerIdMap = <LayerId, LayerId>{};
  final newGroupIdBySource = <LayerId, String>{};
  for (final source in sources) {
    layerIdMap[source.id] = ids.nextLayerId();
    newGroupIdBySource[source.id] = ids.nextLinkGroupId();
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

  final minted = _mintLinkIds(ids, [
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

/// Whether each 겸용 copy of [layer] is born with a cel of its own: a row of
/// a covering kind always is ([_bornWithAFreshPanel]), and an animation row
/// Add Layer makes ([bornWithACel]) is, with its first cel — 🗣️I-138 (유저
/// 2026-10-28): 「애니메이션 레이어 생성시 … 프레임 1개 생성되는걸로」, and
/// an unnamed cel is no other cut's (F-98 above). A row PUT in the cut — a
/// paste, an import — brings its pictures, and its copies take its lane.
bool _copiesBornWithACelOfTheirOwn(
  Layer layer, {
  required bool bornWithACel,
}) =>
    _bornWithAFreshPanel(layer) || (bornWithACel && !isAttachedLayer(layer));

class ConvertToLinkedCutCommandInputPlan {
  const ConvertToLinkedCutCommandInputPlan({
    required this.unionLayerIdMap,
    required this.newGroupIdBySource,
    required this.coveringFrameIdBySource,
    this.siblingUnionLayerIdMap = const {},
    this.siblingCoveringFrameIds = const {},
  });

  /// (owning cut, source layer) → new copy id in the OTHER cut.
  final Map<(CutId, LayerId), LayerId> unionLayerIdMap;

  /// (sibling, one-side-only source layer) → its copy's id in that 겸용
  /// sibling: the origin's siblings take the target-only rows the origin
  /// takes, the target's the origin-only rows the target takes (F-398).
  final Map<(CutId, LayerId), LayerId> siblingUnionLayerIdMap;

  /// The fresh panel each sibling copy of a row born with a frame is born
  /// with, keyed like [siblingUnionLayerIdMap].
  final Map<(CutId, LayerId), FrameId> siblingCoveringFrameIds;

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
  final union = _PlannedCopies(ids);
  final siblingCopies = _PlannedCopies(ids);
  final newGroupIdBySource = <LayerId, String>{};

  for (final pair in plan.layerPairs) {
    newGroupIdBySource[pair.originLayerId] = ids.nextLinkGroupId();
  }
  for (final (owner, onlyIds) in [
    (originCut, plan.originOnlyLayerIds),
    (targetCut, plan.targetOnlyLayerIds),
  ]) {
    for (final layerId in onlyIds) {
      union.plan(owner, layerId, key: (owner.id, layerId));
      newGroupIdBySource[layerId] = ids.nextLinkGroupId();
    }
  }
  // 🗣️F-398 (유저 2026-10-18): 「관련 링크안되는것들 다른것도 조사 법 통일」
  // — a row the origin takes in from the target is an added row there, and
  // the origin's 겸용 siblings take it too; so do the target's, of the rows
  // the target takes in (⑤). ↩️Only the two cuts matched.
  for (final (cut, other, onlyIds) in [
    (originCut, targetCut, plan.targetOnlyLayerIds),
    (targetCut, originCut, plan.originOnlyLayerIds),
  ]) {
    for (final sibling in linkedCutSiblings(project, cutId: cut.id)) {
      if (sibling == other.id) {
        continue;
      }
      for (final layerId in onlyIds) {
        siblingCopies.plan(other, layerId, key: (sibling, layerId));
      }
    }
  }

  return ConvertToLinkedCutCommandInputPlan(
    unionLayerIdMap: union.ids,
    newGroupIdBySource: newGroupIdBySource,
    coveringFrameIdBySource: union.panels,
    siblingUnionLayerIdMap: siblingCopies.ids,
    siblingCoveringFrameIds: siblingCopies.panels,
  );
}

/// The copies a 겸용 변경 plans under one kind of key: each copy's id,
/// minted from the one snapshot every copy of the step mints from, and the
/// fresh panel a row born with a frame is born with (F-99).
class _PlannedCopies {
  _PlannedCopies(this._snapshot);

  final _ProjectIdSnapshot _snapshot;
  final ids = <(CutId, LayerId), LayerId>{};
  final panels = <(CutId, LayerId), FrameId>{};

  /// A copy of [owner]'s row [layerId], under [key].
  void plan(Cut owner, LayerId layerId, {required (CutId, LayerId) key}) {
    final copyId = ids[key] = _snapshot.nextLayerId();
    if (_bornWithAFreshPanel(owner.layers.byId(layerId)!)) {
      panels[key] = mintFrameId(copyId);
    }
  }
}

class LinkDuplicateLayerCommandInputPlan {
  const LinkDuplicateLayerCommandInputPlan({
    required this.layerIdMap,
    required this.newGroupIdBySource,
    this.siblings = const [],
  });

  /// Source member id → its copy's id, over the whole attach group.
  final Map<LayerId, LayerId> layerIdMap;

  /// Planned registry group id per source member (used only for members
  /// that are not in a link group yet).
  final Map<LayerId, String> newGroupIdBySource;

  /// Each 겸용 sibling holding a row of the source: that row's group, its
  /// copies' ids planned the same way (F-398).
  final List<LinkDuplicateUse> siblings;
}

/// Plans a 링크 복제 (L2): one copy id per member of [sourceLayerId]'s
/// attach group, plus fresh registry group ids. FrameIds are NOT mapped —
/// keeping them identical IS the link.
///
/// 🗣️F-398 (유저 2026-10-18): 「관련 링크안되는것들 다른것도 조사 법 통일」 —
/// a link paste in a 겸용 cut is an added row there too: each sibling
/// holding a row of the source copies ITS row's group, planned the same
/// way. ↩️Only the one cut got the copies.
LinkDuplicateLayerCommandInputPlan planLinkDuplicateLayerCommandInput({
  required Project project,
  required Cut cut,
  required LayerId sourceLayerId,
}) {
  final ids = _ProjectIdSnapshot.fromProject(project);
  final own = _linkDuplicateShare(ids, cut, sourceLayerId);
  return LinkDuplicateLayerCommandInputPlan(
    layerIdMap: own.layerIdMap,
    newGroupIdBySource: own.newGroupIdBySource,
    siblings: [
      for (final sibling in linkedCutSiblings(project, cutId: cut.id))
        if (linkCounterpartIn(
              project,
              cutId: cut.id,
              layerId: sourceLayerId,
              targetCutId: sibling,
            )
            case final there?)
          _linkDuplicateShare(
            ids,
            requireCut(project, sibling),
            there,
          ),
    ],
  );
}

/// [cut]'s share of a 링크 복제 of its row [sourceLayerId]: that row's
/// attach group, each member given a copy id and a group id from [ids].
LinkDuplicateUse _linkDuplicateShare(
  _ProjectIdSnapshot ids,
  Cut cut,
  LayerId sourceLayerId,
) {
  final source = cut.layers.firstWhere((layer) => layer.id == sourceLayerId);
  final minted = _mintLinkIds(
    ids,
    attachedGroupSlice(attachBaseIdOf(source), cut.layers),
  );
  return (
    cutId: cut.id,
    sourceLayerId: sourceLayerId,
    layerIdMap: minted.layerIdMap,
    newGroupIdBySource: minted.newGroupIdBySource,
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
/// cut, its anchors resolved to that cut's own rows, the cel of its own a
/// row born with a frame is born with there
/// ([_copiesBornWithACelOfTheirOwn]), plus the link group they join.
///
/// Kinds that do not link into a 겸용 cut plan no mirrors — the per-use SE
/// and direction fixtures already exist in every cut
/// ([LayerKind.linksIntoLinkedCut] is the one predicate for that question).
/// A SINGLETON kind — the conte row, the camera row — mirrors only into a
/// sibling that has none: a cut holds one ([LayerKind.isSingletonPerCut]),
/// so a sibling with its own keeps it and the new row stays this cut's.
///
/// A sibling whose counterpart for an anchor is missing is DROPPED rather
/// than guessed at (the mirrors' rule): a row inheriting a folder that
/// only exists in the origin cut would break the sibling's folder
/// invariant, and an attach row without its base is not a row at all.
AddLayerCommandInputPlan planAddLayerCommandInput({
  required Project project,
  required CutId cutId,
  required Layer layer,
  bool bornWithACel = false,
}) => planAddLayersCommandInput(
  project: project,
  cutId: cutId,
  layers: [layer],
  bornWithACel: bornWithACel,
).single;

/// [layers] added to [cutId] in ONE step, each planned as
/// [planAddLayerCommandInput] plans a row — the plans in [layers]' order.
///
/// 🗣️F-398 (유저 2026-10-18): 「배치 통해 만들어진 레이어(이미지,애니메이션?)가
/// 겸용컷에서 링크가 안됨. 관련 링크안되는것들 다른것도 조사 법 통일」 — an
/// import put its rows in the one cut. An import lands a BATCH, and a PSD's
/// folder rows come with the rows they hold: an anchor can be a row of the
/// batch, whose copy in a sibling is that row's own copy there — and a copy
/// whose anchor is dropped is dropped with it.
///
/// ⚠️The rows' own ids are taken before any copy's: a pasted row's is the
/// project's first free `layer-N`, the very id the first copy would get.
///
/// [bornWithACel]: [layers] are made here, each with its first cel — Add
/// Layer — rather than put in the cut ([_copiesBornWithACelOfTheirOwn]).
List<AddLayerCommandInputPlan> planAddLayersCommandInput({
  required Project project,
  required CutId cutId,
  required List<Layer> layers,
  bool bornWithACel = false,
}) {
  final siblings = linkedCutSiblings(project, cutId: cutId);
  if (siblings.isEmpty) {
    return List.filled(layers.length, AddLayerCommandInputPlan.none);
  }
  final batch = {for (final layer in layers) layer.id};
  LayerId? outside(LayerId anchor, CutId sibling) => linkCounterpartIn(
    project,
    cutId: cutId,
    layerId: anchor,
    targetCutId: sibling,
  );
  final copied = _copiesAnchored(project, layers, siblings, outside);

  final ids = _ProjectIdSnapshot.fromProject(project)
    ..layerIds.addAll([for (final id in batch) id.value]);
  final copyIds = {for (final copy in copied) copy: ids.nextLayerId()};
  LayerId? copyOf(LayerId? anchor, CutId sibling) => anchor == null
      ? null
      : batch.contains(anchor)
      ? copyIds[(anchor, sibling)]
      : outside(anchor, sibling);
  AddLayerCommandInputPlan planOf(Layer layer) {
    final mirrors = [
      for (final sibling in siblings)
        if (copyIds[(layer.id, sibling)] case final copyId?)
          AddLayerMirror(
            cutId: sibling,
            layerId: copyId,
            folderId: copyOf(layer.folderId, sibling),
            attachedToLayerId: copyOf(layer.attachedToLayerId, sibling),
            effects: effectsWithRowsRenamed(
              layer.effects,
              (row) => copyOf(row, sibling),
            ),
            bornCelId:
                _copiesBornWithACelOfTheirOwn(
                  layer,
                  bornWithACel: bornWithACel,
                )
                ? mintFrameId(copyId)
                : null,
          ),
    ];
    return mirrors.isEmpty
        ? AddLayerCommandInputPlan.none
        : AddLayerCommandInputPlan(
            mirrors: mirrors,
            linkGroupId: ids.nextLinkGroupId(),
          );
  }

  return [for (final layer in layers) planOf(layer)];
}

/// The copies [layers] take in [siblings]: each row of a kind that links
/// into a 겸용 cut, in each sibling that keeps no singleton of its own —
/// less every copy whose folder or attach base reaches no row there. An
/// anchor in the batch reaches through its own copy, so a copy dropped
/// drops the ones that hang on it; one outside reaches through [outside].
Set<(LayerId, CutId)> _copiesAnchored(
  Project project,
  List<Layer> layers,
  List<CutId> siblings,
  LayerId? Function(LayerId anchor, CutId sibling) outside,
) {
  final batch = {for (final layer in layers) layer.id};
  final copied = <(LayerId, CutId)>{
    for (final layer in layers)
      if (layer.kind.linksIntoLinkedCut)
        for (final sibling in siblings)
          if (!_keepsItsOwnSingleton(project, sibling, layer))
            (layer.id, sibling),
  };
  bool reaches(LayerId? anchor, CutId sibling) =>
      anchor == null ||
      (batch.contains(anchor)
          ? copied.contains((anchor, sibling))
          : outside(anchor, sibling) != null);
  for (var dropped = true; dropped;) {
    dropped = false;
    for (final layer in layers) {
      for (final sibling in siblings) {
        final anchored =
            reaches(layer.folderId, sibling) &&
            reaches(layer.attachedToLayerId, sibling);
        if (!anchored && copied.remove((layer.id, sibling))) {
          dropped = true;
        }
      }
    }
  }
  return copied;
}

/// Whether [sibling] keeps its own row of [layer]'s SINGLETON kind, and so
/// takes no copy — the ONE row of its kind, that is: a row riding another
/// is not it ([holdsSingletonOfKind]), so the conte row's attach rows
/// mirror like any drawing row's.
bool _keepsItsOwnSingleton(Project project, CutId sibling, Layer layer) =>
    layer.kind.isSingletonPerCut &&
    !isAttachedLayer(layer) &&
    holdsSingletonOfKind(requireCut(project, sibling).layers, layer.kind);

/// [layer] added to [cutId] at [insertionIndex], and to the 겸용 siblings
/// [planAddLayerCommandInput] plans against the project as it stands.
///
/// ONE recipe for every way a row is added to a cut: the layer panel's Add
/// Layer, on the cut the canvas stands on, the conte row a picture's first
/// stroke makes, on the picture's cut, and a pasted or duplicated row. An
/// import's rows take the same plans, a batch at a time
/// ([planAddLayersCommandInput], `ImportMediaCommand`).
///
/// ↩️A pasted row went into its one cut (`PasteLayerCommand`), and so did
/// an import's — no copy in a 겸용 sibling (F-398).
///
/// ↩️A row added to a track's conte was planted in every other cut's here,
/// wearing the head of its seat, and a conte born into the track was born
/// carrying the track's attach rows (I-73). The track's conte structure
/// lays both now (F-343, `trackWithItsConteLaid`): this adds the one row.
Command plannedAddLayerCommand({
  required ProjectRepository repository,
  required CutId cutId,
  required Layer layer,
  int? insertionIndex,
  bool bornWithACel = false,
}) {
  final plan = planAddLayerCommandInput(
    project: repository.requireProject(),
    cutId: cutId,
    layer: layer,
    bornWithACel: bornWithACel,
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

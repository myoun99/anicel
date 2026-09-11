import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/project.dart';
import '../../models/transform_track.dart';
import '../project_lookup.dart';

/// The (cut, layer) addresses a MIRRORED property edit must apply to:
/// every member of [layerId]'s link group, or just itself when unlinked.
///
/// "레인만 각자, 나머지는 하나" — commands touching shared layer
/// properties (name, mark, kind, eye, static opacity, structure, and an
/// FX chain's SHAPE) fan out through this inside ONE command execution,
/// which is what makes the mirror drift-free and single-undo. Only the
/// LANE VALUES stay per-use: timeline entries, effect parameter values
/// and their keyframe tracks, transform tracks. Sharing a lane's numbers
/// is the named-union link's job, not the mirror's.
List<({CutId cutId, LayerId layerId})> linkMirrorTargets(
  Project project, {
  required CutId cutId,
  required LayerId layerId,
}) {
  final group = project.linkRegistry.groupOf(cutId: cutId, layerId: layerId);
  if (group == null) {
    return [(cutId: cutId, layerId: layerId)];
  }
  return [
    for (final member in group.members)
      (cutId: member.cutId, layerId: member.layerId),
  ];
}

/// The transform track ([cutId], [layerId]) keys: the row's own, except the
/// CAMERA row's — the row is its cut's transform header (F-17), and its
/// lanes live on [Cut.camera].
TransformTrack transformTrackOfRow(
  Project project, {
  required CutId cutId,
  required LayerId layerId,
}) {
  final layer = requireLayerAnywhere(project, layerId);
  return layer.kind == LayerKind.camera
      ? requireCut(project, cutId).camera.track
      : layer.transformTrack;
}

/// Every row a write of [after] over ([cutId], [layerId])'s transform track
/// reaches, with the track each one ends up holding: the row itself, with
/// every NAMED key the write moved set on its other keys of that name, and
/// then each 겸용 sibling holding those names.
///
/// "Same name, same value": a transform's lanes are otherwise each use's
/// own ("레인만 각자"), so a named key is the ONLY way a transform number
/// crosses cuts. One law for a layer's transform and a cut's camera (유저
/// 2026-09-11: 「트랜스폼이나 카메라나 똑같으니까 법 싹 하나로 통일해줘」) —
/// which is why every track here is read through [transformTrackOfRow].
List<({CutId cutId, LayerId layerId, TransformTrack track})>
namedTransformWrites(
  Project project, {
  required CutId cutId,
  required LayerId layerId,
  required TransformTrack after,
}) {
  final changes = transformNamedKeyChanges(
    transformTrackOfRow(project, cutId: cutId, layerId: layerId),
    after,
  );
  final writes = [
    (
      cutId: cutId,
      layerId: layerId,
      track: transformTrackWithNamedKeys(after, changes),
    ),
  ];
  if (changes.isEmpty) {
    return writes;
  }
  for (final target in linkMirrorTargets(
    project,
    cutId: cutId,
    layerId: layerId,
  )) {
    if (target.cutId == cutId && target.layerId == layerId) {
      continue;
    }
    final current = transformTrackOfRow(
      project,
      cutId: target.cutId,
      layerId: target.layerId,
    );
    final next = transformTrackWithNamedKeys(current, changes);
    if (next != current) {
      writes.add((cutId: target.cutId, layerId: target.layerId, track: next));
    }
  }
  return writes;
}

/// The 겸용 (linked) sibling cuts of [cutId] — where NEW structure has to
/// appear too, because layer existence is shared structure.
///
/// A cut qualifies only when EVERY linked layer of [cutId] has a
/// counterpart in it (folder_mirror's rule: a partial match means the
/// structure diverged, so we stand down rather than guess). A cut whose
/// layers are all unlinked has no siblings at all.
List<CutId> linkedCutSiblings(Project project, {required CutId cutId}) {
  final registry = project.linkRegistry;
  final cut = requireCut(project, cutId);
  var linkedLayerCount = 0;
  final counterpartsByCut = <CutId, int>{};
  for (final layer in cut.layers) {
    final group = registry.groupOf(cutId: cutId, layerId: layer.id);
    if (group == null) {
      continue;
    }
    linkedLayerCount += 1;
    // Per LAYER, per cut: "has a counterpart there" is a boolean — a cut
    // holding TWO members of one group (link-duplicate inside a linked
    // cut) used to count 2 against this layer's 1 and fail the
    // full-match test below, silently excluding a genuine 겸용 sibling.
    // A resize then broke the size lockstep, and the sibling's first
    // stroke destroyed the shared cel bank (adversarial review).
    final cutsWithCounterpart = <CutId>{
      for (final member in group.members)
        if (member.cutId != cutId) member.cutId,
    };
    for (final target in cutsWithCounterpart) {
      counterpartsByCut[target] = (counterpartsByCut[target] ?? 0) + 1;
    }
  }
  if (linkedLayerCount == 0) {
    return const [];
  }
  return [
    for (final entry in counterpartsByCut.entries)
      if (entry.value == linkedLayerCount) entry.key,
  ];
}

/// [layerId]'s counterpart inside [targetCutId] — the member of its link
/// group that lives there, or null when the row does not reach that cut.
///
/// A new row's ANCHORS (its folder, the base it attaches to) are ids from
/// the origin cut; a mirrored copy has to point at the sibling's own rows
/// instead, and a missing counterpart means the structure diverged there.
LayerId? linkCounterpartIn(
  Project project, {
  required CutId cutId,
  required LayerId layerId,
  required CutId targetCutId,
}) {
  final group = project.linkRegistry.groupOf(cutId: cutId, layerId: layerId);
  if (group == null) {
    return null;
  }
  for (final member in group.members) {
    if (member.cutId == targetCutId) {
      return member.layerId;
    }
  }
  return null;
}

/// [sibling]'s own order after the same MOVE that produced [sourceOrder] —
/// or null when the sibling shares none of the moved rows.
///
/// Stack ORDER is shared structure, like existence and kind, so a row moved
/// in one use site moves in all of them. It cannot be copied verbatim: a
/// sibling holds rows the source does not (its own SE/CAM fixtures,
/// unlinked rows), so the move is restated the way [mirroredInsertionIndex]
/// states an insertion — **directly above the nearest LINKED neighbour
/// below the landing**, skipping rows the sibling does not share rather
/// than counting them.
List<LayerId>? mirroredOrderAfterMove(
  Project project, {
  required CutId cutId,
  required List<LayerId> sourceOrder,
  required Set<LayerId> movedIds,
  required Cut sibling,
}) {
  LayerId? counterpart(LayerId layerId) => linkCounterpartIn(
    project,
    cutId: cutId,
    layerId: layerId,
    targetCutId: sibling.id,
  );

  var landing = -1;
  final carried = <LayerId>[];
  for (var index = 0; index < sourceOrder.length; index += 1) {
    if (!movedIds.contains(sourceOrder[index])) {
      continue;
    }
    if (landing < 0) {
      landing = index;
    }
    final mirror = counterpart(sourceOrder[index]);
    if (mirror != null) {
      carried.add(mirror);
    }
  }
  if (carried.isEmpty) {
    return null;
  }
  final carriedSet = carried.toSet();
  final rest = [
    for (final layer in sibling.layers)
      if (!carriedSet.contains(layer.id)) layer.id,
  ];

  var insertAt = 0;
  for (var index = landing - 1; index >= 0; index -= 1) {
    final id = sourceOrder[index];
    if (movedIds.contains(id)) {
      continue;
    }
    final mirror = counterpart(id);
    final at = mirror == null ? -1 : rest.indexOf(mirror);
    if (at >= 0) {
      insertAt = at + 1;
      break;
    }
  }
  return [...rest.sublist(0, insertAt), ...carried, ...rest.sublist(insertAt)];
}

/// Where a layer inserted at [sourceIndex] of [source] must sit in
/// [sibling]'s own list.
///
/// The layer list runs bottom-up (inserting ABOVE a row is `index + 1`),
/// so this walks DOWN from the insertion point for the nearest LINKED
/// neighbour and lands just above that neighbour's counterpart. Rows the
/// sibling does not share (its own SE/CAM fixtures) are skipped rather
/// than counted, which is what keeps the two lists from drifting apart
/// when their fixture rows differ. No linked neighbour below the
/// insertion point means the bottom of the sibling's list.
int mirroredInsertionIndex(
  Project project, {
  required Cut source,
  required int sourceIndex,
  required Cut sibling,
}) {
  final registry = project.linkRegistry;
  for (var index = sourceIndex - 1; index >= 0; index -= 1) {
    if (index >= source.layers.length) {
      continue;
    }
    final group = registry.groupOf(
      cutId: source.id,
      layerId: source.layers[index].id,
    );
    if (group == null) {
      continue;
    }
    for (final member in group.members) {
      if (member.cutId != sibling.id) {
        continue;
      }
      final at = sibling.layers.indexWhere(
        (layer) => layer.id == member.layerId,
      );
      if (at >= 0) {
        return at + 1;
      }
    }
  }
  return 0;
}

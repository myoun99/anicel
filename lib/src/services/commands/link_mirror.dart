import '../../models/attached_layer_mount.dart' show LayerAttachDrop;
import '../../models/attached_layer_resolve.dart'
    show attachedGroupEndIndex, attachedGroupStartIndex;
import '../../models/attached_placement.dart';
import '../../models/conte_group.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/layer.dart' show Layer, LayerStackQueries, isAttachedLayer;
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/project.dart';
import '../../models/transform_track.dart';
import '../project_lookup.dart';

/// The (cut, layer) addresses a MIRRORED property edit must apply to:
/// every member of [layerId]'s link group, or just itself when unlinked.
///
/// Commands touching shared layer properties (name, mark, kind, blend,
/// static opacity, structure, the transform switch, and an FX chain's
/// SHAPE) fan out through this inside ONE command execution, which is what
/// makes the mirror drift-free and single-undo. Per-use, and never through
/// here: the LANE VALUES (timeline entries, effect parameter values and
/// their keyframe tracks, transform tracks) and whether a use SHOWS the
/// layer (the eye — `UpdateLayerDisplayCommand`). Sharing a lane's numbers
/// is the named-union link's job, not the mirror's.
///
/// ↩️This used to read 「레인만 각자, 나머지는 하나」 and list the eye and
/// static opacity as shared. T9 (유저 확정 2026-08-13, `1d110b574` 「A link
/// shares the drawing, not the eye」) made the three display values each
/// use's own, and retired the sentence. ↩️Of the three, the BLEND and the
/// STATIC OPACITY came back (유저 2026-10-04, F-278: 「겸용컷 블렌드모드도
/// 공유하도록 하자 … 불투명도도 공유하도록 … 보이기만 독립적으로 하고」) —
/// the eye alone is each use's own.
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

/// The ROWS of [linkMirrorTargets]: every use of the row, by the id the
/// rail keeps its view state by — the twirls and the folds, which a linked
/// row wears as one (F-302).
List<LayerId> linkMirrorRows(
  Project project, {
  required CutId cutId,
  required LayerId layerId,
}) => [
  for (final target in linkMirrorTargets(
    project,
    cutId: cutId,
    layerId: layerId,
  ))
    target.layerId,
];

/// 🚨★★★THE CONTE ROWS OF A TRACK WEAR ONE HEAD (I-73).
///
/// 유저 2026-10-08: 「콘티레이어 권고한대로 머리만 한벌 ok. 맘에드는
/// 생각이야. 겸용컷이랑 같은 느낌이네」 · 「6. 이거만 눈이랑 불투명도조차
/// 링크하도록. 그거마저 머리로서 하나로되도록 통일 프레임 이름으로
/// 링크하는거 자체는 컷 기준으로 내부에서만 이름같으면, 겸용컷에서만
/// 이름같으면 이런식은 지키는게 나을듯」. The storyboard draws a track's
/// conte as ONE set of rows over all its cuts, so each of those rows has one
/// head: its name, its label, its blend, its static opacity, its eye, the
/// shape of its fx. What stays each cut's own is what the row HOLDS — its
/// panels, its pictures, the values and keys of its fx.
///
/// Every (cut, row) at [layerId]'s SEAT in the conte groups of its track
/// ([conteSeatOf]) — the row itself first. Empty when it sits in none.
///
/// The row's cut is FOUND, not handed in: a rail that draws one head for
/// every cut presses it under whichever cut is active, and a layer id is
/// its own address — unique across the project.
///
/// ⛔NOT a link group, and it must not be made one: a link group shares the
/// cel bank and the named keys' values ([linkMirrorTargets] answers for
/// those too), and two cuts' conte rows in one group would turn every pair
/// of same-named panels into one picture. The head is a relation of its own
/// — computed from where a row sits, stored nowhere.
List<({CutId cutId, LayerId layerId})> conteHeadTargets(
  Project project,
  LayerId layerId,
) => _rowsAtOnePlace(
  project,
  layerId,
  placeOf: (cut) => conteSeatOf(cut, layerId),
  rowAt: conteRowAtSeat,
);

/// Every (cut, row) of the track that holds [layerId] — the row itself
/// first — at the place [placeOf] finds it at in its cut: the rows ONE head
/// is worn by across a track ([conteHeadTargets], [cameraHeadTargets]).
/// Empty where no cut holds it at such a place.
List<({CutId cutId, LayerId layerId})> _rowsAtOnePlace<P extends Object>(
  Project project,
  LayerId layerId, {
  required P? Function(Cut cut) placeOf,
  required Layer? Function(Cut cut, P place) rowAt,
}) {
  for (final track in project.tracks) {
    for (final cut in track.cuts) {
      final place = placeOf(cut);
      if (place == null) {
        continue;
      }
      return [
        (cutId: cut.id, layerId: layerId),
        for (final other in track.cuts)
          if (other.id != cut.id)
            if (rowAt(other, place) case final row?)
              (cutId: other.id, layerId: row.id),
      ];
    }
  }
  return const [];
}

/// 🚨A TRACK'S CAMERAS WEAR ONE HEAD TOO — ITS NAME AND ITS FX SWITCH (I-73
/// ④).
///
/// 유저 2026-10-09: 「그럼 카메라행도 글로벌? 콘티행처럼 머리 같도록
/// 할까하는데」, and of the head that drew (I-73-camera-row-Q1): 「좋은데
/// 색라벨은 컷마다 있는게 좋을거같은데」. The storyboard draws a track's
/// cameras as ONE row, so the row's name and its fx switch — the camera
/// work on or off — are one for every cut of the track. ⛔The colour label
/// stays each cut's own: the row draws each cut's keys and line in it. The
/// eye and the opacity are the camera VIEW's, no layer's at all.
///
/// Every (cut, camera row) of the track [layerId]'s camera stands on — the
/// row itself first. Empty for any other row.
///
/// ⛔Not a link group either: what a camera HOLDS — its keys, their names
/// and values — stays each cut's own, as a conte row's panels do.
List<({CutId cutId, LayerId layerId})> cameraHeadTargets(
  Project project,
  LayerId layerId,
) => _rowsAtOnePlace(
  project,
  layerId,
  // A cut has one camera row: its place is the row itself.
  placeOf: (cut) => cut.layers.cameraLayer?.id == layerId ? () : null,
  rowAt: (cut, _) => cut.layers.cameraLayer,
);

/// One cut's conte group as a re-ordering of it leaves it: the stack's new
/// [order], and the one rider whose side of the conte flipped.
typedef ConteGroupReorder = ({
  CutId cutId,
  List<LayerId> order,
  ({LayerId layerId, AttachedPlacement placement})? sideChange,
});

/// A placement in [cutId] that RE-ORDERS its conte group's rows, as every
/// other cut of the track takes it: the row at each seat moved to the seat
/// the row at that seat in [cutId] moved to.
///
/// 🗣️I-73-one-head-Q2 (유저 2026-10-09 → `all`): 「넷 다 모든 컷에 함께」 —
/// of the attach structure the track's cuts wear as one head, 순서 바꾸기
/// is one of the four. Only a pure re-ordering carries ([attach] mounts or
/// lets go of nothing), and only into a cut whose group holds the same
/// seats.
///
/// ⛔A group with an organizer folder in it — in [cutId] or in the other
/// cut — stands down, as `folder_mirror` does where structures diverged:
/// a folder files rows, so its members' seats and the folder's place are
/// two answers a seat alone cannot carry. 겸용 siblings are left to the
/// link mirror, which moves them as the same rows.
List<ConteGroupReorder> conteGroupReorders(
  Project project, {
  required CutId cutId,
  required List<LayerId> order,
  required LayerAttachDrop attach,
}) {
  if (attach.mounts.isNotEmpty || attach.detachIds.isNotEmpty) {
    return const [];
  }
  final cut = requireCut(project, cutId);
  final before = plainConteGroupOf(cut);
  if (before == null || before.length < 2) {
    return const [];
  }
  final byId = {for (final layer in cut.layers) layer.id: layer};
  final side = attach.sideChange;
  final after = conteGroupOf(
    cut.copyWith(
      layers: [
        for (final id in order)
          if (byId[id] case final layer?)
            if (side != null && side.layerId == id)
              layer.copyWith(attachedPlacement: side.placement)
            else
              layer,
      ],
    ),
  );
  final seatOf = {for (final entry in after) entry.row.id: entry.seat};
  final moved = {
    for (final entry in before) entry.seat: ?seatOf[entry.row.id],
  };
  if (moved.length != before.length ||
      moved.entries.every((entry) => entry.key == entry.value)) {
    return const [];
  }
  final seats = [for (final entry in before) entry.seat];
  final siblings = linkedCutSiblings(project, cutId: cutId).toSet();
  final track = project.tracks.firstWhere(
    (track) => track.cuts.any((other) => other.id == cutId),
  );
  return [
    for (final other in track.cuts)
      if (other.id != cutId && !siblings.contains(other.id))
        ?_reorderedLike(other, moved, seats),
  ];
}

/// [cut]'s conte group re-ordered by [moved] — each seat to its new one —
/// when it holds exactly [seats] and no organizer folder; else null.
ConteGroupReorder? _reorderedLike(
  Cut cut,
  Map<int, int> moved,
  List<int> seats,
) {
  final group = plainConteGroupOf(cut);
  if (group == null ||
      group.length != seats.length ||
      !group.indexed.every((entry) => entry.$2.seat == seats[entry.$1])) {
    return null;
  }
  final flipped = [
    for (final entry in group)
      if (entry.seat.sign * moved[entry.seat]!.sign < 0) entry,
  ];
  if (flipped.length > 1) {
    return null;
  }
  // The group's rows in their new stack order: lowest seat first.
  final regrouped = [...group]
    ..sort((a, b) => moved[a.seat]!.compareTo(moved[b.seat]!));
  final base = group.firstWhere((entry) => entry.seat == 0).row;
  final start = attachedGroupStartIndex(base.id, cut.layers);
  final end = attachedGroupEndIndex(base.id, cut.layers);
  final turned = flipped.firstOrNull;
  return (
    cutId: cut.id,
    order: [
      for (final layer in cut.layers.sublist(0, start)) layer.id,
      for (final entry in regrouped) entry.row.id,
      for (final layer in cut.layers.sublist(end)) layer.id,
    ],
    sideChange: turned == null
        ? null
        : (
            layerId: turned.row.id,
            placement: moved[turned.seat]! > 0
                ? AttachedPlacement.above
                : AttachedPlacement.below,
          ),
  );
}

/// The addresses a HEAD edit lands on: the row's link group
/// ([linkMirrorTargets]) and, of a row of a conte group, the rows at its
/// seat in every cut of the track ([conteHeadTargets]) — the closure of the
/// two, the row itself first and each address once. A 겸용 sibling's conte
/// on another track brings that track's conte rows with it: one head is one
/// head.
///
/// What walks it: a row's name, label, blend, static opacity and fold, its
/// transform switch and the shape of its effect chain. ⛔Never the named
/// keys' space or the cel bank — those are the link group's alone.
///
/// [cameraHead]: whether the field is one a track's cameras wear as one as
/// well ([cameraHeadTargets]) — the name and the transform switch, and not
/// the label.
List<({CutId cutId, LayerId layerId})> headMirrorTargets(
  Project project, {
  required CutId cutId,
  required LayerId layerId,
  bool cameraHead = false,
}) {
  // From the cut that HOLDS the row ([conteHeadTargets] says why): the
  // registry keys a row's group by its own cut, and would call a row
  // addressed under another one unlinked.
  final reached = [
    (cutId: cutIdOfLayer(project, layerId) ?? cutId, layerId: layerId),
  ];
  final seen = {reached.first};
  for (var index = 0; index < reached.length; index += 1) {
    final at = reached[index];
    final next = [
      ...linkMirrorTargets(project, cutId: at.cutId, layerId: at.layerId),
      ...conteHeadTargets(project, at.layerId),
      if (cameraHead) ...cameraHeadTargets(project, at.layerId),
    ];
    for (final target in next) {
      if (seen.add(target)) {
        reached.add(target);
      }
    }
  }
  return reached;
}

/// The rows that EXIST as one with ([cutId], [layerId]) — what a delete
/// takes together.
///
/// A linked row is one layer seen from several cuts ([linkMirrorTargets]).
/// And an ATTACH ROW OF A TRACK'S CONTE is one row of its head (I-73, the
/// drawn proposal 유저 took on 2026-10-08: 「머리 — … 어태치 구성 … —
/// 트랙의 모든 컷이 하나」): it goes from every cut of the track at once,
/// each cut's own link group with it ([headMirrorTargets]).
///
/// ⛔Not the conte itself. A cut has a conte or has none, cut by cut — the
/// rail keeps the button that makes one in every cut that has none — so
/// deleting one cut's is that cut's alone (and its link group's).
List<({CutId cutId, LayerId layerId})> existenceMirrorTargets(
  Project project, {
  required CutId cutId,
  required LayerId layerId,
}) {
  final layer = layerAnywhereOrNull(project, layerId);
  final ridesAConte =
      layer != null &&
      isAttachedLayer(layer) &&
      conteHeadTargets(project, layerId).isNotEmpty;
  return ridesAConte
      ? headMirrorTargets(project, cutId: cutId, layerId: layerId)
      : linkMirrorTargets(project, cutId: cutId, layerId: layerId);
}

/// The ROWS of [headMirrorTargets] — what [linkMirrorRows] is to the link
/// group: every row that wears the head, by id.
List<LayerId> headMirrorRows(
  Project project, {
  required CutId cutId,
  required LayerId layerId,
  bool cameraHead = false,
}) => [
  for (final target in headMirrorTargets(
    project,
    cutId: cutId,
    layerId: layerId,
    cameraHead: cameraHead,
  ))
    target.layerId,
];

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

/// [cutId]'s 겸용 group as CUTS, in TRACK order: the cut itself and its
/// [linkedCutSiblings] — the cut alone when it is linked to none. The FIRST
/// is the group's owner.
///
/// Track order, never 「the open cut first」: a group is one thing to
/// whatever reads it — the envelope's CUT lines and its ink's owner, the
/// export's joined cut name, the cut a cel is composited in (F-300) — and
/// what it reads must not depend on which sibling happens to be open.
///
/// ↩️Each of those walked the tracks for itself.
List<Cut> linkedCutGroupInTrackOrder(Project project, {required CutId cutId}) {
  final group = <CutId>{cutId, ...linkedCutSiblings(project, cutId: cutId)};
  return [
    for (final track in project.tracks)
      for (final cut in track.cuts)
        if (group.contains(cut.id)) cut,
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
}) => project.linkRegistry.counterpartIn(
  cutId: cutId,
  layerId: layerId,
  targetCutId: targetCutId,
);

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

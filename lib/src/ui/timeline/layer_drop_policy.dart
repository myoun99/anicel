/// Where a row-order drag would land — the ONE answer, shared by every
/// surface that draws a rail.
///
/// Three things live here and nowhere else:
///
/// * **What travels.** A folder carries its subtree, an attach base carries
///   its group; both are contiguous runs of the stack, and the model already
///   knows where they start and end ([LayerFolderIndex],
///   [attachedGroupStartIndex]).
/// * **Which way is up.** The horizontal rail renders the stack REVERSED and
///   the sheet renders it raw. That direction is INFERRED from the two lists
///   rather than passed in: a flag would be a fourth place where a surface
///   gets its own opinion about which way the stack runs, and R9 #22 is what
///   that costs.
/// * **Whether it may.** The proposed stack is handed to
///   [folderStructureProblem] — the structure validator that already exists.
///   A drop that would split a folder's run, mix an attach organizer with
///   ordinary rows, or make a cycle is refused by the same rule that refuses
///   it everywhere else, so this file invents no rule of its own.
/// * **What it ATTACHES and DETACHES** (P3). A slot strictly inside an
///   attach group means "ride this base"; leaving the group means "stop
///   riding it". See [_slotInsideGroup] for why those two tests are not the
///   same interval.
library;

import '../../models/attached_layer_mount.dart';
import '../../models/attached_layer_resolve.dart';
import '../../models/attached_placement.dart';
import '../../models/layer.dart';
import '../../models/layer_effect.dart' show EffectId;
import '../../models/layer_folder.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import 'effect_lane_policy.dart' show parseEffectLaneId;
import 'property_lane_model.dart' show TimelineDisplayRow;
import 'timeline_section_policy.dart';

/// A legal landing: the cut's new stack order, and the rows whose folder
/// membership the drop changes.
class LayerDropPlan {
  const LayerDropPlan({
    required this.order,
    required this.folderIds,
    required this.joinedFolderId,
    this.attach = const LayerAttachDrop(),
  });

  /// The cut's layers, bottom → top, after the move.
  final List<LayerId> order;

  /// The moved rows whose parent changes, to the folder they land in (null
  /// = out of every folder). Empty when the drop only re-orders.
  final Map<LayerId, LayerId?> folderIds;

  /// The folder the run lands INSIDE, for the caret's label ("이 폴더 안으로")
  /// — null at top level.
  final LayerId? joinedFolderId;

  /// The attach relationships this landing makes and breaks — the part of a
  /// drop that changes what a row IS rather than where it sits, and the part
  /// the caret has to say out loud before the release.
  final LayerAttachDrop attach;
}

/// The contiguous stack slice a drag on [movingId] carries.
///
/// `[start, endExclusive)` in [stack] order. A folder takes its subtree (and
/// sits directly above it — the folder invariant), an attach base takes its
/// whole group (R26 #36: the group is unsplittable), everything else takes
/// itself. An attach ROW takes only itself, which is what keeps it inside
/// its group.
({int start, int endExclusive})? layerDragRun(
  List<Layer> stack,
  LayerId movingId,
) {
  final index = stack.indexWhere((layer) => layer.id == movingId);
  if (index < 0) {
    return null;
  }
  final moving = stack[index];
  if (layerKindGroupsLayers(moving.kind)) {
    final members = stack.subtreeMembersOf(moving.id);
    if (members.isEmpty) {
      return (start: index, endExclusive: index + 1);
    }
    final first = stack.indexWhere((layer) => layer.id == members.first.id);
    // The folder row sits directly above its members, so the run ends at
    // the folder itself.
    return (start: first, endExclusive: index + 1);
  }
  if (moving.attachedToLayerId == null &&
      stack.any((other) => other.attachedToLayerId == moving.id)) {
    return (
      start: attachedGroupStartIndex(moving.id, stack),
      endExclusive: attachedGroupEndIndex(moving.id, stack),
    );
  }
  return (start: index, endExclusive: index + 1);
}

/// The MODEL insertion index a display caret [slot] names.
///
/// [slot] is a gap in [displayRows]: 0 is before the first row, `length` is
/// after the last. Returns null when neither neighbour is a row of [stack]
/// (the caret is off in another owner's rows — the track's SE list, which
/// no cut-layer drag can reach).
int? modelInsertionForSlot({
  required List<Layer> stack,
  required List<Layer> displayRows,
  required int slot,
}) {
  final modelIndex = <LayerId, int>{
    for (var i = 0; i < stack.length; i += 1) stack[i].id: i,
  };
  int? indexOfDisplay(int at) => at < 0 || at >= displayRows.length
      ? null
      : modelIndex[displayRows[at].id];

  final before = indexOfDisplay(slot - 1);
  final after = indexOfDisplay(slot);
  if (before != null && after != null) {
    // Adjacent in the stack whichever way the surface renders them.
    return before > after ? before : after;
  }
  final only = before ?? after;
  if (only == null) {
    return null;
  }
  // An END slot: which end depends on which way this surface runs, and the
  // two lists say it without being asked.
  final firstModel = modelIndex[displayRows.first.id];
  final lastModel = modelIndex[displayRows.last.id];
  final reversed =
      firstModel != null && lastModel != null && firstModel > lastModel;
  final atListEnd = before != null;
  if (reversed) {
    return atListEnd ? only : only + 1;
  }
  return atListEnd ? only + 1 : only;
}

/// The plan for dropping [movingId]'s run at [insertAt] in [stack], or null
/// when the landing is refused.
///
/// Refused: a slot inside the run's own span (a no-op), a landing in
/// another SECTION (the display re-buckets by kind, so it would spring
/// back), and anything [folderStructureProblem] rejects.
/// R5 #15: the plan for dropping [movingId] ON the row [targetId] rather
/// than in a gap between rows.
///
/// A caret lives between rows, and there are two intents it cannot express.
/// The inside of an EMPTY folder is one — with no members, "inside it" and
/// "outside, below it" are the same gap, which is why #14's empty folder
/// arrived with no door. The first attach rider on a base is the other: a
/// base with no riders has no inside either.
///
/// Both are the same gesture — you put the thing ON the thing — and the two
/// answers come from what the target IS: a folder swallows, a drawing row
/// takes a rider. Everything after that is [resolveLayerDrop]'s, so the two
/// paths cannot disagree about what is legal.
LayerDropPlan? resolveLayerDropOnRow({
  required List<Layer> stack,
  required LayerId movingId,
  required LayerId targetId,
}) {
  if (movingId == targetId) {
    return null;
  }
  final targetIndex = stack.indexWhere((layer) => layer.id == targetId);
  final run = layerDragRun(stack, movingId);
  if (targetIndex < 0 || run == null) {
    return null;
  }
  // Onto something the run carries — a folder onto one of its own members —
  // is a no-op, and would be a cycle if it were not.
  if (targetIndex >= run.start && targetIndex < run.endExclusive) {
    return null;
  }
  final target = stack[targetIndex];
  if (layerKindGroupsLayers(target.kind)) {
    // The TOP of the folder's members, which is the gap directly under the
    // folder row (the folder invariant puts the row above its members).
    return resolveLayerDrop(
      stack: stack,
      movingId: movingId,
      insertAt: targetIndex,
      forceJoinFolderId: targetId,
    );
  }
  return resolveLayerDrop(
    stack: stack,
    movingId: movingId,
    insertAt: targetIndex + 1,
    forceMountBaseId: targetId,
  );
}

LayerDropPlan? resolveLayerDrop({
  required List<Layer> stack,
  required LayerId movingId,
  required int insertAt,

  /// R5 #15: the folder the run joins, overriding the gap's own answer.
  /// Only [resolveLayerDropOnRow] passes it — it is how "inside this
  /// folder" gets said at all when the folder has no members to sit among.
  LayerId? forceJoinFolderId,

  /// R5 #15: the base the run mounts on, for the same reason — a base with
  /// no riders yet has no inside for a caret to land in.
  LayerId? forceMountBaseId,
}) {
  final run = layerDragRun(stack, movingId);
  if (run == null || insertAt < 0 || insertAt > stack.length) {
    return null;
  }
  if (insertAt > run.start && insertAt < run.endExclusive) {
    return null; // Inside itself.
  }
  // ④ (user, 2026-08-12): 「드래그 시작 시 자기 행 위에 뜨는 강조선 삭제 —
  // 위치가 실제로 바뀌는 상황에서만 뜬다」.
  //
  // A run owns the gaps at BOTH its ends, and lifting it out to put it back
  // there is not a landing. It used to resolve to a plan whose order was
  // the order it started with, so the caret was drawn the instant a drag
  // began — announcing a move nobody had made yet.
  //
  // The forced intents are exempt: dropping ON a row says something a gap
  // cannot ("ride this base", "go inside this folder"), and that intent is
  // real even when the row lands exactly where it already sat.
  if (forceJoinFolderId == null &&
      forceMountBaseId == null &&
      (insertAt == run.start || insertAt == run.endExclusive)) {
    return null;
  }
  final moving = stack.firstWhere((layer) => layer.id == movingId);
  final movingSection = timelineSectionForLayerKind(moving.kind);

  final carried = stack.sublist(run.start, run.endExclusive);
  final rest = [
    for (var i = 0; i < stack.length; i += 1)
      if (i < run.start || i >= run.endExclusive) stack[i],
  ];
  // The insertion point, restated against the list the run was lifted out
  // of: everything above the run slid down by its length.
  final restInsertAt = insertAt <= run.start
      ? insertAt
      : insertAt - carried.length;

  // SECTIONS: the row below the slot decides which one we are in (the
  // bottom of the stack is the first section by construction).
  final below = restInsertAt > 0 ? rest[restInsertAt - 1] : null;
  final above = restInsertAt < rest.length ? rest[restInsertAt] : null;
  final neighbour = below ?? above;
  if (neighbour != null &&
      timelineSectionForLayerKind(neighbour.kind) != movingSection) {
    return null;
  }

  // MEMBERSHIP: the folder the slot sits inside is the folder of the row
  // BELOW it — a member names its own folder, and a folder row (whose run
  // has just ended) names its parent. One formula covers both, and the
  // ends: nothing below means top level.
  //
  // ⚠️An EMPTY folder cannot be entered this way, and no formula could:
  // with no members, "inside it" and "outside, below it" are the SAME
  // slot. Landing in one takes an explicit intent — the caret hovering the
  // folder ROW — which is the drag's business, not the order's.
  final joinedFolderId = forceJoinFolderId ?? below?.folderId;
  final carriedIds = {for (final layer in carried) layer.id};
  final folderIds = <LayerId, LayerId?>{
    for (final layer in carried)
      // Rows whose parent travels WITH them keep pointing at it; only the
      // run's own top-level rows change hands.
      if (layer.folderId == null || !carriedIds.contains(layer.folderId))
        if (layer.folderId != joinedFolderId) layer.id: joinedFolderId,
  };

  // ATTACH (P3): the run's OWN group first — a row already inside one keeps
  // its base while the landing still touches the group, which is what makes
  // re-ordering within a group an ordinary move. An ORGANIZER folder answers
  // its base here too, so a 공정 folder can be repositioned inside its group.
  final runGroupBase =
      moving.attachedToLayerId ?? attachOrganizerBaseOf(moving, stack);
  final keepsOwnGroup =
      runGroupBase != null &&
      _slotTouchesGroup(rest, restInsertAt, runGroupBase);
  // Then the group the slot is strictly INSIDE, which can only be another
  // one (a slot touching this run's own group answered above).
  final insideGroup = keepsOwnGroup
      ? null
      : _slotInsideGroup(rest, restInsertAt, ownBase: runGroupBase);

  // Staying in the group still has a DIRECTION: crossing the base's picture
  // turns an above row into a below one (the same rule an organizer folder
  // reads off the stack). Nothing else about the attachment moves.
  ({LayerId layerId, AttachedPlacement placement})? sideChange;
  if (keepsOwnGroup && moving.attachedToLayerId == runGroupBase) {
    final side = _slotSideOfBase(rest, restInsertAt, runGroupBase);
    if (side != null && side != moving.attachedPlacement) {
      sideChange = (layerId: moving.id, placement: side);
    }
  }

  // R5 #15: dropping ON a drawing row names the base outright. It reads the
  // same as landing inside an existing group — the checks below are the
  // ones that matter — but it reaches the case a gap cannot: a base whose
  // group is still empty.
  final target = insideGroup ??
      (forceMountBaseId == null
          ? null
          : (baseId: forceMountBaseId, placement: AttachedPlacement.above));

  ({LayerId layerId, LayerId baseId, AttachedPlacement placement})? mount;
  if (target != null) {
    final insideGroup = target;
    final base = stack.firstWhere((layer) => layer.id == insideGroup.baseId);
    final single = run.endExclusive - run.start == 1;
    // No nesting: a row that carries attaches of its own is a base, and a
    // base inside another group would make the relation chain.
    final carriesAttaches = stack.any(
      (other) => other.attachedToLayerId == moving.id,
    );
    if (!single ||
        carriesAttaches ||
        !canMountLayerOnBase(row: moving, base: base)) {
      // The slice cannot join this group, and letting it land there anyway
      // would split a group that is unsplittable (R26 #36). The edges of the
      // group are still open, so "next to it" stays reachable.
      return null;
    }
    mount = (
      layerId: moving.id,
      baseId: insideGroup.baseId,
      placement: insideGroup.placement,
    );
  }

  // DETACH is the same question asked of every attach row that TRAVELS: its
  // base did not come along, and the landing no longer touches its group
  // (user 2026-08-07: dragging an attach row out detaches it rather than
  // refusing the drag). One rule covers the row the pointer held and the
  // rows carried inside an organizer folder.
  final detachIds = <LayerId>{
    for (final layer in carried)
      if (layer.attachedToLayerId != null &&
          !carriedIds.contains(layer.attachedToLayerId) &&
          mount?.layerId != layer.id &&
          !_slotTouchesGroup(rest, restInsertAt, layer.attachedToLayerId!))
        layer.id,
  };

  final attach = LayerAttachDrop(
    mount: mount,
    sideChange: sideChange,
    detachIds: detachIds,
  );
  Layer settled(Layer layer) {
    var next = folderIds.containsKey(layer.id)
        ? layer.copyWith(folderId: folderIds[layer.id])
        : layer;
    if (mount != null && layer.id == mount.layerId) {
      next = next.copyWith(
        attachedToLayerId: mount.baseId,
        attachedPlacement: mount.placement,
      );
    } else if (sideChange != null && layer.id == sideChange.layerId) {
      next = next.copyWith(attachedPlacement: sideChange.placement);
    } else if (detachIds.contains(layer.id)) {
      next = next.copyWith(attachedToLayerId: null);
    }
    return next;
  }

  final placed = [
    ...rest.sublist(0, restInsertAt),
    for (final layer in carried) settled(layer),
    ...rest.sublist(restInsertAt),
  ];
  // Validated WITH the attach change applied: dropping a plain row among a
  // 공정 organizer's members is legal precisely because it becomes one of
  // that base's attach rows, and the validator has to see that to agree.
  if (folderStructureProblem(placed) != null) {
    return null;
  }
  return LayerDropPlan(
    order: [for (final layer in placed) layer.id],
    folderIds: folderIds,
    joinedFolderId: joinedFolderId,
    attach: attach,
  );
}

/// Where a row has to LAND for a MENU detach — the placement half of "어태치
/// 해제", or null when clearing the pointer is the whole edit.
///
/// A detached row left INSIDE its old group's run would cut that run in two:
/// the group span is derived by CONTIGUITY, so every attach row past the
/// detached one would silently fall out of its own group (its `addAttach`
/// insertions, its unlink slice, its drag run all read the shorter span).
/// The row therefore steps just past the group's outer edge on the side it
/// was already on — the shortest move that keeps the run whole.
///
/// The 공정 ORGANIZER folder is the second reason to move: its identity is
/// "nothing but one base's attach rows", so a detached row left inside one
/// makes the folder quietly stop being an organizer, bringing back the fx
/// lanes and the arrow it exists to suppress.
///
/// Null when neither applies — the outermost row on its side, in no
/// organizer. Then nothing has to move, and nothing does.
int? detachLandingIndex(List<Layer> stack, LayerId layerId) {
  final index = stack.indexWhere((layer) => layer.id == layerId);
  if (index < 0) {
    return null;
  }
  final baseId = stack[index].attachedToLayerId;
  final baseIndex = baseId == null
      ? -1
      : stack.indexWhere((layer) => layer.id == baseId);
  if (baseId == null || baseIndex < 0) {
    return null; // Not attached, or a dangling link: no group to step out of.
  }
  final organizer = stack.folderById(stack[index].folderId);
  final inOrganizer =
      organizer != null && attachOrganizerBaseOf(organizer, stack) == baseId;
  if (index > baseIndex) {
    final groupEnd = attachedGroupEndIndex(baseId, stack);
    return !inOrganizer && index == groupEnd - 1 ? null : groupEnd;
  }
  final groupStart = attachedGroupStartIndex(baseId, stack);
  return !inOrganizer && index == groupStart ? null : groupStart;
}

/// The attach group [row] belongs to, named by its base — what a slot's
/// neighbours answer with.
///
/// [ownBase] is the base of the row being DRAGGED: while its only attach row
/// is off the list, the base row would otherwise stop reading as a base and
/// a lone attach row could not be moved from above its base to below it.
LayerId? _groupBaseOfRow(List<Layer> stack, Layer row, {LayerId? ownBase}) {
  final attached = row.attachedToLayerId;
  if (attached != null) {
    return attached;
  }
  final organizer = attachOrganizerBaseOf(row, stack);
  if (organizer != null) {
    return organizer;
  }
  if (row.id == ownBase ||
      stack.any((other) => other.attachedToLayerId == row.id)) {
    return row.id;
  }
  return null;
}

/// The group the slot at [insertAt] sits STRICTLY INSIDE — both neighbours
/// in the same group — with the side of the base it lands on.
///
/// Strictly inside is what MAKES an attach, and the strictness is the whole
/// safety of it: the slots at a group's two outer edges stay ordinary moves,
/// so a row can always be placed next to a group without joining it, and
/// passing above or below one commits nothing. The price is that a base with
/// no attach rows yet has no inner slot at all — mounting the FIRST one is
/// the Layer menu's job ("위/아래 레이어에 장착"), the same way an empty
/// folder cannot be entered by stepping.
({LayerId baseId, AttachedPlacement placement})? _slotInsideGroup(
  List<Layer> rest,
  int insertAt, {
  LayerId? ownBase,
}) {
  if (insertAt <= 0 || insertAt >= rest.length) {
    return null;
  }
  final below = _groupBaseOfRow(rest, rest[insertAt - 1], ownBase: ownBase);
  final above = _groupBaseOfRow(rest, rest[insertAt], ownBase: ownBase);
  if (below == null || below != above) {
    return null;
  }
  final baseIndex = rest.indexWhere((layer) => layer.id == below);
  if (baseIndex < 0) {
    return null;
  }
  // Above or below the BASE's picture, read off the stack the way an
  // organizer folder's arrow already reads it.
  return (
    baseId: below,
    placement: insertAt > baseIndex
        ? AttachedPlacement.above
        : AttachedPlacement.below,
  );
}

/// Which side of [baseId]'s picture the slot at [insertAt] lands on, or null
/// when that base is not in [rest] to be measured against.
AttachedPlacement? _slotSideOfBase(
  List<Layer> rest,
  int insertAt,
  LayerId baseId,
) {
  final baseIndex = rest.indexWhere((layer) => layer.id == baseId);
  if (baseIndex < 0) {
    return null;
  }
  return insertAt > baseIndex
      ? AttachedPlacement.above
      : AttachedPlacement.below;
}

/// Whether the slot at [insertAt] still TOUCHES [baseId]'s group — inside it
/// or at either edge.
///
/// The closed interval, where [_slotInsideGroup] is open, and for one
/// reason: a row that is already in the group keeps its membership at the
/// edges (dragging the topmost attach row one place up is a re-order, not a
/// detach), while a row from outside has to be put clearly INSIDE before it
/// joins.
bool _slotTouchesGroup(List<Layer> rest, int insertAt, LayerId baseId) {
  final below = insertAt > 0
      ? _groupBaseOfRow(rest, rest[insertAt - 1], ownBase: baseId)
      : null;
  if (below == baseId) {
    return true;
  }
  final above = insertAt < rest.length
      ? _groupBaseOfRow(rest, rest[insertAt], ownBase: baseId)
      : null;
  return above == baseId;
}

/// The gap [steps] away from the item at [index].
///
/// An item occupies the gaps [index] and `index + 1` and NEITHER is a move,
/// so a step down has to clear the second one. That asymmetry is the whole
/// reason this is a named function: stated inline as `index + steps` it
/// reads correct and silently refuses every downward drag.
int slotForSteps(int index, int steps, int count) {
  final slot = steps > 0 ? index + 1 + steps : index + steps;
  return slot.clamp(0, count);
}

/// The rail rows that are fx GROUP headers of [layerId], in display order,
/// with the row index each sits at.
///
/// The chain's slots are counted in THESE while the pointer's travel is
/// counted in rail rows, and the two differ exactly when a chain is twirled
/// open — which is when someone is most likely to be re-ordering it.
List<({int rowIndex, EffectId effectId})> effectHeaderRowsOf(
  List<TimelineDisplayRow> rows,
  LayerId layerId,
) {
  final headers = <({int rowIndex, EffectId effectId})>[];
  for (var index = 0; index < rows.length; index += 1) {
    final row = rows[index];
    final lane = row.lane;
    if (lane == null || !lane.isGroupHeader || row.layer.id != layerId) {
      continue;
    }
    final parsed = parseEffectLaneId(lane.laneId);
    if (parsed != null && parsed.parameterId == null) {
      headers.add((rowIndex: index, effectId: parsed.effectId));
    }
  }
  return headers;
}

/// How many HEADERS a travel of [rowSteps] rail rows from [fromRowIndex]
/// passes.
int effectStepsBetween(
  List<({int rowIndex, EffectId effectId})> headers,
  int fromRowIndex,
  int rowSteps,
) {
  final targetRow = fromRowIndex + rowSteps;
  var steps = 0;
  for (final header in headers) {
    if (rowSteps > 0 &&
        header.rowIndex > fromRowIndex &&
        header.rowIndex <= targetRow) {
      steps += 1;
    } else if (rowSteps < 0 &&
        header.rowIndex < fromRowIndex &&
        header.rowIndex >= targetRow) {
      steps -= 1;
    }
  }
  return steps;
}

/// One layer's effect chain after a header drag, in MODEL order — or null
/// when the landing is where it started.
///
/// [displayEffects] is the chain as the SURFACE lists it. The rail runs it
/// in model order (effects downward from the layer, Transform last) and the
/// sheet runs it reversed, and which one this is comes from COMPARING the
/// two lists rather than from a flag — the same rule the row drop follows,
/// for the same reason.
///
/// The Transform group is not in either list: it is not a chain member, it
/// is where the chain ends, so nothing can be dropped past it.
List<EffectId>? resolveEffectDrop({
  required List<EffectId> modelEffects,
  required List<EffectId> displayEffects,
  required EffectId movingId,
  required int slot,
}) {
  if (displayEffects.length != modelEffects.length) {
    return null;
  }
  final bool reversed;
  if (_sameOrder(displayEffects, modelEffects)) {
    reversed = false;
  } else if (_sameOrder(displayEffects, modelEffects.reversed.toList())) {
    reversed = true;
  } else {
    // An arrangement neither way round: refuse rather than guess which
    // half of it the slot was counted in.
    return null;
  }
  final from = displayEffects.indexOf(movingId);
  if (from < 0 || slot < 0 || slot > displayEffects.length) {
    return null;
  }
  if (slot >= from && slot <= from + 1) {
    return null; // Where it already is.
  }
  final next = [...displayEffects]..removeAt(from);
  next.insert(slot > from ? slot - 1 : slot, movingId);
  return reversed ? next.reversed.toList() : next;
}

bool _sameOrder(List<EffectId> a, List<EffectId> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}

/// The SE rows' plan: a flat permutation of the track's list. They carry no
/// folders and cannot interleave with a cut's rows (the display list
/// appends them), so the whole answer is an order.
List<LayerId>? resolveTrackSeDrop({
  required List<Layer> seLayers,
  required List<Layer> displayRows,
  required LayerId movingId,
  required int slot,
}) {
  final from = seLayers.indexWhere((layer) => layer.id == movingId);
  if (from < 0) {
    return null;
  }
  final insertAt = modelInsertionForSlot(
    stack: seLayers,
    displayRows: displayRows,
    slot: slot,
  );
  if (insertAt == null || (insertAt >= from && insertAt <= from + 1)) {
    return null;
  }
  final rest = [...seLayers]..removeAt(from);
  rest.insert(insertAt > from ? insertAt - 1 : insertAt, seLayers[from]);
  return [for (final layer in rest) layer.id];
}

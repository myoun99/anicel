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
library;

import '../../models/attached_layer_resolve.dart';
import '../../models/layer.dart';
import '../../models/layer_effect.dart' show EffectId;
import '../../models/layer_folder.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import 'timeline_section_policy.dart';

/// A legal landing: the cut's new stack order, and the rows whose folder
/// membership the drop changes.
class LayerDropPlan {
  const LayerDropPlan({
    required this.order,
    required this.folderIds,
    required this.joinedFolderId,
  });

  /// The cut's layers, bottom → top, after the move.
  final List<LayerId> order;

  /// The moved rows whose parent changes, to the folder they land in (null
  /// = out of every folder). Empty when the drop only re-orders.
  final Map<LayerId, LayerId?> folderIds;

  /// The folder the run lands INSIDE, for the caret's label ("이 폴더 안으로")
  /// — null at top level.
  final LayerId? joinedFolderId;
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
LayerDropPlan? resolveLayerDrop({
  required List<Layer> stack,
  required LayerId movingId,
  required int insertAt,
}) {
  final run = layerDragRun(stack, movingId);
  if (run == null || insertAt < 0 || insertAt > stack.length) {
    return null;
  }
  if (insertAt > run.start && insertAt < run.endExclusive) {
    return null; // Inside itself.
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
  final joinedFolderId = below?.folderId;
  final carriedIds = {for (final layer in carried) layer.id};
  final folderIds = <LayerId, LayerId?>{
    for (final layer in carried)
      // Rows whose parent travels WITH them keep pointing at it; only the
      // run's own top-level rows change hands.
      if (layer.folderId == null || !carriedIds.contains(layer.folderId))
        if (layer.folderId != joinedFolderId) layer.id: joinedFolderId,
  };

  final placed = [
    ...rest.sublist(0, restInsertAt),
    for (final layer in carried)
      folderIds.containsKey(layer.id)
          ? layer.copyWith(folderId: folderIds[layer.id])
          : layer,
    ...rest.sublist(restInsertAt),
  ];
  if (folderStructureProblem(placed) != null) {
    return null;
  }
  return LayerDropPlan(
    order: [for (final layer in placed) layer.id],
    folderIds: folderIds,
    joinedFolderId: joinedFolderId,
  );
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

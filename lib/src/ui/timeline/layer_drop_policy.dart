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

import 'package:flutter/foundation.dart';
import '../../models/attached_layer_mount.dart';
import '../../models/attached_layer_resolve.dart';
import '../../models/attached_placement.dart';
import '../../models/layer.dart';
import '../../models/layer_effect.dart' show EffectId;
import '../../models/layer_folder.dart';
import '../../models/layer_id.dart';
import '../../models/new_row_placement.dart';
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
///
/// ㊵ (유저 2026-08-12): 「선택범위로 레이어 여러개 선택하고 드래그하면 한
/// 레이어만 이동된다」. [alsoMoving] is the row SELECTION, and a selection that
/// contains [movingId] widens the run to span every selected row's own run —
/// so "what travels" stays ONE question with one answer, and every rule below
/// (what a slot may refuse, which side of a base, which folder is joined) goes
/// on reading the same two numbers.
///
/// ⚠️It is a SPAN, not a set: a row sitting between two selected ones travels
/// with them. That is the honest reading of a block move — the rows keep their
/// relative order — and it can only happen when the selection has a hole in it
/// (a filtered-out row), because a span is otherwise contiguous by
/// construction.
({int start, int endExclusive})? layerDragRun(
  List<Layer> stack,
  LayerId movingId, {
  Set<LayerId> alsoMoving = const {},
}) {
  final own = _ownDragRun(stack, movingId);
  if (own == null || alsoMoving.length <= 1 || !alsoMoving.contains(movingId)) {
    return own;
  }
  var start = own.start;
  var endExclusive = own.endExclusive;
  for (final id in alsoMoving) {
    final other = id == movingId ? null : _ownDragRun(stack, id);
    if (other == null) {
      continue;
    }
    if (other.start < start) {
      start = other.start;
    }
    if (other.endExclusive > endExclusive) {
      endExclusive = other.endExclusive;
    }
  }
  return (start: start, endExclusive: endExclusive);
}

/// What ONE row carries, before a selection has its say.
({int start, int endExclusive})? _ownDragRun(
  List<Layer> stack,
  LayerId movingId,
) {
  final index = stack.indexWhere((layer) => layer.id == movingId);
  if (index < 0) {
    return null;
  }
  final moving = stack[index];
  if (moving.kind.groupsLayers) {
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
  //
  // 🚨A5-3 (유저 2026-08-22) — **ASK THE ROWS OF THIS STACK, NOT THE ENDS OF
  // THE LIST.**
  //
  // > 「타임라인패널에서, **se레이어가 2개 있을경우 se행끼리 순서바꾸기가
  // > 안됐음** … 레이어 2개일땐 그냥 안되고 **3개일땐 2번째 레이어가
  // > 드래그가 안 되고 1번 3번은 됨.** 뭔가 이상한 규칙이 있는듯」
  //
  // ⛔This used to read `displayRows.first` and `displayRows.last`, which
  // works only when the surface shows THIS stack and nothing else. The
  // storyboard's rail does (it hands in the track's SE rows alone), so it
  // was right there and wrong on the timeline, whose display list is the
  // whole composed film — camera rows, then SE rows, then drawing rows.
  // The track's SE block sits in the MIDDLE, so both ends fell outside
  // `modelIndex`, `reversed` was forced to false, and the end-slot
  // arithmetic came out one seat short.
  //
  // 📐What that produced is exactly what the user counted: with two SE rows
  // every reachable landing collapsed onto 1 and the "already there" guard
  // refused both; with three the reachable set was {1, 2}, so the outer two
  // could still find a landing and the MIDDLE one could not.
  //
  // ★The rows of [stack] the display actually shows are the ones that know
  // which way it runs. When the ends already belong to the stack this picks
  // the same two rows, so every surface that was right stays right.
  int? firstModel;
  int? lastModel;
  for (final row in displayRows) {
    final at = modelIndex[row.id];
    if (at == null) {
      continue;
    }
    firstModel ??= at;
    lastModel = at;
  }
  final reversed =
      firstModel != null && lastModel != null && firstModel > lastModel;
  final atListEnd = before != null;
  if (reversed) {
    return atListEnd ? only : only + 1;
  }
  return atListEnd ? only + 1 : only;
}

/// Where a NEW row lands for the caret gap [slot] of [displayRows] — the
/// model index, or null where no new row may go.
///
/// The answers a moved row gets, asked for a row that is not in the stack
/// yet: the gap must name a place in [stack] ([modelInsertionForSlot]); it
/// must sit in the DRAWING section, read off the row below as a landing's
/// section is (`_Lift.below`) — a picture row let go between camera rows
/// would re-bucket into its own section, so the line would promise a place
/// it does not land; and it must not split an attach group
/// ([newRowPlacement] would carry the row past the group, and the line has
/// to be where the row goes).
int? newRowInsertionForSlot({
  required List<Layer> stack,
  required List<Layer> displayRows,
  required int slot,
}) {
  final insertAt = modelInsertionForSlot(
    stack: stack,
    displayRows: displayRows,
    slot: slot,
  );
  if (insertAt == null) {
    return null;
  }
  final neighbour = insertAt > 0 ? stack[insertAt - 1] : stack.first;
  if (timelineSectionForLayerKind(neighbour.kind) != TimelineSection.drawing) {
    return null;
  }
  return newRowPlacement(stack, insertAt).index == insertAt ? insertAt : null;
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

  /// ㊵: the row selection this drag carries, when [movingId] is in it.
  Set<LayerId> alsoMoving = const {},
}) {
  if (movingId == targetId) {
    return null;
  }
  final targetIndex = stack.indexWhere((layer) => layer.id == targetId);
  final run = layerDragRun(stack, movingId, alsoMoving: alsoMoving);
  if (targetIndex < 0 || run == null) {
    return null;
  }
  // Onto something the run carries — a folder onto one of its own members —
  // is a no-op, and would be a cycle if it were not.
  if (targetIndex >= run.start && targetIndex < run.endExclusive) {
    return null;
  }
  final target = stack[targetIndex];
  if (target.kind.groupsLayers) {
    // The TOP of the folder's members, which is the gap directly under the
    // folder row (the folder invariant puts the row above its members).
    return resolveLayerDrop(
      stack: stack,
      movingId: movingId,
      insertAt: targetIndex,
      forceJoinFolderId: targetId,
      alsoMoving: alsoMoving,
    );
  }
  // ⑤ (user, 2026-08-12): 「어태치 장착 면은 두 행의 상대 위치가 정한다.
  // 아래에서 위로 붙이면 아래쪽 어태치여야 하는데 지금은 무조건 위쪽
  // 어태치가 된다」.
  //
  // A rider's side is a fact about the PICTURE — which of the two composites
  // over the other — so it has to be the side the row was already on. It was
  // written here as a constant `above`, which meant carrying a row up onto
  // its new base silently flipped it over that base.
  //
  // The stack position follows the same answer rather than being decided
  // separately: a below rider sits under its base, an above one over it, so
  // one comparison settles both and they cannot disagree.
  final fromBelow = run.start < targetIndex;
  return resolveLayerDrop(
    stack: stack,
    movingId: movingId,
    insertAt: fromBelow ? targetIndex : targetIndex + 1,
    forceMountBaseId: targetId,
    forceMountPlacement: fromBelow
        ? AttachedPlacement.below
        : AttachedPlacement.above,
    alsoMoving: alsoMoving,
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

  /// ⑤: which side of that base's picture the rider takes. Only
  /// [resolveLayerDropOnRow] passes it, and it reads the answer off the two
  /// rows' relative position — a gap says its own side ([_slotInsideGroup]),
  /// but a drop ON a row has no gap to ask.
  AttachedPlacement forceMountPlacement = AttachedPlacement.above,

  /// ㊵: the row selection this drag carries, when [movingId] is in it.
  Set<LayerId> alsoMoving = const {},

  /// F-31②: the row the POINTER stands in, which splits the boundary caret
  /// in half — see [_slotKeepsGroup]. Null from every caller that has no
  /// pointer (the menu moves, the tests), and the closed interval stands.
  LayerId? pointerInRow,
}) {
  final forced = forceJoinFolderId != null || forceMountBaseId != null;
  final lift = _liftIfLanding(
    stack,
    movingId,
    insertAt,
    alsoMoving: alsoMoving,
    pointerInRow: pointerInRow,
    forced: forced,
  );
  if (lift == null) return null;
  // MEMBERSHIP: the folder the slot sits inside is the folder of the row
  // BELOW it — a member names its own folder, and a folder row (whose run
  // has just ended) names its parent. One formula covers both, and the
  // ends: nothing below means top level.
  //
  // ⚠️An EMPTY folder cannot be entered this way, and no formula could:
  // with no members, "inside it" and "outside, below it" are the SAME
  // slot. Landing in one takes an explicit intent — the caret hovering the
  // folder ROW — which is the drag's business, not the order's.
  final joinedFolderId = forceJoinFolderId ?? lift.below?.folderId;
  final folderIds = _folderChanges(lift, joinedFolderId);
  final attach = _attachPlan(
    lift,
    forceMountBaseId: forceMountBaseId,
    forceMountPlacement: forceMountPlacement,
  );
  if (attach == null) return null;
  final placed = _placed(lift, folderIds, attach);
  // Validated WITH the attach change applied: dropping a plain row among a
  // 공정 organizer's members is legal precisely because it becomes one of
  // that base's attach rows, and the validator has to see that to agree.
  if (folderStructureProblem(placed) != null) return null;
  return LayerDropPlan(
    order: [for (final layer in placed) layer.id],
    folderIds: folderIds,
    joinedFolderId: joinedFolderId,
    attach: attach,
  );
}

/// The run lifted out of the stack, against the rest: everything a landing
/// is judged against.
class _Lift {
  const _Lift({
    required this.stack,
    required this.moving,
    required this.carried,
    required this.carriedIds,
    required this.rest,
    required this.restInsertAt,
    required this.pointerInRow,
  });

  factory _Lift.of(
    List<Layer> stack,
    LayerId movingId,
    ({int start, int endExclusive}) run,
    int insertAt,
    LayerId? pointerInRow,
  ) {
    final carried = stack.sublist(run.start, run.endExclusive);
    return _Lift(
      stack: stack,
      moving: stack.firstWhere((layer) => layer.id == movingId),
      carried: carried,
      carriedIds: {for (final layer in carried) layer.id},
      rest: [
        for (var i = 0; i < stack.length; i += 1)
          if (i < run.start || i >= run.endExclusive) stack[i],
      ],
      // The insertion point, restated against the list the run was lifted
      // out of: everything above the run slid down by its length.
      restInsertAt: insertAt <= run.start
          ? insertAt
          : insertAt - carried.length,
      pointerInRow: pointerInRow,
    );
  }

  final List<Layer> stack;
  final Layer moving;
  final List<Layer> carried;
  final Set<LayerId> carriedIds;
  final List<Layer> rest;
  final int restInsertAt;
  final LayerId? pointerInRow;

  /// SECTIONS: the row below the slot decides which one we are in (the
  /// bottom of the stack is the first section by construction).
  Layer? get below => restInsertAt > 0 ? rest[restInsertAt - 1] : null;
  Layer? get above => restInsertAt < rest.length ? rest[restInsertAt] : null;
}

/// The lift, or null when the slot is no landing for this run or would
/// take it out of its section.
_Lift? _liftIfLanding(
  List<Layer> stack,
  LayerId movingId,
  int insertAt, {
  required Set<LayerId> alsoMoving,
  required LayerId? pointerInRow,
  required bool forced,
}) {
  final run = layerDragRun(stack, movingId, alsoMoving: alsoMoving);
  if (run == null ||
      !_lands(run, insertAt, stackLength: stack.length, forced: forced)) {
    return null;
  }
  final lift = _Lift.of(stack, movingId, run, insertAt, pointerInRow);
  return _leavesSection(lift) ? null : lift;
}

/// Whether [insertAt] is a landing at all for [run].
///
/// ④ (user, 2026-08-12): 「드래그 시작 시 자기 행 위에 뜨는 강조선 삭제 —
/// 위치가 실제로 바뀌는 상황에서만 뜬다」.
///
/// A run owns the gaps at BOTH its ends, and lifting it out to put it back
/// there is not a landing. It used to resolve to a plan whose order was
/// the order it started with, so the caret was drawn the instant a drag
/// began — announcing a move nobody had made yet.
///
/// The forced intents are exempt: dropping ON a row says something a gap
/// cannot ("ride this base", "go inside this folder"), and that intent is
/// real even when the row lands exactly where it already sat.
bool _lands(
  ({int start, int endExclusive}) run,
  int insertAt, {
  required int stackLength,
  required bool forced,
}) {
  if (insertAt < 0 || insertAt > stackLength) return false;
  if (insertAt > run.start && insertAt < run.endExclusive) {
    return false; // Inside itself.
  }
  return forced || (insertAt != run.start && insertAt != run.endExclusive);
}

/// 🚨A5-4: the RANK travels with the section. Inside the camera section the
/// three kinds have a fixed order (camera on top, then transition, then
/// direction), so 「디렉션 = 디렉션끼리만」 is the same sentence as "may not
/// cross a section", one level down.
///
/// ⚠️This is also what made the move IRREVERSIBLE. The section is read off
/// the row BELOW the slot, so one gap answers differently depending on
/// which side is asked — a Direction row could climb past the camera and
/// then find the single gap that would put it back refused, because that
/// gap's `below` is a drawing row. Comparing the rank refuses the climb
/// itself, and the pair stops being asymmetric because neither direction
/// is legal.
bool _leavesSection(_Lift lift) {
  final neighbour = lift.below ?? lift.above;
  if (neighbour == null) return false;
  final moving = lift.moving;
  return timelineSectionForLayerKind(neighbour.kind) !=
          timelineSectionForLayerKind(moving.kind) ||
      timelineCameraSectionRank(neighbour.kind) !=
          timelineCameraSectionRank(moving.kind);
}

/// Rows whose parent travels WITH them keep pointing at it; only the run's
/// own top-level rows change hands.
Map<LayerId, LayerId?> _folderChanges(_Lift lift, LayerId? joinedFolderId) => {
  for (final layer in lift.carried)
    if (_changesFolder(lift, layer, joinedFolderId)) layer.id: joinedFolderId,
};

bool _changesFolder(_Lift lift, Layer layer, LayerId? joinedFolderId) {
  final parent = layer.folderId;
  final parentTravels = parent != null && lift.carriedIds.contains(parent);
  return !parentTravels && parent != joinedFolderId;
}

typedef _Mount = ({
  LayerId layerId,
  LayerId baseId,
  AttachedPlacement placement,
});
typedef _Target = ({LayerId baseId, AttachedPlacement placement});

/// ATTACH (P3): the run's OWN group first — a row already inside one keeps
/// its base while the landing still KEEPS the group (F-31②: at the
/// boundary that is the half the pointer is in), which is what makes
/// re-ordering within a group an ordinary move. An ORGANIZER folder answers
/// its base here too, so a 공정 folder can be repositioned inside its group.
///
/// ⚠️Passing the pointer here changes no OUTCOME today, and that is a
/// proof rather than an oversight: a slot that touches this group cannot
/// be strictly inside another one (the neighbour that puts it in this
/// group is not in that one), so [_slotInsideGroup] is null either way
/// and the run detaches instead of mounting. It is asked with the pointer
/// anyway because it is the same question as the detach test, and two
/// spellings of one question is how they drift apart.
///
/// Then the group the slot is strictly INSIDE, which can only be another
/// one (a slot touching this run's own group answered above). R5 #15:
/// dropping ON a drawing row names the base outright. It reads the same as
/// landing inside an existing group — the checks in [_mountsOn] are the
/// ones that matter — but it reaches the case a gap cannot: a base whose
/// group is still empty.
LayerAttachDrop? _attachPlan(
  _Lift lift, {
  required LayerId? forceMountBaseId,
  required AttachedPlacement forceMountPlacement,
}) {
  final moving = lift.moving;
  final ownBase =
      moving.attachedToLayerId ?? attachOrganizerBaseOf(moving, lift.stack);
  final keepsOwnGroup =
      ownBase != null &&
      _slotKeepsGroup(lift.rest, lift.restInsertAt, ownBase, lift.pointerInRow);
  final target =
      (keepsOwnGroup
          ? null
          : _slotInsideGroup(lift.rest, lift.restInsertAt, ownBase: ownBase)) ??
      (forceMountBaseId == null
          ? null
          : (baseId: forceMountBaseId, placement: forceMountPlacement));
  final mounts = target == null ? const <_Mount>[] : _mountsOn(lift, target);
  if (mounts == null) return null;
  return LayerAttachDrop(
    mounts: mounts,
    sideChange: keepsOwnGroup ? _sideChange(lift, ownBase) : null,
    detachIds: _detachIds(lift, mounts),
  );
}

/// Staying in the group still has a DIRECTION: crossing the base's picture
/// turns an above row into a below one (the same rule an organizer folder
/// reads off the stack). Nothing else about the attachment moves.
({LayerId layerId, AttachedPlacement placement})? _sideChange(
  _Lift lift,
  LayerId ownBase,
) {
  final moving = lift.moving;
  if (moving.attachedToLayerId != ownBase) return null;
  final side = _slotSideOfBase(lift.rest, lift.restInsertAt, ownBase);
  if (side == null || side == moving.attachedPlacement) return null;
  return (layerId: moving.id, placement: side);
}

/// ⑦ (user, 2026-08-12): 「폴더도 드래그 드롭으로 어태치 장착 가능(동일
/// 규칙). 불가능한 경우는 「어태치 폴더 안에 폴더」 구조뿐이고 그때는
/// 안내문을 낸다」.
///
/// A folder never becomes a rider itself — an organizer folder IS its
/// members riding one base ([attachOrganizerBaseOf]) — so a folder run
/// mounts the rows it carries and the folder follows by derivation. That
/// is why this is a LIST of riders rather than "the moved row".
///
/// 🪦⑦ used to exclude one more shape here — a folder carrying a folder,
/// because «an organizer folder is FLAT». That ban lived in the model
/// (`attachOrganizerBaseOf` read DIRECT members, so a nested folder made
/// an organizer impure) and 유저 2026-08-29 lifted it: nothing about
/// drawing required it, and plain folders already nest. The walk reads
/// the subtree's leaves now, so a carried folder is just structure and
/// its leaves are the riders.
List<Layer> _ridersOf(_Lift lift) {
  final moving = lift.moving;
  if (!moving.kind.groupsLayers) {
    return lift.carried.length == 1 ? [moving] : const <Layer>[];
  }
  return lift.carried.where((layer) => !layer.kind.groupsLayers).toList();
}

/// The mounts onto [target], or null when the slice cannot join that group
/// — letting it land there anyway would split a group that is unsplittable
/// (R26 #36). The edges of the group are still open, so "next to it" stays
/// reachable.
///
/// ⛔What did NOT change with ⑦'s lift: every leaf must still be an attach
/// of the SAME base — 「a레이어 어태치 안에 있는 모든거는 a에 대한
/// 어태치여야해」. [canMountLayerOnBase] is where each rider answers for
/// itself. No chaining: a row that carries attaches of its own is a base,
/// and a base inside another group would make the relation chain.
List<_Mount>? _mountsOn(_Lift lift, _Target target) {
  final base = lift.stack.firstWhere((layer) => layer.id == target.baseId);
  final riders = _ridersOf(lift);
  final carriesAttaches = lift.stack.any(
    (other) => lift.carriedIds.contains(other.attachedToLayerId),
  );
  if (riders.isEmpty ||
      carriesAttaches ||
      riders.any((row) => !canMountLayerOnBase(row: row, base: base))) {
    return null;
  }
  return [
    for (final row in riders)
      (layerId: row.id, baseId: target.baseId, placement: target.placement),
  ];
}

/// DETACH is the same question asked of every attach row that TRAVELS: its
/// base did not come along, and the landing no longer touches its group
/// (user 2026-08-07: dragging an attach row out detaches it rather than
/// refusing the drag). One rule covers the row the pointer held and the
/// rows carried inside an organizer folder.
Set<LayerId> _detachIds(_Lift lift, List<_Mount> mounts) {
  final mountedIds = {for (final mount in mounts) mount.layerId};
  return {
    for (final layer in lift.carried)
      if (layer.attachedToLayerId != null &&
          !lift.carriedIds.contains(layer.attachedToLayerId) &&
          !mountedIds.contains(layer.id) &&
          !_slotKeepsGroup(
            lift.rest,
            lift.restInsertAt,
            layer.attachedToLayerId!,
            lift.pointerInRow,
          ))
        layer.id,
  };
}

/// The stack with the run put down in its slot, each carried row settled.
List<Layer> _placed(
  _Lift lift,
  Map<LayerId, LayerId?> folderIds,
  LayerAttachDrop attach,
) {
  final mountById = {for (final mount in attach.mounts) mount.layerId: mount};
  return [
    ...lift.rest.sublist(0, lift.restInsertAt),
    for (final layer in lift.carried)
      _settled(layer, folderIds, attach, mountById[layer.id]),
    ...lift.rest.sublist(lift.restInsertAt),
  ];
}

Layer _settled(
  Layer layer,
  Map<LayerId, LayerId?> folderIds,
  LayerAttachDrop attach,
  _Mount? mount,
) {
  var next = folderIds.containsKey(layer.id)
      ? layer.copyWith(folderId: folderIds[layer.id])
      : layer;
  final sideChange = attach.sideChange;
  if (mount != null) {
    next = next.copyWith(
      attachedToLayerId: mount.baseId,
      attachedPlacement: mount.placement,
    );
  } else if (sideChange != null && layer.id == sideChange.layerId) {
    next = next.copyWith(attachedPlacement: sideChange.placement);
  } else if (attach.detachIds.contains(layer.id)) {
    next = next.copyWith(attachedToLayerId: null);
  }
  return next;
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

/// Which of the slot's two neighbours belong to [baseId]'s group.
///
/// One walk, because every question a slot gets asked about a group is some
/// reading of this pair: TOUCHES is either side, strictly INSIDE is both,
/// and the boundary that F-31② splits in half is exactly one.
({bool below, bool above}) _groupSidesOfSlot(
  List<Layer> rest,
  int insertAt,
  LayerId baseId,
) => (
  below:
      insertAt > 0 &&
      _groupBaseOfRow(rest, rest[insertAt - 1], ownBase: baseId) == baseId,
  above:
      insertAt < rest.length &&
      _groupBaseOfRow(rest, rest[insertAt], ownBase: baseId) == baseId,
);

/// Whether a run landing at [insertAt] KEEPS its membership of [baseId]'s
/// group — the touch test, split in half at the boundary by where the
/// pointer stands.
///
/// F-31② (user, 2026-08-29): 「어태치 경계에 커서 가면 가로선 생기는 거,
/// 그걸 커서 위치에 따라 영역을 반으로 나눠서 어태치 안쪽이면 어태치 유지한
/// 채로 외곽에 두는 로직, 바깥쪽이면 어태치 해제하는 로직」.
///
/// The boundary gap is one caret with two meanings: it is both the group's
/// outer edge and the first slot outside. The predicate this replaces
/// (`_slotTouchesGroup`) answered the closed interval — the edge always
/// kept the row, on the reasoning that a row already in the group keeps
/// its membership at the edges while a row from outside has to be put
/// clearly INSIDE before it joins. That made the second meaning
/// unsayable, and leaving a group meant travelling one row further than
/// the picture suggested.
///
/// 🚨ONE function, asked by BOTH sites. "Does the run keep its own group"
/// and "does this attach row detach" are the same question, and they were
/// on their way to answering it differently — a closed interval here and a
/// split boundary there. `_slotTouchesGroup` was this with a null pointer,
/// so it is this with a null pointer.
///
/// The half is not new geometry: the gap has a row on either side of it,
/// and the one the pointer is IN is the answer. Inside that group's row —
/// even its base — keeps the attach; the row past it lets go.
///
/// [pointerInRow] is null when the drag has no pointer row to offer (a menu
/// move, a test, the pointer over a lane), and then the old closed interval
/// stands: no information is not a reason to detach.
bool _slotKeepsGroup(
  List<Layer> rest,
  int insertAt,
  LayerId baseId,
  LayerId? pointerInRow,
) {
  final sides = _groupSidesOfSlot(rest, insertAt, baseId);
  if (!sides.below && !sides.above) {
    return false;
  }
  if (sides.below && sides.above) {
    return true; // Strictly inside: there is no half to be on.
  }
  if (pointerInRow == null) {
    return true;
  }
  for (final row in rest) {
    if (row.id == pointerInRow) {
      return _groupBaseOfRow(rest, row, ownBase: baseId) == baseId;
    }
  }
  // The pointer is over a row this drag CARRIES: it moved with the run, so
  // it says nothing about which side of the boundary the run came to rest.
  return true;
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

/// The rail rows that are LAYER rows, in display order, with the row index
/// each sits at — the layer list a caret can actually land in.
///
/// 🚨F-31 (유저 2026-08-24: 「보이는것중에서만 이동하도록」). This is
/// [effectHeaderRowsOf]'s problem one list up, and it bites harder: travel
/// is counted in rail ROWS while a slot indexes the LAYER list, and those
/// two lists part company in BOTH directions. A collapsed folder or attach
/// group contributes layers and no rows; a twirled-open layer contributes
/// rows and no layers. Adding rail-row travel to a layer index therefore
/// ran the caret ahead of the cursor as soon as either happened — and past
/// a folded group the caret's slot named a gap no visible row draws, so the
/// line went missing entirely.
///
/// Handing THIS list to the drop policy is also what makes the landing
/// right: with only visible rows in it, the gap after a folded folder has
/// the next VISIBLE row on its far side, so the insertion lands after the
/// folder's members instead of among them.
List<({int rowIndex, Layer layer})> layerRowsOf(List<TimelineDisplayRow> rows) {
  final layers = <({int rowIndex, Layer layer})>[];
  for (var index = 0; index < rows.length; index += 1) {
    final row = rows[index];
    if (!row.isLane) {
      layers.add((rowIndex: index, layer: row.layer));
    }
  }
  return layers;
}

/// The gap among the LAYER rows on screen nearest a pointer standing
/// [along] into a uniform strip of [pitch]-long rows — the caret a drag
/// that holds no row raises (a file from the pool).
///
/// 유저 2026-08-12 ④: the line is where the cursor is — the nearest
/// boundary between layer rows. Lanes only ever trail the layer they belong
/// to, so the last gap is the strip's end.
int nearestLayerGap(
  List<TimelineDisplayRow> rows,
  double along,
  double pitch,
) {
  final layers = layerRowsOf(rows);
  var nearest = 0;
  var nearestDistance = double.infinity;
  for (var slot = 0; slot <= layers.length; slot += 1) {
    final edge =
        (slot < layers.length ? layers[slot].rowIndex : rows.length) * pitch;
    final distance = (along - edge).abs();
    if (distance < nearestDistance) {
      nearest = slot;
      nearestDistance = distance;
    }
  }
  return nearest;
}

/// One dragged row's view of the rail: the layer rows on screen, where the
/// row sits among them, and the two answers a travel needs.
///
/// It exists so the rail and the x-sheet ask the same object rather than
/// each doing the same arithmetic — the arithmetic they were each doing is
/// what F-31 is (see [layerRowsOf]), and one of them getting fixed alone is
/// how it would come back.
class LayerRowCaret {
  LayerRowCaret._(this.rows, this.slot);

  /// Null when [movingId] has no row in this pass — the held row pinned
  /// outside the window, which has nothing to count from.
  static LayerRowCaret? of(List<TimelineDisplayRow> rows, LayerId movingId) {
    final onScreen = layerRowsOf(rows);
    final slot = onScreen.indexWhere((row) => row.layer.id == movingId);
    return slot < 0 ? null : LayerRowCaret._(onScreen, slot);
  }

  final List<({int rowIndex, Layer layer})> rows;

  /// The dragged row's index among [layers] — its own gap, and the caret's
  /// `slotBefore`.
  final int slot;

  /// The layers a drop may land between: the ones with a row on screen.
  List<Layer> get layers => [for (final row in rows) row.layer];

  bool get isLastRow => slot == rows.length - 1;

  /// The gap a travel of [rowSteps] RAIL rows lands on.
  int slotFor(int rowSteps) => slotForSteps(
    slot,
    rowStepsBetween(
      [for (final row in rows) row.rowIndex],
      rows[slot].rowIndex,
      rowSteps,
    ),
    rows.length,
  );

  /// The layer the ON-ROW band names, or null when the band is over a rail
  /// row that is not a layer row (a lane) — a lane holds no drop.
  Layer? onRowLayer(int? onRow) {
    if (onRow == null) {
      return null;
    }
    final targetRow = rows[slot].rowIndex + onRow;
    for (final row in rows) {
      if (row.rowIndex == targetRow) {
        return row.layer;
      }
    }
    return null;
  }
}

/// How many ENTRIES of [rowIndices] a travel of [rowSteps] rail rows from
/// [fromRowIndex] passes.
///
/// One walk for both lists that need it — the fx chain's headers and the
/// layer rows — because they are the same question asked of different rows,
/// and the layer half only ever got it wrong by not asking.
int rowStepsBetween(List<int> rowIndices, int fromRowIndex, int rowSteps) {
  final targetRow = fromRowIndex + rowSteps;
  var steps = 0;
  for (final rowIndex in rowIndices) {
    if (rowSteps > 0 && rowIndex > fromRowIndex && rowIndex <= targetRow) {
      steps += 1;
    } else if (rowSteps < 0 &&
        rowIndex < fromRowIndex &&
        rowIndex >= targetRow) {
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
  if (listEquals(displayEffects, modelEffects)) {
    reversed = false;
  } else if (listEquals(displayEffects, modelEffects.reversed.toList())) {
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

/// The slot an fx chain's header at [slot] lands in once a drag has
/// crossed [steps] rows, given the chain's [headers] in display order.
///
/// ⛔ONE ANSWER FOR BOTH AXES. The horizontal rail and the vertical sheet
/// each wrote out the same three nested calls, and a chain that reorders
/// one way in the timeline and another in the sheet is one chain
/// disagreeing with itself. Both also hand [EffectRowDragHooks.onEffectUpdate]
/// the same effect-id list, which is why it is built here too.
({int slot, List<EffectId> effectIds}) effectChainAfterCrossing(
  List<({int rowIndex, EffectId effectId})> headers,
  int slot,
  int steps,
) => (
  slot: slotForSteps(
    slot,
    rowStepsBetween(
      [for (final header in headers) header.rowIndex],
      headers[slot].rowIndex,
      steps,
    ),
    headers.length,
  ),
  effectIds: [for (final header in headers) header.effectId],
);

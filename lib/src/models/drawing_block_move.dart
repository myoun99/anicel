import 'dart:collection';
import 'dart:math' as math;

import 'block_row_swap.dart';
import 'block_run_move.dart';
import 'cel_bank_lanes.dart';
import 'cel_rekey.dart';
import 'frame.dart';
import 'frame_id.dart';
import 'layer.dart';
import 'timeline_coverage.dart';
import 'timeline_exposure.dart';
import 'timeline_repeat.dart' show ghostFreeTimeline;

/// Where the axis stops for [layer]'s blocks, given the cut is
/// [cutFrameCount] frames long — or null when nothing stops them.
///
/// A row that TILES its cut lives inside it (the storyboard's), so its last
/// block may not slide past the cut's end: coverage would stop making a
/// panel for it and the drawing would drop off the conte while staying in
/// the file. Every other row may sit past the end, which is data the cut
/// simply does not show.
///
/// Both ends are the CONTE's, in the cut's own frames ([layerBlockFloor]).
int? _axisEndFor(Layer layer, int? cutFrameCount) =>
    layerCoversWithoutGaps(layer) && cutFrameCount != null
    ? layerBlockFloor(layer) + cutFrameCount
    : null;

/// The resolved result of a whole-block move drag (R10-④b): the affected
/// layers with the block relocated. Same-layer slides carry only
/// [sourceAfter]; cross-layer moves also carry the target pair and the
/// frame ids whose brush drawings must re-key — to the target layer, and
/// back from it ([returnedFrameIds]).
class DrawingBlockMovePlan {
  const DrawingBlockMovePlan({
    required this.sourceAfter,
    this.targetBefore,
    this.targetAfter,
    this.movedFrameIds = const [],
    this.returnedFrameIds = const [],
    required this.destinationStartIndex,
  }) : assert(
         (targetBefore == null) == (targetAfter == null),
         'Cross-layer plans carry both target snapshots.',
       );

  final Layer sourceAfter;

  /// Null when the move stays on the source layer.
  final Layer? targetBefore;
  final Layer? targetAfter;

  /// Frame ids that changed owning layer (empty for same-layer slides).
  final List<FrameId> movedFrameIds;

  /// Frame ids the landing sent back from the target to the source — the
  /// blocks it landed on ([LandingSwapsThem], F-384); none for a slide or
  /// a landing that pushes them.
  final List<FrameId> returnedFrameIds;

  final int destinationStartIndex;

  bool get isCrossLayer => targetBefore != null;

  /// The cels the move carries from one row onto the other ([CelRekey]):
  /// [movedFrameIds] onto the target and [returnedFrameIds] back — none for
  /// a slide along one row. The release re-keys them; until then the drag
  /// shows each in its own row's pixels.
  List<CelRekey> get rekeys => [
    if (targetAfter case final target?) ...[
      for (final frameId in movedFrameIds)
        (from: sourceAfter.id, to: target.id, frameId: frameId),
      for (final frameId in returnedFrameIds)
        (from: target.id, to: sourceAfter.id, frameId: frameId),
    ],
  ];
}

/// Plans moving EVERY drawing block inside [rangeStartIndex,
/// rangeEndIndexExclusive) on [source] by [frameDelta] frames onto [target]
/// ([target] == [source] for a plain slide) as ONE RIGID GROUP (relative
/// offsets — internal gaps included — are preserved). The UI-R8 range move:
/// the selection is block-snapped, so the range always holds whole blocks.
/// A whole-block drag (R10-④b) is the range of exactly that block — the
/// round-8 audit (2026-09-06) retired the one-block planner that had
/// written this same sequence (link check → cel collection → pushed
/// landing → rebuild of both layers) a second time.
///
/// Returns null when the move is impossible or a no-op:
///
/// - a SAME-LAYER slide follows the shared rank rule ([planBlockRunMove]):
///   reaching the seat beyond a neighbour reorders, and either way the run
///   re-times inside the free space of the rank it ends up holding. It
///   never pushes anything;
/// - a CROSS-LAYER landing does with the blocks it lands on what [landing]
///   says: a move sends them back to [source] on their own frames
///   ([LandingSwapsThem], F-384); an insertion pushes them out of the way
///   (R12-②, [LandingPushesThem]), cascading, and clamps at the frame-0
///   wall on the way left;
/// - cross-layer moves take the moved cels along, so a cel that an entry
///   OUTSIDE the moved set still references (linked cels) stays put — the
///   move is rejected rather than splitting the link; entries linked WITHIN
///   the range travel together sharing their cel. OUTSIDE is every lane of
///   [sourceBank] too (F-136): a 겸용 cut's row showing the cel keeps it
///   exactly the way a second block on this row does.
///
/// GHOST entries (derived repeat instances) never move and never obstruct:
/// both timelines are planned ghost-free and the caller re-derives repeats
/// afterwards (UI-R20 #5: selections COVER ghosts now).
DrawingBlockMovePlan? planDrawingRangeMove({
  required Layer source,
  required Layer target,
  required int rangeStartIndex,
  required int rangeEndIndexExclusive,
  required int frameDelta,
  required CelBankLanes sourceBank,
  required LandingOnBlocks landing,
  int? cutFrameCount,
}) {
  if (rangeEndIndexExclusive <= rangeStartIndex) {
    return null;
  }
  final sameLayer = source.id == target.id;
  if (sameLayer && frameDelta == 0) {
    return null;
  }

  final sourceBase = ghostFreeTimeline(source);
  final targetBase = sameLayer ? sourceBase : ghostFreeTimeline(target);

  final moved = <TimelineDrawingBlock>[];
  for (final block in drawingBlocks(sourceBase)) {
    if (block.startIndex >= rangeStartIndex &&
        block.endIndexExclusive <= rangeEndIndexExclusive) {
      moved.add(block);
    } else if (block.startIndex < rangeEndIndexExclusive &&
        block.endIndexExclusive > rangeStartIndex) {
      // A partially covered block means the range was not block-snapped.
      return null;
    }
  }
  if (moved.isEmpty) {
    return null;
  }
  // Ghost instances inside the range neither move nor block (UI-R20 #5:
  // selections COVER ghosts now) — the plan is ghost-free above and the
  // caller re-derives the repeats after the slide, so ghosts follow
  // their sources to the landing.

  final groupStart = moved.first.startIndex;
  final groupEndExclusive = moved.last.endIndexExclusive;
  final groupSpan = groupEndExclusive - groupStart;
  final movedStarts = {for (final block in moved) block.startIndex};

  // A same-layer slide is the shared rank rule over the row's blocks. The
  // moved ones are contiguous in that list (a partially covered block was
  // rejected above), which is exactly the run the rule takes.
  if (sameLayer) {
    final blocks = drawingBlocks(sourceBase);
    final runStart = _indexOfBlockStarting(blocks, groupStart);
    final landed = _sameLayerRunMove(
      blocks: blocks,
      runStart: runStart,
      runEnd: runStart + moved.length - 1,
      frameDelta: frameDelta,
      axisStart: layerBlockFloor(source),
      axisEndExclusive: _axisEndFor(source, cutFrameCount),
    );
    if (landed == null) {
      return null;
    }
    return DrawingBlockMovePlan(
      sourceAfter: source.copyWith(timeline: landed.timeline),
      destinationStartIndex: landed.destinationStartIndex,
    );
  }

  // Cross-layer: the cels travel with the group. A cel referenced from
  // outside the moved set stays put (link preserved — move rejected).
  final movedFrames = <Frame>[];
  final movedFrameIds = <FrameId>[];
  final frameIds = <FrameId>{for (final block in moved) block.frameId};
  final sourceTimeline = SplayTreeMap<int, TimelineExposure>.of(sourceBase);
  for (final start in movedStarts) {
    sourceTimeline.remove(start);
  }
  // Read the ghost-FREE base: derived repeat/hold ghosts share the moved
  // block's frameId but are not real links — counting them here voided
  // every cross-row move of a repeat/hold-edge block (UI-R23 #5).
  //
  // 🚨F-136: and read EVERY lane of the source's bank — this row's own
  // without the moved blocks, and each 겸용 sibling's.
  for (final frameId in frameIds) {
    if (sourceBank.exposes(frameId, lane: sourceTimeline)) {
      return null;
    }
  }
  for (final frameId in frameIds) {
    Frame? frame;
    frame = source.frameById(frameId);
    if (frame == null) {
      return null;
    }
    movedFrames.add(frame);
    movedFrameIds.add(frameId);
  }

  final landed = switch (landing) {
    LandingPushesThem() => _landPushing(
      targetBase,
      moved: moved,
      requestedStart: groupStart + frameDelta,
      movedLength: groupSpan,
      pushRight: frameDelta >= 0,
      // Leftward drops clamp against the frame-0 wall, and never land RIGHT
      // of where the group came from (a leftward drag must not teleport it
      // forward).
      leftwardCap: math.max(0, groupStart),
    ),
    LandingSwapsThem(:final bank) => _landSwapping(
      targetBase,
      moved: moved,
      destStart: math.max(0, groupStart + frameDelta),
      target: target,
      bank: bank,
    ),
  };
  if (landed == null) {
    return null;
  }
  final (:destStart, :timeline, :returned, :returnedBlocks) = landed;

  final movedFrameIdSet = {for (final id in movedFrameIds) id};
  final returnedIds = {for (final frame in returned) frame.id};
  return DrawingBlockMovePlan(
    sourceAfter: source.copyWith(
      timeline: timelineTakingBack(sourceTimeline, returnedBlocks),
      frames: [
        for (final frame in source.frames)
          if (!movedFrameIdSet.contains(frame.id)) frame,
        ...returned,
      ],
    ),
    targetBefore: target,
    targetAfter: target.copyWith(
      timeline: timeline,
      frames: [
        for (final frame in target.frames)
          if (!returnedIds.contains(frame.id)) frame,
        ...movedFrames,
      ],
    ),
    movedFrameIds: movedFrameIds,
    returnedFrameIds: [for (final frame in returned) frame.id],
    destinationStartIndex: destStart,
  );
}

/// A cross-layer landing: where the group starts, the target's timeline
/// with it laid in, and the target's blocks it sent back with their cels.
typedef _Landed = ({
  int destStart,
  SplayTreeMap<int, TimelineExposure> timeline,
  List<TimelineDrawingBlock> returnedBlocks,
  List<Frame> returned,
});

/// [moved] laid on [targetBase] from [requestedStart], the blocks there
/// pushed aside ([_resolvePushedLanding]) — an insertion's landing. Null
/// when nowhere takes it.
_Landed? _landPushing(
  SplayTreeMap<int, TimelineExposure> targetBase, {
  required List<TimelineDrawingBlock> moved,
  required int requestedStart,
  required int movedLength,
  required bool pushRight,
  required int leftwardCap,
}) {
  final resolved = _resolvePushedLanding(
    others: drawingBlocks(targetBase),
    requestedStart: requestedStart,
    movedLength: movedLength,
    pushRight: pushRight,
    leftwardCap: leftwardCap,
  );
  if (resolved == null) {
    return null;
  }
  final (:destStart, :pushes) = resolved;
  final timeline = _timelineWithPushes(targetBase, pushes);
  final groupStart = moved.first.startIndex;
  for (final block in moved) {
    timeline[destStart + (block.startIndex - groupStart)] = block.entry;
  }
  return (
    destStart: destStart,
    timeline: timeline,
    returnedBlocks: const [],
    returned: const [],
  );
}

/// [moved] laid on [targetBase] from [destStart], and every block of
/// [target] they land on sent back ([blocksLandedOn]) — a move's landing
/// (F-384). Null when a cel sent back is one another lane of [bank] still
/// shows: the move would split the link (F-136).
_Landed? _landSwapping(
  SplayTreeMap<int, TimelineExposure> targetBase, {
  required List<TimelineDrawingBlock> moved,
  required int destStart,
  required Layer target,
  required CelBankLanes bank,
}) {
  final groupStart = moved.first.startIndex;
  final spans = [
    for (final block in moved)
      (
        start: destStart + (block.startIndex - groupStart),
        length: block.length,
      ),
  ];
  final landedOn = blocksLandedOn(drawingBlocks(targetBase), spans);
  final timeline = SplayTreeMap<int, TimelineExposure>.of(targetBase);
  for (final block in landedOn) {
    timeline.remove(block.startIndex);
  }
  final returned = <Frame>[];
  for (final frameId in {for (final block in landedOn) block.frameId}) {
    final frame = target.frameById(frameId);
    if (frame == null || bank.exposes(frameId, lane: timeline)) {
      return null;
    }
    returned.add(frame);
  }
  for (final (position, block) in moved.indexed) {
    timeline[spans[position].start] = block.entry;
  }
  return (
    destStart: destStart,
    timeline: timeline,
    returnedBlocks: landedOn,
    returned: returned,
  );
}

/// The index of the block starting at [startIndex] in [blocks].
int _indexOfBlockStarting(List<TimelineDrawingBlock> blocks, int startIndex) {
  for (var index = 0; index < blocks.length; index += 1) {
    if (blocks[index].startIndex == startIndex) {
      return index;
    }
  }
  throw ArgumentError.value(
    startIndex,
    'startIndex',
    'No drawing block starts there.',
  );
}

/// A same-layer slide of `blocks[runStart..runEnd]`, under the shared rank
/// rule. Null when the run does not move at all.
///
/// The row's blocks become slots — each carrying the empty space in front
/// of it — so the whole timeline is REBUILT from the resulting layout
/// rather than patched. That is what lets the reorder case exist: a
/// permutation has no "how far did it shift" to patch with.
({SplayTreeMap<int, TimelineExposure> timeline, int destinationStartIndex})?
_sameLayerRunMove({
  required List<TimelineDrawingBlock> blocks,
  required int runStart,
  required int runEnd,
  required int frameDelta,
  int axisStart = 0,
  int? axisEndExclusive,
}) {
  final lengths = [for (final block in blocks) block.length];
  // Planned from [axisStart]: the axis has no room in front of it.
  final gaps = leadingGapsOf(
    starts: [for (final block in blocks) block.startIndex - axisStart],
    lengths: lengths,
  );
  final slots = <BlockMoveSlot>[
    for (var index = 0; index < blocks.length; index += 1)
      (leadingGap: gaps[index], length: lengths[index]),
  ];

  final layout = planBlockRunMove(
    slots: slots,
    runStart: runStart,
    runEnd: runEnd,
    frameDelta: frameDelta,
    axisEndExclusive: axisEndExclusive == null
        ? null
        : axisEndExclusive - axisStart,
  );
  final destinationStartIndex = axisStart + layout.startOf(runStart);
  if (!layout.isReorder &&
      destinationStartIndex == blocks[runStart].startIndex) {
    return null;
  }

  final timeline = SplayTreeMap<int, TimelineExposure>();
  for (var position = 0; position < layout.order.length; position += 1) {
    timeline[axisStart + layout.starts[position]] =
        blocks[layout.order[position]].entry;
  }
  return (timeline: timeline, destinationStartIndex: destinationStartIndex);
}

typedef _Push = ({TimelineDrawingBlock block, int newStart});

/// Where a CROSS-LAYER drop lands and which of the target's blocks it
/// shoves aside. Only blocks the landing actually touches move.
///
/// Rightward ([pushRight]): the landing is exactly [requestedStart]; the
/// shoved blocks shift to later frames, gaps between them absorbing first
/// — the frame axis is endless, so this always succeeds.
///
/// Leftward: blocks ahead are pushed toward frame 0, each one's own gap
/// absorbing before the wave reaches the next. When the chain hits the
/// wall the landing CLAMPS to the nearest feasible start at or above
/// [requestedStart] (never above [leftwardCap]); null when even the cap
/// cannot host the block leftward-style — the caller treats that as an
/// unchanged landing.
({int destStart, List<_Push> pushes})? _resolvePushedLanding({
  required List<TimelineDrawingBlock> others,
  required int requestedStart,
  required int movedLength,
  required bool pushRight,
  required int leftwardCap,
}) {
  if (pushRight) {
    final destStart = math.max(0, requestedStart);
    // The push every insertion on either axis makes
    // ([startsClearingFrontier]).
    final reached = [
      for (final block in others)
        if (block.endIndexExclusive > destStart) block,
    ];
    final starts = startsClearingFrontier([
      for (final block in reached)
        (start: block.startIndex, length: block.length),
    ], frontier: destStart + movedLength);
    final pushes = <_Push>[
      for (final (position, block) in reached.indexed)
        if (starts[position] != block.startIndex)
          (block: block, newStart: starts[position]),
    ];
    return (destStart: destStart, pushes: pushes);
  }

  // One leftward attempt: the pushes when the chain fits, or the deficit
  // (how far below frame 0 the deepest pushed block lands). Raising the
  // landing by d raises every chained position by AT MOST d, so the
  // deficit is an exact lower bound on the required raise — jumping by it
  // never skips a feasible landing.
  (List<_Push>?, int) tryLeftward(int destStart) {
    final pushes = <_Push>[];
    var frontier = destStart;
    for (final block in others.reversed) {
      if (block.startIndex >= destStart + movedLength) {
        continue;
      }
      final newStart = math.min(block.startIndex, frontier - block.length);
      if (newStart < 0) {
        return (null, -newStart);
      }
      if (newStart != block.startIndex) {
        pushes.add((block: block, newStart: newStart));
        frontier = newStart;
      } else {
        // Untouched — everything further left is even further away.
        break;
      }
    }
    return (pushes, 0);
  }

  var destStart = math.max(0, requestedStart);
  while (destStart <= leftwardCap) {
    final (pushes, deficit) = tryLeftward(destStart);
    if (pushes != null) {
      return (destStart: destStart, pushes: pushes);
    }
    destStart += deficit;
  }
  return null;
}

/// [targetBase] with the pushed blocks re-glued at their new starts — the
/// landing step both block plans share (the audit's clone scan,
/// 2026-09-03); the caller then lays its moved entries in.
SplayTreeMap<int, TimelineExposure> _timelineWithPushes(
  Map<int, TimelineExposure> targetBase,
  List<_Push> pushes,
) {
  final timeline = SplayTreeMap<int, TimelineExposure>.of(targetBase);
  for (final push in pushes) {
    timeline.remove(push.block.startIndex);
  }
  for (final push in pushes) {
    timeline[push.newStart] = push.block.entry;
  }
  return timeline;
}

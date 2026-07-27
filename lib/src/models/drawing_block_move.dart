import 'dart:collection';
import 'dart:math' as math;

import 'block_run_move.dart';
import 'frame.dart';
import 'frame_id.dart';
import 'layer.dart';
import 'layer_kind.dart';
import 'timeline_coverage.dart';
import 'timeline_exposure.dart';

/// Where the axis stops for [layer]'s blocks, given the cut is
/// [cutFrameCount] frames long — or null when nothing stops them.
///
/// A row that TILES its cut lives inside it (the storyboard's), so its last
/// block may not slide past the cut's end: coverage would stop making a
/// panel for it and the drawing would drop off the conte while staying in
/// the file. Every other row may sit past the end, which is data the cut
/// simply does not show.
int? _axisEndFor(Layer layer, int? cutFrameCount) =>
    layerKindCoversWithoutGaps(layer.kind) ? cutFrameCount : null;

/// The resolved result of a whole-block move drag (R10-④b): the affected
/// layers with the block relocated. Same-layer slides carry only
/// [sourceAfter]; cross-layer moves also carry the target pair and the
/// frame ids whose brush drawings must re-key to the target layer.
class DrawingBlockMovePlan {
  const DrawingBlockMovePlan({
    required this.sourceAfter,
    this.targetBefore,
    this.targetAfter,
    this.movedFrameIds = const [],
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

  final int destinationStartIndex;

  bool get isCrossLayer => targetBefore != null;
}

/// Plans moving the drawing block starting at [blockStartIndex] on [source]
/// by [frameDelta] frames onto [target] ([target] == [source] for a plain
/// slide). Returns null when the move is impossible or a no-op:
///
/// - a SAME-LAYER slide follows the shared rank rule ([planBlockRunMove]):
///   staying in its own free space re-times it, reaching past a
///   neighbour's midpoint reorders instead. It never pushes anything;
/// - a CROSS-LAYER drop pushes the blocks it lands among out of the way
///   (R12-②), cascading, and clamps at the frame-0 wall on the way left;
/// - cross-layer moves take the block's cel along, so a cel that other
///   timeline entries still reference (linked cels) stays put — the move
///   is rejected rather than splitting the link.
DrawingBlockMovePlan? planDrawingBlockMove({
  required Layer source,
  required Layer target,
  required int blockStartIndex,
  required int frameDelta,
  int? cutFrameCount,
}) {
  // Plan on ghost-free timelines: derived repeat/hold ghosts neither move
  // nor obstruct, and (sharing the moved cel's frameId) must never count
  // as an external link — the caller re-derives the run behaviors after
  // the slide (UI-R23 #5, matching planDrawingRangeMove).
  SplayTreeMap<int, TimelineExposure> baseTimeline(Layer layer) {
    final base = SplayTreeMap<int, TimelineExposure>();
    layer.timeline.forEach((index, entry) {
      if (!(entry.isDrawing && entry.ghost)) {
        base[index] = entry;
      }
    });
    return base;
  }

  final sameLayer = source.id == target.id;
  final sourceBase = baseTimeline(source);
  final targetBase = sameLayer ? sourceBase : baseTimeline(target);

  final entry = sourceBase[blockStartIndex];
  if (entry == null || !entry.isDrawing) {
    return null;
  }
  if (sameLayer && frameDelta == 0) {
    return null;
  }
  final length = entry.length!;

  // A same-layer slide is a run of one under the shared rule.
  if (sameLayer) {
    final blocks = drawingBlocks(sourceBase);
    final runIndex = _indexOfBlockStarting(blocks, blockStartIndex);
    final moved = _sameLayerRunMove(
      blocks: blocks,
      runStart: runIndex,
      runEnd: runIndex,
      frameDelta: frameDelta,
      axisEndExclusive: _axisEndFor(source, cutFrameCount),
    );
    if (moved == null) {
      return null;
    }
    return DrawingBlockMovePlan(
      sourceAfter: source.copyWith(timeline: moved.timeline),
      destinationStartIndex: moved.destinationStartIndex,
    );
  }

  // Cross-layer: the cel travels with the block. Linked cels (the same
  // frame exposed by another REAL entry) stay: rejecting keeps the link
  // intact.
  final frameId = entry.frameId!;
  Frame? movedFrame;
  for (final candidate in sourceBase.entries) {
    if (candidate.key != blockStartIndex &&
        candidate.value.isDrawing &&
        candidate.value.frameId == frameId) {
      return null;
    }
  }
  for (final frame in source.frames) {
    if (frame.id == frameId) {
      movedFrame = frame;
      break;
    }
  }
  if (movedFrame == null) {
    return null;
  }

  final resolved = _resolvePushedLanding(
    others: drawingBlocks(targetBase),
    requestedStart: blockStartIndex + frameDelta,
    movedLength: length,
    pushRight: frameDelta >= 0,
    // Leftward drops clamp against the frame-0 wall, and never land RIGHT
    // of where the block came from (a leftward drag must not teleport it
    // forward).
    leftwardCap: math.max(0, blockStartIndex),
  );
  if (resolved == null) {
    return null;
  }
  final (:destStart, :pushes) = resolved;

  SplayTreeMap<int, TimelineExposure> targetTimelineAfter() {
    final timeline = SplayTreeMap<int, TimelineExposure>.of(targetBase);
    for (final push in pushes) {
      timeline.remove(push.block.startIndex);
    }
    for (final push in pushes) {
      timeline[push.newStart] = push.block.entry;
    }
    timeline[destStart] = entry;
    return timeline;
  }

  final sourceTimeline = SplayTreeMap<int, TimelineExposure>.of(sourceBase)
    ..remove(blockStartIndex);
  return DrawingBlockMovePlan(
    sourceAfter: source.copyWith(
      timeline: sourceTimeline,
      frames: [
        for (final frame in source.frames)
          if (frame.id != frameId) frame,
      ],
    ),
    targetBefore: target,
    targetAfter: target.copyWith(
      timeline: targetTimelineAfter(),
      frames: [...target.frames, movedFrame],
    ),
    movedFrameIds: [frameId],
    destinationStartIndex: destStart,
  );
}

/// Plans moving EVERY drawing block inside [rangeStartIndex,
/// rangeEndIndexExclusive) on [source] by [frameDelta] frames onto [target]
/// as ONE RIGID GROUP (relative offsets — internal gaps included — are
/// preserved). The UI-R8 range move: the selection is block-snapped, so
/// the range always holds whole blocks.
///
/// Same rules as [planDrawingBlockMove], applied group-wise:
/// - a same-layer slide follows the shared rank rule ([planBlockRunMove]):
///   free space re-times, a neighbour's midpoint reorders, nothing is
///   pushed;
/// - cross-layer moves carry the moved cels; a cel referenced by an entry
///   OUTSIDE the moved set stays (rejected) to keep links intact — entries
///   linked WITHIN the range travel together sharing their cel.
///
/// GHOST entries (derived repeat instances) never move and never obstruct:
/// both timelines are planned ghost-free and the caller re-derives repeats
/// afterwards. A range intersecting a ghost is rejected outright.
DrawingBlockMovePlan? planDrawingRangeMove({
  required Layer source,
  required Layer target,
  required int rangeStartIndex,
  required int rangeEndIndexExclusive,
  required int frameDelta,
  int? cutFrameCount,
}) {
  if (rangeEndIndexExclusive <= rangeStartIndex) {
    return null;
  }
  final sameLayer = source.id == target.id;
  if (sameLayer && frameDelta == 0) {
    return null;
  }

  // Plan on ghost-free timelines: derived entries neither move nor block.
  SplayTreeMap<int, TimelineExposure> baseTimeline(Layer layer) {
    final base = SplayTreeMap<int, TimelineExposure>();
    layer.timeline.forEach((index, entry) {
      if (!(entry.isDrawing && entry.ghost)) {
        base[index] = entry;
      }
    });
    return base;
  }

  final sourceBase = baseTimeline(source);
  final targetBase = sameLayer ? sourceBase : baseTimeline(target);

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
  // Read the ghost-FREE base: derived repeat/hold ghosts share the moved
  // block's frameId but are not real links — counting them here voided
  // every cross-row move of a repeat/hold-edge block (UI-R23 #5).
  for (final candidate in sourceBase.entries) {
    if (movedStarts.contains(candidate.key)) {
      continue;
    }
    final entry = candidate.value;
    if (entry.isDrawing && frameIds.contains(entry.frameId)) {
      return null;
    }
  }
  for (final frameId in frameIds) {
    Frame? frame;
    for (final candidate in source.frames) {
      if (candidate.id == frameId) {
        frame = candidate;
        break;
      }
    }
    if (frame == null) {
      return null;
    }
    movedFrames.add(frame);
    movedFrameIds.add(frameId);
  }

  final resolved = _resolvePushedLanding(
    others: drawingBlocks(targetBase),
    requestedStart: groupStart + frameDelta,
    movedLength: groupSpan,
    pushRight: frameDelta >= 0,
    leftwardCap: math.max(0, groupStart),
  );
  if (resolved == null) {
    return null;
  }
  final (:destStart, :pushes) = resolved;

  SplayTreeMap<int, TimelineExposure> targetTimelineAfter() {
    final timeline = SplayTreeMap<int, TimelineExposure>.of(targetBase);
    for (final push in pushes) {
      timeline.remove(push.block.startIndex);
    }
    for (final push in pushes) {
      timeline[push.newStart] = push.block.entry;
    }
    for (final block in moved) {
      timeline[destStart + (block.startIndex - groupStart)] = block.entry;
    }
    return timeline;
  }

  final movedFrameIdSet = {for (final id in movedFrameIds) id};
  final sourceTimeline = SplayTreeMap<int, TimelineExposure>.of(sourceBase);
  for (final start in movedStarts) {
    sourceTimeline.remove(start);
  }
  return DrawingBlockMovePlan(
    sourceAfter: source.copyWith(
      timeline: sourceTimeline,
      frames: [
        for (final frame in source.frames)
          if (!movedFrameIdSet.contains(frame.id)) frame,
      ],
    ),
    targetBefore: target,
    targetAfter: target.copyWith(
      timeline: targetTimelineAfter(),
      frames: [...target.frames, ...movedFrames],
    ),
    movedFrameIds: movedFrameIds,
    destinationStartIndex: destStart,
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
  int? axisEndExclusive,
}) {
  final slots = <BlockMoveSlot>[];
  var previousEnd = 0;
  for (final block in blocks) {
    slots.add((
      leadingGap: block.startIndex - previousEnd,
      length: block.length,
    ));
    previousEnd = block.endIndexExclusive;
  }

  final layout = planBlockRunMove(
    slots: slots,
    runStart: runStart,
    runEnd: runEnd,
    frameDelta: frameDelta,
    axisEndExclusive: axisEndExclusive,
  );
  final destinationStartIndex = layout.startOf(runStart);
  if (!layout.isReorder &&
      destinationStartIndex == blocks[runStart].startIndex) {
    return null;
  }

  final timeline = SplayTreeMap<int, TimelineExposure>();
  for (var position = 0; position < layout.order.length; position += 1) {
    timeline[layout.starts[position]] = blocks[layout.order[position]].entry;
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
    final pushes = <_Push>[];
    var frontier = destStart + movedLength;
    for (final block in others) {
      if (block.endIndexExclusive <= destStart) {
        continue;
      }
      final newStart = math.max(block.startIndex, frontier);
      frontier = newStart + block.length;
      if (newStart != block.startIndex) {
        pushes.add((block: block, newStart: newStart));
      }
    }
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

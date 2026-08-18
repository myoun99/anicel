import 'dart:collection';
import 'dart:math' as math;

import 'frame_id.dart';
import 'layer.dart';
import 'timeline_coverage.dart' show coveringDrawingBlockAt;
import 'timeline_exposure.dart';

/// Which edge of a glued run a [TimelineRunBehavior] hangs off.
enum TimelineRunEdgeSide {
  start,
  end;

  String toJson() => name;

  static TimelineRunEdgeSide fromJson(Object? value) => switch (value) {
    'start' => TimelineRunEdgeSide.start,
    'end' => TimelineRunEdgeSide.end,
    _ => throw FormatException('Unknown run edge side: $value'),
  };
}

/// What a run edge does with the free space next to it. `None` is the
/// absence of a behavior — never stored.
enum TimelineRunEdgeMode {
  /// The edge's drawing holds as ONE dim ghost block to the cut boundary.
  hold,

  /// The pattern (a selection-defined span or the whole run) cycles into
  /// the free space to the cut boundary.
  repeat;

  String toJson() => name;

  static TimelineRunEdgeMode fromJson(Object? value) => switch (value) {
    'hold' => TimelineRunEdgeMode.hold,
    'repeat' => TimelineRunEdgeMode.repeat,
    _ => throw FormatException('Unknown run edge mode: $value'),
  };
}

/// A run-edge property (UI-R9 #10, TVP-style N/H/R): a persistent LIVE
/// spec on the layer — one per (run, side), set through the edge tag.
///
/// The behavior stores no ghost entries and no frame count: it names WHAT
/// ([anchorFrameId] = identity of a block inside the run; the LIVE glued
/// run containing it is the unit) and HOW ([mode] + optional
/// [patternAnchorFrameId] for selection-scoped repeat patterns). The
/// ghosts always fill to the cut boundary; [rederiveRunBehaviors] wipes
/// and re-synthesizes them after every timeline edit and every cut
/// duration change, so the tail/lead-in re-arranges automatically (live
/// sync, and the ghost-glue guarantee: the pattern IS the current run, a
/// comma shrink can never open a gap). A vanished anchor drops the
/// behavior (self-healing).
class TimelineRunBehavior {
  const TimelineRunBehavior({
    required this.anchorFrameId,
    required this.side,
    required this.mode,
    this.patternAnchorFrameId,
  });

  /// Identity of the run: a frameId of one of its blocks (the run's first
  /// block at creation). Resolved to its lowest non-ghost index on
  /// rederive; the glued run containing that block is the behavior's run.
  final FrameId anchorFrameId;

  final TimelineRunEdgeSide side;
  final TimelineRunEdgeMode mode;

  /// Repeat with a selection: the block bounding the pattern span.
  /// - [TimelineRunEdgeSide.end]: the pattern runs from THIS block's start
  ///   to the run end (the run's last block is always included).
  /// - [TimelineRunEdgeSide.start]: the pattern runs from the run start to
  ///   THIS block's end (the first block is always included).
  /// Null (or no longer resolvable inside the run) = the whole run.
  final FrameId? patternAnchorFrameId;

  /// The marker stamped on ghost entries this behavior owns
  /// ([TimelineExposure.ghostOwnerId]).
  String get ghostOwnerId => '${anchorFrameId.value}:${side.name}';

  Map<String, dynamic> toJson() => {
    'anchor': anchorFrameId.toJson(),
    'side': side.toJson(),
    'mode': mode.toJson(),
    if (patternAnchorFrameId != null)
      'patternAnchor': patternAnchorFrameId!.toJson(),
  };

  factory TimelineRunBehavior.fromJson(Map<String, dynamic> json) =>
      TimelineRunBehavior(
        anchorFrameId: FrameId.fromJson(json['anchor'] as Map<String, dynamic>),
        side: TimelineRunEdgeSide.fromJson(json['side']),
        mode: TimelineRunEdgeMode.fromJson(json['mode']),
        patternAnchorFrameId: json['patternAnchor'] == null
            ? null
            : FrameId.fromJson(json['patternAnchor'] as Map<String, dynamic>),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineRunBehavior &&
          other.anchorFrameId == anchorFrameId &&
          other.side == side &&
          other.mode == mode &&
          other.patternAnchorFrameId == patternAnchorFrameId;

  @override
  int get hashCode =>
      Object.hash(anchorFrameId, side, mode, patternAnchorFrameId);

  @override
  String toString() =>
      'TimelineRunBehavior(anchor: $anchorFrameId, side: ${side.name}, '
      'mode: ${mode.name}'
      '${patternAnchorFrameId == null ? '' : ', pattern: $patternAnchorFrameId'})';
}

typedef _Run = ({int startIndex, int endIndexExclusive, FrameId anchorFrameId});

/// Re-derives every run behavior's ghost entries from the CURRENT base
/// timeline — THE live-sync engine (UI-R8 repeat regions rebuilt as UI-R9
/// edge properties). Pure: returns [layer] itself when nothing changes
/// (identity matters for the grid's memo gates).
///
/// Pass order:
/// 1. Strip every ghost entry (derived state, never authored).
/// 2. Behaviors resolve to their LIVE glued run (anchor block's run;
///    missing anchor drops the behavior) and dedupe per (run, side) — the
///    LAST spec in list order wins (most recently set).
/// 3. Application in run order, start side before end side. End side:
///    hold = one ghost of the run's last frameId filling to the cut end;
///    repeat = the pattern span cycling to the cut end. Start side is the
///    mirror, ghosts FLUSH-aligned to the run start (a partial lead-in
///    shows the pattern's tail). Ghosts clamp against authored entries and
///    earlier behaviors' ghosts — derived frames never displace real ones.
/// 4. A fully occluded behavior stays kept (spec survives until room
///    opens up again).
Layer rederiveRunBehaviors(Layer layer, {required int cutFrameCount}) {
  final hasGhosts = layer.timeline.values.any((entry) => entry.ghost);
  if (layer.runBehaviors.isEmpty && !hasGhosts) {
    return layer;
  }

  final base = SplayTreeMap<int, TimelineExposure>();
  layer.timeline.forEach((index, entry) {
    if (!entry.ghost) {
      base[index] = entry;
    }
  });

  int? anchorStartOf(FrameId frameId) {
    for (final entry in base.entries) {
      if (entry.value.frameId == frameId) {
        return entry.key;
      }
    }
    return null;
  }

  _Run runAt(int blockStartIndex) {
    final blocks = [
      for (final entry in base.entries)
        (start: entry.key, endExclusive: entry.key + entry.value.length!),
    ];
    var index = blocks.indexWhere((block) => block.start == blockStartIndex);
    var first = index;
    while (first > 0 && blocks[first - 1].endExclusive == blocks[first].start) {
      first -= 1;
    }
    var last = index;
    while (last < blocks.length - 1 &&
        blocks[last].endExclusive == blocks[last + 1].start) {
      last += 1;
    }
    return (
      startIndex: blocks[first].start,
      endIndexExclusive: blocks[last].endExclusive,
      anchorFrameId: base[blocks[first].start]!.frameId!,
    );
  }

  // Resolve + dedupe: one behavior per (run, side), the LAST wins.
  final byEdge =
      <
        (int, TimelineRunEdgeSide),
        ({TimelineRunBehavior behavior, _Run run})
      >{};
  for (final behavior in layer.runBehaviors) {
    final anchorStart = anchorStartOf(behavior.anchorFrameId);
    if (anchorStart == null) {
      continue; // Anchor vanished — the behavior drops (self-healing).
    }
    final run = runAt(anchorStart);
    byEdge[(run.startIndex, behavior.side)] = (behavior: behavior, run: run);
  }
  final resolved = byEdge.values.toList()
    ..sort((a, b) {
      // HOLDS apply before REPEATS (UI-R13 #5): a repeat's default
      // pattern is the DISPLAYED run including the opposite edge's hold
      // ghosts, so every hold must sit in the result first. Within a
      // mode: run order, start side before end side.
      final byMode =
          (a.behavior.mode == TimelineRunEdgeMode.hold ? 0 : 1) -
          (b.behavior.mode == TimelineRunEdgeMode.hold ? 0 : 1);
      if (byMode != 0) {
        return byMode;
      }
      final byRun = a.run.startIndex.compareTo(b.run.startIndex);
      if (byRun != 0) {
        return byRun;
      }
      return (a.behavior.side == TimelineRunEdgeSide.start ? 0 : 1) -
          (b.behavior.side == TimelineRunEdgeSide.start ? 0 : 1);
    });

  final result = SplayTreeMap<int, TimelineExposure>.of(base);
  final kept = <TimelineRunBehavior>[];

  TimelineExposure ghostEntry({
    required FrameId frameId,
    required int length,
    required String ownerId,
    List<int> dots = const [],
  }) {
    var ghost = TimelineExposure.drawing(
      frameId,
      length: length,
      ghost: true,
      ghostOwnerId: ownerId,
    );
    if (dots.isNotEmpty) {
      // copyWith clamps the dots to the (possibly shorter) ghost length.
      ghost = ghost.copyWith(breakdownOffsets: dots);
    }
    return ghost;
  }

  for (final item in resolved) {
    final behavior = item.behavior;
    final run = item.run;
    kept.add(behavior);

    if (behavior.side == TimelineRunEdgeSide.end) {
      final ghostStart = run.endIndexExclusive;
      // Fill limit: the cut end, or the next occupied index (an authored
      // entry or an earlier behavior's ghosts) — whichever comes first.
      var limit = cutFrameCount;
      final nextKey = result.firstKeyAfter(ghostStart - 1);
      if (nextKey != null && nextKey < limit) {
        limit = nextKey;
      }
      if (limit <= ghostStart) {
        continue; // Occluded right now; the spec survives.
      }

      if (behavior.mode == TimelineRunEdgeMode.hold) {
        final lastBlockKey = result.lastKeyBefore(ghostStart)!;
        result[ghostStart] = ghostEntry(
          frameId: result[lastBlockKey]!.frameId!,
          length: limit - ghostStart,
          ownerId: behavior.ghostOwnerId,
        );
        continue;
      }

      // Repeat: pattern span [patternStart, run end).
      var patternStart = run.startIndex;
      final patternAnchor = behavior.patternAnchorFrameId;
      if (patternAnchor != null) {
        final key = anchorStartOf(patternAnchor);
        if (key != null &&
            key >= run.startIndex &&
            key < run.endIndexExclusive) {
          patternStart = key;
        }
      } else {
        // UI-R13 #5: the DEFAULT pattern is the DISPLAYED run — a
        // front-hold lead-in abutting the run start joins the repeated
        // unit (holds applied first, so its ghost already sits here).
        final startEdge = byEdge[(run.startIndex, TimelineRunEdgeSide.start)];
        if (startEdge != null &&
            startEdge.behavior.mode == TimelineRunEdgeMode.hold) {
          final leadKey = result.lastKeyBefore(run.startIndex);
          if (leadKey != null) {
            final lead = result[leadKey]!;
            if (lead.ghost &&
                lead.ghostOwnerId == startEdge.behavior.ghostOwnerId &&
                leadKey + lead.length! == run.startIndex) {
              patternStart = leadKey;
            }
          }
        }
      }
      final span = run.endIndexExclusive - patternStart;
      final parts = [
        // From RESULT, not base: the pattern may include this run's own
        // front-hold ghost (UI-R13 #5); inside the run the two agree.
        for (final entry in result.entries)
          if (entry.key >= patternStart && entry.key < run.endIndexExclusive)
            (
              offset: entry.key - patternStart,
              frameId: entry.value.frameId!,
              length: entry.value.length!,
              dots: entry.value.breakdownOffsets,
            ),
      ];
      for (
        var cycleStart = ghostStart;
        cycleStart < limit;
        cycleStart += span
      ) {
        for (final part in parts) {
          final start = cycleStart + part.offset;
          if (start >= limit) {
            break;
          }
          result[start] = ghostEntry(
            frameId: part.frameId,
            length: part.length.clamp(1, limit - start),
            ownerId: behavior.ghostOwnerId,
            dots: part.dots,
          );
        }
      }
      continue;
    }

    // Start side: fill [limitStart, run start), flush-aligned to the run.
    final runStart = run.startIndex;
    var limitStart = 0;
    final previousKey = result.lastKeyBefore(runStart);
    if (previousKey != null) {
      limitStart = math.max(0, previousKey + result[previousKey]!.length!);
    }
    if (limitStart >= runStart) {
      continue; // Occluded; the spec survives.
    }

    if (behavior.mode == TimelineRunEdgeMode.hold) {
      result[limitStart] = ghostEntry(
        frameId: base[runStart]!.frameId!,
        length: runStart - limitStart,
        ownerId: behavior.ghostOwnerId,
      );
      continue;
    }

    // Repeat: pattern span [run start, patternEnd).
    var patternEnd = run.endIndexExclusive;
    final patternAnchor = behavior.patternAnchorFrameId;
    if (patternAnchor != null) {
      final key = anchorStartOf(patternAnchor);
      if (key != null && key >= runStart && key < run.endIndexExclusive) {
        patternEnd = key + base[key]!.length!;
      }
    } else {
      // UI-R13 #5 (the mirror): a rear-hold tail abutting the run end
      // joins the repeated unit — the front repeat cycles the DISPLAYED
      // run, hold included.
      final endEdge = byEdge[(run.startIndex, TimelineRunEdgeSide.end)];
      if (endEdge != null &&
          endEdge.behavior.mode == TimelineRunEdgeMode.hold) {
        final rear = result[run.endIndexExclusive];
        if (rear != null &&
            rear.ghost &&
            rear.ghostOwnerId == endEdge.behavior.ghostOwnerId) {
          patternEnd = run.endIndexExclusive + rear.length!;
        }
      }
    }
    final span = patternEnd - runStart;
    final parts = [
      // From RESULT, not base: the pattern may include this run's own
      // rear-hold ghost (UI-R13 #5); inside the run the two agree.
      for (final entry in result.entries)
        if (entry.key >= runStart && entry.key < patternEnd)
          (
            offset: entry.key - runStart,
            frameId: entry.value.frameId!,
            length: math.min(entry.value.length!, patternEnd - entry.key),
            dots: entry.value.breakdownOffsets,
          ),
    ];
    // Tile leftward from the run start; the leftmost partial cycle keeps
    // the pattern's TAIL (lead-in alignment).
    for (
      var cycleStart = runStart - span;
      cycleStart + span > limitStart;
      cycleStart -= span
    ) {
      for (final part in parts) {
        var start = cycleStart + part.offset;
        final end = start + part.length;
        if (end <= limitStart) {
          continue; // Fully cut off by the boundary.
        }
        var dots = part.dots;
        if (start < limitStart) {
          // Clip the straddling lead-in part: keep its visible tail.
          final shift = limitStart - start;
          dots = [for (final dot in part.dots) dot - shift];
          start = limitStart;
        }
        result[start] = ghostEntry(
          frameId: part.frameId,
          length: end - start,
          ownerId: behavior.ghostOwnerId,
          dots: dots,
        );
      }
    }
  }

  final behaviorsUnchanged =
      kept.length == layer.runBehaviors.length &&
      () {
        for (var i = 0; i < kept.length; i += 1) {
          if (kept[i] != layer.runBehaviors[i]) {
            return false;
          }
        }
        return true;
      }();
  final timelineUnchanged =
      result.length == layer.timeline.length &&
      () {
        for (final entry in result.entries) {
          if (layer.timeline[entry.key] != entry.value) {
            return false;
          }
        }
        return true;
      }();
  if (behaviorsUnchanged && timelineUnchanged) {
    return layer;
  }
  return layer.copyWith(timeline: result, runBehaviors: kept);
}

/// The contiguous GLUED run of non-ghost drawing blocks containing the
/// block at [blockStartIndex] (UI-R8: the run-edge handles' unit —
/// "연결된 블록들"): expands in both directions while neighbours touch
/// (next.start == prev.endExclusive). Null when no non-ghost block starts
/// there.
({int startIndex, int endIndexExclusive, FrameId anchorFrameId})? gluedRunAt(
  Layer layer,
  int blockStartIndex,
) => gluedRunsByBlockStart(layer)[blockStartIndex];

/// EVERY glued run in [layer], keyed by each member block's start index.
///
/// [gluedRunAt] answers for one block and rebuilds the block list to do it,
/// so asking it once per block — which is what resolving a row's run-edge
/// chrome does — was O(n²) with an allocation per block. Callers that want
/// more than one run resolve them all in a single pass through this and index
/// the result.
Map<int, ({int startIndex, int endIndexExclusive, FrameId anchorFrameId})>
gluedRunsByBlockStart(Layer layer) {
  final blocks = [
    for (final key in layer.timeline.keys)
      if (layer.timeline[key]!.isDrawing && !layer.timeline[key]!.ghost)
        (start: key, endExclusive: key + layer.timeline[key]!.length!),
  ];
  final runs =
      <int, ({int startIndex, int endIndexExclusive, FrameId anchorFrameId})>{};
  var first = 0;
  while (first < blocks.length) {
    var last = first;
    while (last < blocks.length - 1 &&
        blocks[last].endExclusive == blocks[last + 1].start) {
      last += 1;
    }
    final run = (
      startIndex: blocks[first].start,
      endIndexExclusive: blocks[last].endExclusive,
      anchorFrameId: layer.timeline[blocks[first].start]!.frameId!,
    );
    for (var member = first; member <= last; member += 1) {
      runs[blocks[member].start] = run;
    }
    first = last + 1;
  }
  return runs;
}

/// The behavior set on [side] of the glued run containing
/// [blockStartIndex]; null when the edge carries none (None).
TimelineRunBehavior? runEdgeBehaviorAt(
  Layer layer,
  int blockStartIndex,
  TimelineRunEdgeSide side,
) {
  final run = gluedRunAt(layer, blockStartIndex);
  if (run == null) {
    return null;
  }
  return runEdgeBehaviorIn(layer, run, side);
}

/// [runEdgeBehaviorAt] with the run already resolved — the form a caller
/// that walked every run once should use.
TimelineRunBehavior? runEdgeBehaviorIn(
  Layer layer,
  ({int startIndex, int endIndexExclusive, FrameId anchorFrameId}) run,
  TimelineRunEdgeSide side,
) {
  TimelineRunBehavior? found;
  for (final behavior in layer.runBehaviors) {
    if (behavior.side != side) {
      continue;
    }
    // The behavior belongs to this run when its anchor block lives inside.
    for (final entry in layer.timeline.entries) {
      if (entry.value.ghost || entry.value.frameId != behavior.anchorFrameId) {
        continue;
      }
      if (entry.key >= run.startIndex && entry.key < run.endIndexExclusive) {
        found = behavior; // Last spec in list order wins.
      }
      break;
    }
  }
  return found;
}

/// The behavior OWNING the ghost that covers [frameIndex]; null when the
/// cell is not ghost-covered or the owner vanished. The cells painter
/// reads the mode off this (hold ghosts draw ㅡ dashes, repeat ghosts
/// text-only cel names — UI-R10 #11).
TimelineRunBehavior? runBehaviorOwningGhostAt(Layer layer, int frameIndex) {
  String? ownerId;
  final entry = layer.timeline[frameIndex];
  if (entry != null) {
    if (entry.ghost) {
      ownerId = entry.ghostOwnerId;
    }
  } else {
    final coveringKey = layer.timeline.lastKeyBefore(frameIndex);
    if (coveringKey != null) {
      final covering = layer.timeline[coveringKey]!;
      if (covering.ghost && frameIndex < coveringKey + covering.length!) {
        ownerId = covering.ghostOwnerId;
      }
    }
  }
  if (ownerId == null) {
    return null;
  }
  TimelineRunBehavior? found;
  for (final behavior in layer.runBehaviors) {
    if (behavior.ghostOwnerId == ownerId) {
      found = behavior; // Last spec in list order wins (dedupe mirror).
    }
  }
  return found;
}

/// A7① (2026-08-18): the flip's COLUMN at [frame], with HOLD-mode ghost
/// tails and lead-ins absorbed into their owning run — the animator's
/// flip treats a hold as ONE unit (「홀드 블록을 한 단위로 건너뛰어」), and
/// the flip HUD already draws no block where a hold ghost is, so
/// movement and picture agree again.
///
/// The merge is DIRECTIONAL by the behavior's own side: an end-side tail
/// merges leftward into its run, a start-side lead-in rightward — never
/// across the ghost's far edge, so a tail that happens to abut the NEXT
/// authored run does not fuse two runs into one column (the flip must
/// still land there). Glued authored blocks stay separate columns
/// exactly as before, and REPEAT-mode ghosts stay their own columns —
/// A7① names holds only.
({int start, int endExclusive})? holdMergedFlipColumnAt(
  Layer layer,
  int frame,
) {
  final block = coveringDrawingBlockAt(layer.timeline, frame);
  if (block == null) {
    return null;
  }

  bool isHoldGhost(int startIndex, TimelineExposure entry) =>
      entry.ghost &&
      runBehaviorOwningGhostAt(layer, startIndex)?.mode ==
          TimelineRunEdgeMode.hold;
  TimelineRunEdgeSide? holdGhostSide(int startIndex, TimelineExposure entry) =>
      entry.ghost && isHoldGhost(startIndex, entry)
      ? runBehaviorOwningGhostAt(layer, startIndex)!.side
      : null;

  var start = block.startIndex;
  var endExclusive = block.endIndexExclusive;
  // What the span's outermost blocks ARE, for the directional edge rule.
  var leftmostHoldSide = holdGhostSide(block.startIndex, block.entry);
  var rightmostHoldSide = leftmostHoldSide;
  if (block.entry.ghost && leftmostHoldSide == null) {
    // A repeat ghost (or an orphan): its own column, unchanged.
    return (start: start, endExclusive: endExclusive);
  }

  var expanded = true;
  while (expanded) {
    expanded = false;
    // LEFT edge: merge when the neighbour is a lead-in ghost of OUR run
    // (side == start points rightward at us), or when OUR leftmost block
    // is an end-side tail and the neighbour is the authored run it holds.
    final beforeKey = layer.timeline.lastKeyBefore(start);
    if (beforeKey != null) {
      final before = layer.timeline[beforeKey]!;
      if (before.isDrawing && beforeKey + (before.length ?? 1) == start) {
        final beforeHoldSide = holdGhostSide(beforeKey, before);
        final merge =
            beforeHoldSide == TimelineRunEdgeSide.start ||
            (leftmostHoldSide == TimelineRunEdgeSide.end && !before.ghost);
        if (merge) {
          start = beforeKey;
          leftmostHoldSide = beforeHoldSide;
          expanded = true;
        }
      }
    }
    // RIGHT edge: the mirror.
    final after = layer.timeline[endExclusive];
    if (after != null && after.isDrawing) {
      final afterHoldSide = holdGhostSide(endExclusive, after);
      final merge =
          afterHoldSide == TimelineRunEdgeSide.end ||
          (rightmostHoldSide == TimelineRunEdgeSide.start && !after.ghost);
      if (merge) {
        endExclusive = endExclusive + (after.length ?? 1);
        rightmostHoldSide = afterHoldSide;
        expanded = true;
      }
    }
  }
  return (start: start, endExclusive: endExclusive);
}

/// Whether [index] on [layer] falls inside a GHOST exposure (a derived
/// repeat instance) — the timeline cells dim these and the editing
/// affordances (grips, move, run-end handles) stand down on them.
bool timelineIndexIsGhost(Layer layer, int index) {
  final entry = layer.timeline[index];
  if (entry != null) {
    return entry.isDrawing && entry.ghost;
  }
  // Inside a hold: the covering block is the last entry before the index.
  final coveringKey = layer.timeline.lastKeyBefore(index);
  if (coveringKey == null) {
    return false;
  }
  final covering = layer.timeline[coveringKey]!;
  return covering.isDrawing &&
      covering.ghost &&
      index < coveringKey + covering.length!;
}

import 'dart:collection';
import 'dart:math' as math;

import '../core/floor_math.dart';
import 'frame_id.dart';
import 'layer.dart';
import 'timeline_exposure.dart';
import 'timeline_run_behavior.dart';

export 'timeline_run_behavior.dart';

/// A glued run of authored blocks: its span and its blocks' starts, in
/// timeline order.
typedef TimelineGluedRun = ({
  int startIndex,
  int endIndexExclusive,
  List<int> blockStarts,
});

/// One run side's property as a query reads it: the mode, and the start of
/// the block that bounds its selection-scoped pattern (null = the whole run).
typedef TimelineRunEdgeProperty = ({
  TimelineRunEdgeMode mode,
  int? patternBlockStart,
});

/// One run side the rederive applies: the run, the side, and what its
/// blocks resolved to.
typedef _RunEdge = ({
  TimelineGluedRun run,
  TimelineRunEdgeSide side,
  TimelineRunEdgeMode mode,
  int? bound,
});

/// One entry of a repeat pattern, positioned relative to the pattern's own
/// start.
typedef _PatternPart = ({
  int offset,
  FrameId frameId,
  int length,
  List<int> dots,
});

/// A free interval `[lo, hi)` a repeat fills, plus the edge its cycle
/// phase is pinned to. The three travel together because none of them
/// means anything without the other two.
typedef _GhostFill = ({int lo, int hi, int alignAt});

const _startHoldGhost = TimelineRunEdgeGhost(
  side: TimelineRunEdgeSide.start,
  mode: TimelineRunEdgeMode.hold,
);
const _endHoldGhost = TimelineRunEdgeGhost(
  side: TimelineRunEdgeSide.end,
  mode: TimelineRunEdgeMode.hold,
);

/// [layer]'s timeline without its ghosts — the base a block move plans on.
///
/// Derived repeat/hold ghosts neither move nor obstruct, and (sharing the
/// moved cel's frameId) must never count as an external link — the caller
/// re-derives the run behaviors after the slide (UI-R23 #5). Every planner
/// reads this one function — [planDrawingRangeMove], the multi-row planner,
/// [layerWithNewFramesAtRunEdge] and [rederiveRunBehaviors]'s pass 1; until
/// 2026-09-03 each kept its own copy, and the mutation campaign found a copy
/// nobody tested. (The round-8 audit, 2026-09-06, found two more copies the
/// 2026-09-03 unification had stopped short of, and moved the one function
/// here, beside the ghost's only constructor.)
///
/// The rederive pass used to filter on `!entry.ghost` alone; that is the
/// same predicate, because [TimelineExposure.drawing] is the only
/// constructor, so every entry answers `isDrawing`.
SplayTreeMap<int, TimelineExposure> ghostFreeTimeline(Layer layer) {
  final base = SplayTreeMap<int, TimelineExposure>();
  layer.timeline.forEach((index, entry) {
    if (!(entry.isDrawing && entry.ghost)) {
      base[index] = entry;
    }
  });
  return base;
}

/// [timeline]'s glued runs of non-ghost drawing blocks, in timeline order
/// (UI-R8: the run-edge handles' unit — "연결된 블록들": neighbours glue
/// while next.start == prev.endExclusive). The one walk every run question
/// reads.
List<TimelineGluedRun> _gluedRuns(
  SplayTreeMap<int, TimelineExposure> timeline,
) {
  final blocks = [
    for (final entry in timeline.entries)
      if (entry.value.isDrawing && !entry.value.ghost)
        (start: entry.key, endExclusive: entry.key + entry.value.length!),
  ];
  final runs = <TimelineGluedRun>[];
  var first = 0;
  while (first < blocks.length) {
    var last = first;
    while (last < blocks.length - 1 &&
        blocks[last].endExclusive == blocks[last + 1].start) {
      last += 1;
    }
    runs.add((
      startIndex: blocks[first].start,
      endIndexExclusive: blocks[last].endExclusive,
      blockStarts: [for (var i = first; i <= last; i += 1) blocks[i].start],
    ));
    first = last + 1;
  }
  return runs;
}

/// The winning carrier of [side] among a run's [blockStarts], its mode, and
/// the bound it claims — or null when no block carries that side. THE
/// resolution [TimelineRunEdgeMark] describes: the rederive normalizes the
/// marks by it, and every query reads through it.
({int carrier, TimelineRunEdgeMode mode, int? bound})? _resolveRunEdge(
  Map<int, TimelineExposure> timeline,
  List<int> blockStarts,
  TimelineRunEdgeSide side,
) {
  // Inward from the edge: the end side walks back from the run's end, the
  // start side forward from its start — the first carrier met is the one
  // nearest the edge.
  final inward = side == TimelineRunEdgeSide.end
      ? blockStarts.reversed
      : blockStarts;
  int? carrier;
  TimelineRunEdgeMode? mode;
  for (final start in inward) {
    final mark = timeline[start]!.edgeMark(side);
    final found = carrier;
    if (found == null) {
      final carried = mark.mode;
      if (carried == null) {
        continue; // Nearer the edge than every carrier: nobody's bound.
      }
      if (carried != TimelineRunEdgeMode.repeat || mark.bound) {
        return (
          carrier: start,
          mode: carried,
          bound: carried == TimelineRunEdgeMode.repeat ? start : null,
        );
      }
      carrier = start;
      mode = carried;
      continue;
    }
    if (mark.mode != null) {
      break; // Another carrier: every bound past it is its own.
    }
    if (mark.bound) {
      return (carrier: found, mode: mode!, bound: start);
    }
  }
  final found = carrier;
  return found == null ? null : (carrier: found, mode: mode!, bound: null);
}

/// [rederiveRunBehaviors]'s working state — the authored base, the result
/// being written, the run sides resolved from the base's marks — so every
/// pass reads the same sheet and each is a named step. (The audit's
/// 2026-09-03 restructure of one 300-line function; every rule and its
/// comment moved verbatim.)
class _RunBehaviorPass {
  _RunBehaviorPass(this.base, {required this.drawnFrameCount});

  /// Where an end side fills TO: the cut's DRAWN end — its conte 尺 plus
  /// the のりしろ transitions ask of it — not the red line.
  ///
  /// 🗣️F-227 (유저 2026-09-29): 「타임라인패널에서도 홀드같은게 빨간엔드라인에서
  /// 끝나는게아니라 여백엔드라인까지 가도록, 거기가 진짜 엔드라인이라는 느낌」.
  /// A hold is "this picture until the end", and with an O.L the end is where
  /// the cut's material ends: stopping at the conte end left the leaving cut
  /// nothing to show through the second half of its own O.L.
  final int drawnFrameCount;

  /// Pass 1's output: the authored entries alone — their marks normalized
  /// by pass 2 before anything is derived from them.
  final SplayTreeMap<int, TimelineExposure> base;

  /// Pass 3's sheet: the base plus every ghost written so far.
  late final SplayTreeMap<int, TimelineExposure> result =
      SplayTreeMap<int, TimelineExposure>.of(base);

  /// Pass 2's output: every run side some block carries.
  final edges = <_RunEdge>[];

  /// Pass 2: resolve every run side ([_resolveRunEdge]) and strip the marks
  /// the resolution did not pick — a merged run's inner carriers, a bound no
  /// carrier claims — so the base leaves holding one carrier and at most one
  /// bound per run side.
  void resolve() {
    for (final run in _gluedRuns(base)) {
      for (final side in TimelineRunEdgeSide.values) {
        final resolved = _resolveRunEdge(base, run.blockStarts, side);
        for (final start in run.blockStarts) {
          final wanted = TimelineRunEdgeMark(
            mode: start == resolved?.carrier ? resolved?.mode : null,
            bound: start == resolved?.bound,
          );
          final entry = base[start]!;
          if (entry.edgeMark(side) != wanted) {
            base[start] = entry.withEdgeMark(side, wanted);
          }
        }
        if (resolved != null) {
          edges.add((
            run: run,
            side: side,
            mode: resolved.mode,
            bound: resolved.bound,
          ));
        }
      }
    }
  }

  /// The application order: HOLDS apply before REPEATS (UI-R13 #5) — a
  /// repeat's default pattern is the DISPLAYED run including the opposite
  /// edge's hold ghosts, so every hold must sit in the result first. Within
  /// a mode: run order, start side before end side.
  List<_RunEdge> get applicationOrder => [...edges]
    ..sort((a, b) {
      final byMode =
          (a.mode == TimelineRunEdgeMode.hold ? 0 : 1) -
          (b.mode == TimelineRunEdgeMode.hold ? 0 : 1);
      if (byMode != 0) {
        return byMode;
      }
      final byRun = a.run.startIndex.compareTo(b.run.startIndex);
      if (byRun != 0) {
        return byRun;
      }
      return (a.side == TimelineRunEdgeSide.start ? 0 : 1) -
          (b.side == TimelineRunEdgeSide.start ? 0 : 1);
    });

  /// Whether [run]'s [side] holds — the question a repeat's DEFAULT
  /// pattern asks about the opposite edge (UI-R13 #5: the default pattern
  /// is the DISPLAYED run, hold ghosts included).
  bool holds(TimelineGluedRun run, TimelineRunEdgeSide side) => edges.any(
    (edge) =>
        edge.run.startIndex == run.startIndex &&
        edge.side == side &&
        edge.mode == TimelineRunEdgeMode.hold,
  );

  TimelineExposure ghostEntry({
    required FrameId frameId,
    required int length,
    required TimelineRunEdgeGhost owner,
    List<int> dots = const [],
  }) {
    var ghost = TimelineExposure.drawing(
      frameId,
      length: length,
      ghostOf: owner,
    );
    if (dots.isNotEmpty) {
      // copyWith clamps the dots to the (possibly shorter) ghost length.
      ghost = ghost.copyWith(breakdownOffsets: dots);
    }
    return ghost;
  }

  /// Pass 3, one run side: its ghosts, clamped against authored entries
  /// and earlier sides' ghosts — derived frames never displace real ones.
  void apply(_RunEdge edge) {
    if (edge.side == TimelineRunEdgeSide.end) {
      _fillAfter(edge);
    } else {
      _fillBefore(edge);
    }
  }

  /// End side: hold = one ghost of the run's last frameId filling to the
  /// drawn end; repeat = the pattern span cycling to the drawn end.
  void _fillAfter(_RunEdge edge) {
    final ghostStart = edge.run.endIndexExclusive;
    // Fill limit: the drawn end, or the next occupied index (an authored
    // entry or an earlier behavior's ghosts) — whichever comes first.
    var limit = drawnFrameCount;
    final nextKey = result.firstKeyAfter(ghostStart - 1);
    if (nextKey != null && nextKey < limit) {
      limit = nextKey;
    }
    if (limit <= ghostStart) {
      return; // Occluded right now; the marks survive.
    }

    if (edge.mode == TimelineRunEdgeMode.hold) {
      final lastBlockKey = result.lastKeyBefore(ghostStart)!;
      result[ghostStart] = ghostEntry(
        frameId: result[lastBlockKey]!.frameId!,
        length: limit - ghostStart,
        owner: _endHoldGhost,
      );
      return;
    }
    _repeatAfter(edge, ghostStart: ghostStart, limit: limit);
  }

  /// Repeat: pattern span [patternStart, run end), cycling to [limit].
  void _repeatAfter(
    _RunEdge edge, {
    required int ghostStart,
    required int limit,
  }) {
    final run = edge.run;
    var patternStart = run.startIndex;
    final bound = edge.bound;
    if (bound != null) {
      // End side: the pattern opens at the bound BLOCK's start.
      patternStart = bound;
    } else if (holds(run, TimelineRunEdgeSide.start)) {
      // UI-R13 #5: the DEFAULT pattern is the DISPLAYED run — a
      // front-hold lead-in abutting the run start joins the repeated
      // unit (holds applied first, so its ghost already sits here).
      // A lead-in ghost is keyed at ITS own start, so finding it is a
      // search backwards plus an adjacency test.
      final leadKey = result.lastKeyBefore(run.startIndex);
      if (leadKey != null) {
        final lead = result[leadKey]!;
        if (lead.ghostOf == _startHoldGhost &&
            leadKey + lead.length! == run.startIndex) {
          patternStart = leadKey;
        }
      }
    }
    _tileGhosts(
      _patternParts(patternStart, run.endIndexExclusive),
      span: run.endIndexExclusive - patternStart,
      fill: (lo: ghostStart, hi: limit, alignAt: ghostStart),
      owner: const TimelineRunEdgeGhost(
        side: TimelineRunEdgeSide.end,
        mode: TimelineRunEdgeMode.repeat,
      ),
    );
  }

  /// Start side: the mirror, ghosts FLUSH-aligned to the run start (a
  /// partial lead-in shows the pattern's tail).
  void _fillBefore(_RunEdge edge) {
    // Start side: fill [limitStart, run start), flush-aligned to the run.
    final runStart = edge.run.startIndex;
    var limitStart = 0;
    final previousKey = result.lastKeyBefore(runStart);
    if (previousKey != null) {
      limitStart = math.max(0, previousKey + result[previousKey]!.length!);
    }
    if (limitStart >= runStart) {
      return; // Occluded; the marks survive.
    }

    if (edge.mode == TimelineRunEdgeMode.hold) {
      result[limitStart] = ghostEntry(
        frameId: base[runStart]!.frameId!,
        length: runStart - limitStart,
        owner: _startHoldGhost,
      );
      return;
    }
    _repeatBefore(edge, limitStart: limitStart);
  }

  /// Repeat: pattern span [run start, patternEnd), tiled leftward down to
  /// [limitStart].
  void _repeatBefore(_RunEdge edge, {required int limitStart}) {
    final run = edge.run;
    final runStart = run.startIndex;
    var patternEnd = run.endIndexExclusive;
    final bound = edge.bound;
    if (bound != null) {
      // Start side: the pattern closes at the bound BLOCK's end.
      patternEnd = bound + base[bound]!.length!;
    } else if (holds(run, TimelineRunEdgeSide.end)) {
      // UI-R13 #5 (the mirror): a rear-hold tail abutting the run end
      // joins the repeated unit — the front repeat cycles the DISPLAYED
      // run, hold included.
      // A rear ghost is keyed exactly at the run's end, so this side
      // reads it straight out of the map.
      final rear = result[run.endIndexExclusive];
      if (rear != null && rear.ghostOf == _endHoldGhost) {
        patternEnd = run.endIndexExclusive + rear.length!;
      }
    }
    _tileGhosts(
      _patternParts(runStart, patternEnd),
      span: patternEnd - runStart,
      fill: (lo: limitStart, hi: runStart, alignAt: runStart),
      owner: const TimelineRunEdgeGhost(
        side: TimelineRunEdgeSide.start,
        mode: TimelineRunEdgeMode.repeat,
      ),
    );
  }

  /// The pattern's parts, offsets relative to [patternStart].
  ///
  /// From RESULT, not base: the pattern may include this run's own
  /// front-hold / rear-hold ghost (UI-R13 #5); inside the run the two
  /// agree.
  List<_PatternPart> _patternParts(int patternStart, int patternEnd) => [
    for (final entry in result.entries)
      if (entry.key >= patternStart && entry.key < patternEnd)
        (
          offset: entry.key - patternStart,
          frameId: entry.value.frameId!,
          length: math.min(entry.value.length!, patternEnd - entry.key),
          dots: entry.value.breakdownOffsets,
        ),
  ];

  /// Tiles [parts] across the free interval `[lo, hi)`, with the cycle
  /// phase pinned so that a cycle boundary lands exactly on [alignAt].
  ///
  /// ★[alignAt] is what tells the two sides apart, and it is a frame
  /// NUMBER, not a mode. The end side pins the phase to the first ghost
  /// frame, so a partial cycle at the far end is cut off its HEAD; the
  /// start side pins it to the run start, so the leftmost partial cycle
  /// keeps the pattern's TAIL — lead-in alignment (UI-R13 #5). Which wall
  /// clips is then simply which side of [lo, hi) the part runs off.
  ///
  /// A part straddling a wall keeps its VISIBLE half, and its breakdown
  /// dots move with it. (Dots past the far end need no arithmetic:
  /// [TimelineExposure] drops any that fall outside the clipped length.)
  void _tileGhosts(
    List<_PatternPart> parts, {
    required int span,
    required _GhostFill fill,
    required TimelineRunEdgeGhost owner,
  }) {
    final (:lo, :hi, :alignAt) = fill;
    for (
      var cycleStart = alignAt + floorDiv(lo - alignAt, span) * span;
      cycleStart < hi;
      cycleStart += span
    ) {
      for (final part in parts) {
        final placed = cycleStart + part.offset;
        final start = math.max(placed, lo);
        final end = math.min(placed + part.length, hi);
        if (end <= start) {
          continue; // Fully cut off by a wall.
        }
        final shift = start - placed;
        result[start] = ghostEntry(
          frameId: part.frameId,
          length: end - start,
          owner: owner,
          dots: shift == 0
              ? part.dots
              : [for (final dot in part.dots) dot - shift],
        );
      }
    }
  }

  /// Whether [layer] already shows exactly this pass's result — identity
  /// matters for the grid's memo gates.
  bool leavesUnchanged(Layer layer) {
    if (result.length != layer.timeline.length) {
      return false;
    }
    for (final entry in result.entries) {
      if (layer.timeline[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }
}

/// Re-derives every run edge's ghost entries from the CURRENT base
/// timeline — THE live-sync engine (UI-R8 repeat regions rebuilt as UI-R9
/// edge properties, carried by the blocks themselves since F-134). Pure:
/// returns [layer] itself when nothing changes (identity matters for the
/// grid's memo gates).
///
/// Pass order:
/// 1. Strip every ghost entry (derived state, never authored).
/// 2. Every glued run's two sides resolve from their blocks' marks — the
///    carrier nearest the edge wins, a bound belongs to the carrier nearest
///    it (see [TimelineRunEdgeMark]) — and the marks the resolution did not
///    pick are stripped.
/// 3. Application, holds before repeats, in run order, start side before
///    end side. End side: hold = one ghost of the run's last frameId filling
///    to the DRAWN end ([_RunBehaviorPass.drawnFrameCount]); repeat = the
///    pattern span cycling to it.
///    Start side is the mirror, ghosts FLUSH-aligned to the run start (a
///    partial lead-in shows the pattern's tail). Ghosts clamp against
///    authored entries and earlier sides' ghosts — derived frames never
///    displace real ones.
/// 4. A fully occluded side keeps its marks (the property comes back when
///    room opens up again).
Layer rederiveRunBehaviors(Layer layer, {required int drawnFrameCount}) {
  final carriesAnything = layer.timeline.values.any(
    (entry) => entry.ghost || !entry.startEdge.isNone || !entry.endEdge.isNone,
  );
  if (!carriesAnything) {
    return layer;
  }
  // Pass 1: strip every ghost entry (derived state, never authored).
  final pass = _RunBehaviorPass(
    ghostFreeTimeline(layer),
    drawnFrameCount: drawnFrameCount,
  );
  pass.resolve();
  for (final edge in pass.applicationOrder) {
    pass.apply(edge);
  }
  if (pass.leavesUnchanged(layer)) {
    return layer;
  }
  return layer.copyWith(timeline: pass.result);
}

/// The contiguous GLUED run of non-ghost drawing blocks containing the
/// block at [blockStartIndex] (UI-R8: the run-edge handles' unit —
/// "연결된 블록들"): expands in both directions while neighbours touch
/// (next.start == prev.endExclusive). Null when no non-ghost block starts
/// there.
TimelineGluedRun? gluedRunAt(Layer layer, int blockStartIndex) =>
    gluedRunsByBlockStart(layer)[blockStartIndex];

/// EVERY glued run in [layer], keyed by each member block's start index.
///
/// [gluedRunAt] answers for one block and rebuilds the block list to do it,
/// so asking it once per block — which is what resolving a row's run-edge
/// chrome does — was O(n²) with an allocation per block. Callers that want
/// more than one run resolve them all in a single pass through this and index
/// the result.
Map<int, TimelineGluedRun> gluedRunsByBlockStart(Layer layer) => {
  for (final run in _gluedRuns(layer.timeline))
    for (final start in run.blockStarts) start: run,
};

/// The property on [side] of the glued run containing [blockStartIndex];
/// null when the edge carries none (None).
TimelineRunEdgeProperty? runEdgeBehaviorAt(
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
/// that walked every run once should use. [run] must be one of [layer]'s.
TimelineRunEdgeProperty? runEdgeBehaviorIn(
  Layer layer,
  TimelineGluedRun run,
  TimelineRunEdgeSide side,
) {
  final resolved = _resolveRunEdge(layer.timeline, run.blockStarts, side);
  return resolved == null
      ? null
      : (mode: resolved.mode, patternBlockStart: resolved.bound);
}

/// The edge property the ghost covering [frameIndex] was derived from; null
/// when the cell is not ghost-covered. The cells painter reads the mode off
/// this (hold ghosts draw ㅡ dashes, repeat ghosts text-only cel names —
/// UI-R10 #11).
TimelineRunEdgeGhost? runEdgeGhostAt(Layer layer, int frameIndex) {
  final entry = layer.timeline[frameIndex];
  if (entry != null) {
    return entry.ghostOf;
  }
  final coveringKey = layer.timeline.lastKeyBefore(frameIndex);
  if (coveringKey == null) {
    return null;
  }
  final covering = layer.timeline[coveringKey]!;
  return frameIndex < coveringKey + covering.length!
      ? covering.ghostOf
      : null;
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

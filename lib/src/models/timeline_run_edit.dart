import 'dart:collection';
import 'dart:math' as math;

import 'frame.dart';
import 'frame_id.dart';
import 'layer.dart';
import 'timeline_exposure.dart';
import 'timeline_repeat.dart';

/// TVP-style "+ add frames" at a run edge (UI-R8): [count] NEW one-frame
/// drawings glued onto the run containing the block at [blockStartIndex].
///
/// - [atEnd]: the new frames insert at the run's end; downstream drawings
///   get overlap-pushed (gaps absorb first, the end-grow grip's feel) and
///   marks at/after the insertion point ride along by [count].
/// - Start side: the new frames fill the gap BEFORE the run — clamped at
///   frame 0 and the previous entry's coverage (nothing gets pushed left).
///
/// [frameIdAt] supplies project-unique ids per new-frame ordinal (0-based)
/// so a drag preview and its commit synthesize the SAME ids. Returns null
/// when nothing can be added.
({Layer layer, List<FrameId> newFrameIds})? layerWithNewFramesAtRunEdge(
  Layer layer, {
  required int blockStartIndex,
  required bool atEnd,
  required int count,
  required FrameId Function(int ordinal) frameIdAt,
}) {
  if (count < 1) {
    return null;
  }
  final run = gluedRunAt(layer, blockStartIndex);
  if (run == null) {
    return null;
  }

  // Plan on the ghost-free base; the caller re-derives repeats after.
  final base = ghostFreeTimeline(layer);

  if (atEnd) {
    final insertStart = run.endIndexExclusive;
    final next = SplayTreeMap<int, TimelineExposure>();
    base.forEach((index, entry) {
      if (index < insertStart) {
        next[index] = entry;
      }
    });
    // Downstream drawings overlap-push (gaps absorb).
    var frontier = insertStart + count;
    for (final index in base.keys) {
      if (index < insertStart) {
        continue;
      }
      final entry = base[index]!;
      final newStart = math.max(index, frontier);
      frontier = newStart + entry.length!;
      next[newStart] = entry;
    }
    final ids = <FrameId>[];
    for (var i = 0; i < count; i += 1) {
      final id = frameIdAt(i);
      ids.add(id);
      next[insertStart + i] = TimelineExposure.drawing(id, length: 1);
    }
    return (
      layer: layer.copyWith(
        timeline: next,
        frames: [
          ...layer.frames,
          for (final id in ids) Frame(id: id, duration: 1, strokes: const []),
        ],
      ),
      newFrameIds: ids,
    );
  }

  // Start side: clamp into the free gap before the run.
  var gapStart = 0;
  final previousKey = base.lastKeyBefore(run.startIndex);
  if (previousKey != null) {
    gapStart = previousKey + base[previousKey]!.length!;
  }
  final room = run.startIndex - gapStart;
  final clamped = math.min(count, room);
  if (clamped < 1) {
    return null;
  }
  final next = SplayTreeMap<int, TimelineExposure>.of(base);
  final ids = <FrameId>[];
  for (var i = 0; i < clamped; i += 1) {
    final id = frameIdAt(i);
    ids.add(id);
    next[run.startIndex - clamped + i] = TimelineExposure.drawing(
      id,
      length: 1,
    );
  }
  return (
    layer: layer.copyWith(
      timeline: next,
      frames: [
        ...layer.frames,
        for (final id in ids) Frame(id: id, duration: 1, strokes: const []),
      ],
    ),
    newFrameIds: ids,
  );
}

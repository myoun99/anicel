part of '../timeline_controller.dart';

/// THE EXPOSURE EDGE — shifting an exposure's edge: whether it can move,
/// how far, and the timeline it leaves behind — as its own object.
///
/// 🚨A collaborator carved out of `TimelineController` (the audit's SRP
/// cut, 2026-09-02). Measured before cutting: four controller members
/// shared. It reaches the controller through `_controller`.
class _TimelineExposureEdge {
  _TimelineExposureEdge(this._controller);

  final TimelineController _controller;

  /// Whether the block starting at [blockStartIndex] can shift its [edge]
  /// at all in the direction of [delta] (used to enable UI affordances;
  /// the actual applied delta is clamped by [clampExposureEdgeDelta]).
  bool canShiftExposureEdge({
    required Layer layer,
    required int blockStartIndex,
    required TimelineBlockEdge edge,
    required int delta,
  }) {
    return clampExposureEdgeDelta(
          layer: layer,
          blockStartIndex: blockStartIndex,
          edge: edge,
          delta: delta,
        ) !=
        0;
  }

  /// The largest applicable portion of [delta] for an edge shift:
  /// shrinking stops at length 1, and start-edge growth stops when the
  /// pushed chain would cross frame 0. Growth toward the open end is
  /// unlimited.
  int clampExposureEdgeDelta({
    required Layer layer,
    required int blockStartIndex,
    required TimelineBlockEdge edge,
    required int delta,
  }) {
    final entry = layer.timeline[blockStartIndex];
    if (entry == null || !entry.isDrawing || delta == 0) {
      return 0;
    }
    final length = entry.length!;

    switch (edge) {
      case TimelineBlockEdge.end:
        if (delta > 0) {
          return delta;
        }
        // Shrink from the end: keep at least one frame.
        return delta < 1 - length ? 1 - length : delta;
      case TimelineBlockEdge.start:
        if (delta > 0) {
          // Shrink from the front: keep at least one frame.
          return delta > length - 1 ? length - 1 : delta;
        }
        // Grow backward: limited by the room the preceding glued/pushed
        // chain has before frame 0.
        final maxGrow = _controller._startEdgeGrowRoom(
          layer.timeline,
          blockStartIndex: blockStartIndex,
        );
        return delta < -maxGrow ? -maxGrow : delta;
    }
  }

  /// Pure computation of the layer after a comma edge shift; `null` when
  /// the clamped delta is zero. Exposed for drag previews (apply directly,
  /// commit once on release) while [shiftExposureEdge] applies it as a
  /// single undoable command.
  Layer? shiftedLayerForEdge({
    required Layer layer,
    required int blockStartIndex,
    required TimelineBlockEdge edge,
    required int delta,
  }) {
    final clampedDelta = clampExposureEdgeDelta(
      layer: layer,
      blockStartIndex: blockStartIndex,
      edge: edge,
      delta: delta,
    );
    if (clampedDelta == 0) {
      return null;
    }

    final nextTimeline = _shiftEdgeTimeline(
      layer.timeline,
      blockStartIndex: blockStartIndex,
      edge: edge,
      delta: clampedDelta,
    );
    // Live preview keeps the ghosts following the dragged run (UI-R8).
    return rederiveRunBehaviors(
      layer.copyWith(timeline: nextTimeline),
      cutFrameCount: _controller._cutFrameCount(),
    );
  }

  void shiftExposureEdge({
    required LayerId layerId,
    required int blockStartIndex,
    required TimelineBlockEdge edge,
    required int delta,
  }) {
    final before = _controller._requireLayer(layerId);
    // Callers pass the block start as DISPLAYED (cut-local); track-SE
    // layers store it at the global offset.
    final after = shiftedLayerForEdge(
      layer: before,
      blockStartIndex:
          blockStartIndex +
          (_controller._frameOffsetForLayer?.call(layerId) ?? 0),
      edge: edge,
      delta: delta,
    );
    if (after == null || after == before) {
      return;
    }
    _controller._applyLayerEdit(before: before, after: after);
  }

  SplayTreeMap<int, TimelineExposure> _shiftEdgeTimeline(
    SplayTreeMap<int, TimelineExposure> timeline, {
    required int blockStartIndex,
    required TimelineBlockEdge edge,
    required int delta,
  }) {
    final blocks = drawingBlocks(timeline);
    final targetIndex = blocks.indexWhere(
      (block) => block.startIndex == blockStartIndex,
    );
    if (targetIndex == -1) {
      throw StateError('No drawing block starts at index $blockStartIndex.');
    }

    // New start/length per block, seeded with the resized target.
    final newStarts = List<int>.generate(
      blocks.length,
      (i) => blocks[i].startIndex,
      growable: false,
    );
    final newLengths = List<int>.generate(
      blocks.length,
      (i) => blocks[i].length,
      growable: false,
    );

    final target = blocks[targetIndex];
    switch (edge) {
      case TimelineBlockEdge.end:
        newLengths[targetIndex] = target.length + delta;
      case TimelineBlockEdge.start:
        newStarts[targetIndex] = target.startIndex + delta;
        newLengths[targetIndex] = target.length - delta;
    }

    // Ripple following blocks (end-edge resizes and front shrinks change
    // where the target ends; contact rules: glued blocks stay glued,
    // separated blocks move only when overlapped).
    var prevOldEnd = target.endIndexExclusive;
    var prevNewEnd = newStarts[targetIndex] + newLengths[targetIndex];
    for (var i = targetIndex + 1; i < blocks.length; i += 1) {
      final block = blocks[i];
      final glued = block.startIndex == prevOldEnd;
      var start = glued ? prevNewEnd : block.startIndex;
      if (start < prevNewEnd) {
        start = prevNewEnd;
      }
      newStarts[i] = start;
      prevOldEnd = block.endIndexExclusive;
      prevNewEnd = start + block.length;
    }

    // Ripple preceding blocks (start-edge moves): mirror of the above.
    var nextOldStart = target.startIndex;
    var nextNewStart = newStarts[targetIndex];
    for (var i = targetIndex - 1; i >= 0; i -= 1) {
      final block = blocks[i];
      final glued = block.endIndexExclusive == nextOldStart;
      var end = glued ? nextNewStart : block.endIndexExclusive;
      if (end > nextNewStart) {
        end = nextNewStart;
      }
      newStarts[i] = end - block.length;
      nextOldStart = block.startIndex;
      nextNewStart = newStarts[i];
    }

    if (newStarts.isNotEmpty && newStarts.first < 0) {
      throw StateError(
        'Comma edge shift would push a block before frame 0 '
        '(clamp deltas with clampExposureEdgeDelta first).',
      );
    }

    // Rebuild: drawings at their new starts. Block-owned dots ride inside
    // the entries for free; copyWith drops offsets a shrink cut off.
    final next = SplayTreeMap<int, TimelineExposure>();
    for (var i = 0; i < blocks.length; i += 1) {
      next[newStarts[i]] = blocks[i].entry.copyWith(length: newLengths[i]);
    }
    return next;
  }
}

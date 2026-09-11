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
  /// pushed chain would cross frame 0 — or, for a MOVIE kept as a
  /// reference, at the file's first frame. Growth toward the open end is
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
        // chain has before frame 0 — and a movie's head by the frames of
        // the file before its in point ([_referenceAfterEdge]).
        final room = _controller._startEdgeGrowRoom(
          layer.timeline,
          blockStartIndex: blockStartIndex,
        );
        final maxGrow = isMovieReference(layer)
            ? math.min(room, layer.mediaReference!.frameOffset)
            : room;
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
      layer.copyWith(
        timeline: nextTimeline,
        mediaReference: _referenceAfterEdge(layer, edge, clampedDelta),
      ),
      cutFrameCount: _controller._cutFrameCount(),
    );
  }

  /// A MOVIE kept as a reference counts its positions from its block's
  /// start plus [MediaReference.frameOffset] — so a HEAD trim moves the
  /// file's in point by exactly what the start moved, and every frame left
  /// shows what it showed (the video spec the user approved, 2026-09-11: a
  /// reference block trims at both ends, and its head trim moves the in
  /// point). A tail trim, and every other row, keep theirs.
  static MediaReference? _referenceAfterEdge(
    Layer layer,
    TimelineBlockEdge edge,
    int delta,
  ) {
    final reference = layer.mediaReference;
    if (reference == null ||
        edge != TimelineBlockEdge.start ||
        !isMovieReference(layer)) {
      return reference;
    }
    return reference.copyWith(frameOffset: reference.frameOffset + delta);
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
    final layout = _BlockLayout.of(timeline);
    final targetIndex = layout.blocks.indexWhere(
      (block) => block.startIndex == blockStartIndex,
    );
    if (targetIndex == -1) {
      throw StateError('No drawing block starts at index $blockStartIndex.');
    }

    final target = layout.blocks[targetIndex];
    switch (edge) {
      case TimelineBlockEdge.end:
        layout.lengths[targetIndex] = target.length + delta;
      case TimelineBlockEdge.start:
        layout.starts[targetIndex] = target.startIndex + delta;
        layout.lengths[targetIndex] = target.length - delta;
    }

    // Ripple following blocks (end-edge resizes and front shrinks change
    // where the target ends; contact rules: glued blocks stay glued,
    // separated blocks move only when overlapped).
    layout.relayAfter(targetIndex);

    // Ripple preceding blocks (start-edge moves): mirror of the above.
    var nextOldStart = target.startIndex;
    var nextNewStart = layout.starts[targetIndex];
    for (var i = targetIndex - 1; i >= 0; i -= 1) {
      final block = layout.blocks[i];
      final glued = block.endIndexExclusive == nextOldStart;
      var end = glued ? nextNewStart : block.endIndexExclusive;
      if (end > nextNewStart) {
        end = nextNewStart;
      }
      layout.starts[i] = end - block.length;
      nextOldStart = block.startIndex;
      nextNewStart = layout.starts[i];
    }

    if (layout.starts.isNotEmpty && layout.starts.first < 0) {
      throw StateError(
        'Comma edge shift would push a block before frame 0 '
        '(clamp deltas with clampExposureEdgeDelta first).',
      );
    }

    return layout.toTimeline();
  }
}

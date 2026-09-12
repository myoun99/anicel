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
        // Grow backward: the empty space in front plus what the block
        // it touches can give up before IT would fall under one frame —
        // the shared lead-edge rule's own limit, asked rather than
        // re-derived (I-21). A movie's head is additionally capped by the
        // frames of the file before its in point ([_referenceAfterEdge]).
        final room = _leadEdgeRoomInFront(
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
        // Ripple following blocks: a trailing-edge resize moves where the
        // target ends. Contact rules — glued blocks stay glued, separated
        // blocks move only when overlapped.
        layout.relayAfter(targetIndex);
      case TimelineBlockEdge.start:
        // ★THE LEAD EDGE IS ONE RULE FOR BOTH AXES, and it lives in the
        // model (I-21). The frame axis used to walk backwards with its
        // own copy of the contact rules — the same algorithm the cut axis
        // read from [planBlockRunLeadEdge], spelled twice. It is spelled
        // once now: nothing in front moves, the neighbour trades frames
        // across the boundary, and the target's end holds by arithmetic.
        _applyLeadEdge(layout, targetIndex: targetIndex, delta: delta);
    }

    if (layout.starts.isNotEmpty && layout.starts.first < 0) {
      throw StateError(
        'Comma edge shift would push a block before frame 0 '
        '(clamp deltas with clampExposureEdgeDelta first).',
      );
    }

    return layout.toTimeline();
  }

  /// [layer] after a LEAD-edge drag of the block starting at
  /// [blockStartIndex], reaching [reach] blocks in front — the SELECTION's
  /// answer when a range is live, one when it is not.
  ///
  /// The bulk path needs the rule at LAYER level (it rewrites whole rows
  /// per drag step) and the single-grip path needs it at timeline level;
  /// both arrive here, so "how a lead edge lays out" is written once.
  Layer? leadEdgeLayerForBlock({
    required Layer layer,
    required int blockStartIndex,
    required int delta,
    int reach = 1,
  }) {
    final layout = _BlockLayout.of(layer.timeline);
    final targetIndex = layout.blocks.indexWhere(
      (block) => block.startIndex == blockStartIndex,
    );
    if (targetIndex == -1 || delta == 0) {
      return null;
    }
    _applyLeadEdge(layout, targetIndex: targetIndex, delta: delta, reach: reach);
    final next = layer.copyWith(timeline: layout.toTimeline());
    return next == layer ? null : next;
  }

  /// How far this block's lead edge can travel forward, by the shared
  /// rule: ask it for an unreachable delta and see what it grants.
  ///
  /// ⛔DERIVED, NOT RE-DERIVED. The room used to be computed here from the
  /// axis's own arithmetic ("every gap up to frame 0"), which was a second
  /// statement of a limit the planner already owns — and the two would
  /// have parted the moment either moved. I-21 moved it.
  int _leadEdgeRoomInFront(
    SplayTreeMap<int, TimelineExposure> timeline, {
    required int blockStartIndex,
  }) {
    final layout = _BlockLayout.of(timeline);
    final targetIndex = layout.blocks.indexWhere(
      (block) => block.startIndex == blockStartIndex,
    );
    if (targetIndex == -1) {
      return 0;
    }
    final before = layout.blocks[targetIndex].startIndex;
    _applyLeadEdge(layout, targetIndex: targetIndex, delta: -_unreachable);
    return before - layout.starts[targetIndex];
  }

  /// Bigger than any timeline a hand can drag — the planner clamps it.
  static const int _unreachable = 1 << 30;

  /// Lays [layout] out after a LEAD-edge drag, through the shared rule.
  ///
  /// The model speaks in slots (leading gap + length); this axis speaks in
  /// absolute starts. Converting both ways is the whole adapter — and it
  /// is what keeps "드래그하는 블록 로직은 컷블록이랑 전부 통일" true in
  /// code rather than in two places that merely agree today.
  void _applyLeadEdge(
    _BlockLayout layout, {
    required int targetIndex,
    required int delta,
    int reach = 1,
  }) {
    var previousEnd = 0;
    final slots = <BlockMoveSlot>[];
    for (final block in layout.blocks) {
      slots.add((
        leadingGap: block.startIndex - previousEnd,
        length: block.length,
      ));
      previousEnd = block.endIndexExclusive;
    }

    final planned = planBlockRunLeadEdge(
      slots: slots,
      targetIndex: targetIndex,
      frameDelta: delta,
      limits: (minLength: 1, reach: reach),
    );

    var cursor = 0;
    for (var i = 0; i < layout.blocks.length; i += 1) {
      cursor += planned.leadingGaps[i];
      layout.starts[i] = cursor;
      layout.lengths[i] = planned.lengths[i];
      cursor += planned.lengths[i];
    }
  }
}

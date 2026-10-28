part of '../timeline_controller.dart';

/// THE MARKS — the inbetween marks a layer carries: whether a frame has
/// one, toggling one, the frames a band can mark and setting them all —
/// as their own object.
///
/// 🚨A collaborator carved out of `TimelineController` (the audit's SRP
/// cut, 2026-09-02). Measured before cutting: five controller members
/// shared. It reaches the controller through `_controller`.
class _TimelineMarks {
  _TimelineMarks(this._controller);

  final TimelineController _controller;

  bool hasMarkAt({required Layer layer, required int frameIndex}) {
    if (frameIndex < 0) {
      return false;
    }
    return breakdownMarkAt(layer.timeline, frameIndex) != null;
  }

  /// Inbetween dots live on the HELD cells of a real drawing block only
  /// (offset 1..length-1): a block start is the drawing itself, an empty
  /// cell has no block to own the dot (author an unnamed frame first), and
  /// ghosts are derived — their dots come from the source block.
  bool canToggleMarkAt({required Layer layer, required int frameIndex}) {
    if (frameIndex < 0) {
      return false;
    }
    return isHeldCellAt(layer.timeline, frameIndex);
  }

  /// [mark] at the edit frame — or none, where the cell already wears it.
  ///
  /// 🗣️I-130-Q1 (추천 a, 답 전): a cell wearing the OTHER mark takes this
  /// one — one mark to a cell, 「모양이 다를뿐인 같은 중간나누기」.
  void toggleMarkForLayer({
    required LayerId layerId,
    required InbetweenMark mark,
  }) => _controller._editCoveringBlockAtEditFrame(
    layerId,
    canEdit: (layer, frameIndex) =>
        canToggleMarkAt(layer: layer, frameIndex: frameIndex),
    edit: (entry, offset) => _withMark(
      entry,
      offset,
      entry.breakdownMarks[offset] == mark ? null : mark,
    ),
  );

  /// [entry] with [mark] on the dot at [offset] — none there when null.
  static TimelineExposure _withMark(
    TimelineExposure entry,
    int offset,
    InbetweenMark? mark,
  ) => entry.copyWith(
    breakdownMarks: {
      for (final MapEntry(key: other, value: wears)
          in entry.breakdownMarks.entries)
        if (other != offset) other: wears,
      offset: ?mark,
    },
  );

  /// 🚨결정 9 / R8-c (유저 확정 2026-08-22) — **THE BAND'S FRAMES, NOT THE
  /// PLAYHEAD'S.**
  ///
  /// > 「지우기 눌렀다고해서 **현재 행만 지우는게아니라 선택된 모든게
  /// > 지워지는걸** 말하는거임. **복사든 뭐든 마찬가지**」
  ///
  /// Every swept frame that could take a mark, per row. Delete's band rung
  /// collects BLOCK STARTS because a cel is what it removes; a mark lives on
  /// a HELD frame inside a block ([canToggleMarkAt] refuses the head), so
  /// this one walks frames. Same law, different unit — and naming the unit
  /// here is what stops a caller handing the wrong list to the wrong verb.
  ///
  /// Empty when the band names nothing markable, which is a real answer and
  /// not an error: a band over three block heads has no mark to make, and
  /// that press must be a no-op rather than falling through onto whatever
  /// row happens to be active.
  Map<LayerId, List<int>> markableFramesInBand({
    required Iterable<LayerId> layerIds,
    required int startIndex,
    required int endIndexExclusive,
  }) {
    final byLayer = <LayerId, List<int>>{};
    for (final layerId in layerIds) {
      final layer = _controller._requireLayer(layerId);
      final frames = <int>[
        for (var index = startIndex; index < endIndexExclusive; index += 1)
          if (canToggleMarkAt(layer: layer, frameIndex: index)) index,
      ];
      if (frames.isNotEmpty) {
        byLayer[layerId] = frames;
      }
    }
    return byLayer;
  }

  /// Whether every frame in [framesByLayer] already wears [mark] — the
  /// question that turns a toggle into a SET.
  bool bandFramesAreAllMarked(
    Map<LayerId, List<int>> framesByLayer,
    InbetweenMark mark,
  ) {
    for (final entry in framesByLayer.entries) {
      final layer = _controller._requireLayer(entry.key);
      for (final frameIndex in entry.value) {
        if (breakdownMarkAt(layer.timeline, frameIndex) != mark) {
          return false;
        }
      }
    }
    return true;
  }

  /// Puts [mark] on every frame in [framesByLayer] — or clears them all,
  /// when null — ONE undo step.
  ///
  /// ⚠️SET, not toggle-each. A band holding a mix would otherwise INVERT
  /// under the hand and hand back the complement of what was there, which is
  /// the one outcome nobody presses a button for. The caller asks
  /// [bandFramesAreAllMarked] which way to go, so the whole band moves
  /// together the way Delete's does.
  void setMarksForFrames(
    Map<LayerId, List<int>> framesByLayer, {
    required InbetweenMark? mark,
  }) => _controller._editLayersAsOneStep(
    framesByLayer,
    edit: (before, frames) => _markedFramesLayer(before, frames, mark: mark),
    description: 'Mark selected cells',
  );

  Layer? _markedFramesLayer(
    Layer before,
    List<int> frameIndexes, {
    required InbetweenMark? mark,
  }) {
    final nextTimeline = SplayTreeMap<int, TimelineExposure>.from(
      before.timeline,
    );
    var changed = false;
    for (final frameIndex in frameIndexes) {
      final block = coveringDrawingBlockAt(before.timeline, frameIndex);
      if (block == null) {
        continue;
      }
      final offset = frameIndex - block.startIndex;
      // ⚠️Read the entry back out of `nextTimeline`, never `before`: several
      // swept frames share ONE block, and each has to see the marks the ones
      // before it just made. Off `before`, the last write would win and
      // every earlier mark in that block would vanish.
      final entry = nextTimeline[block.startIndex];
      if (entry == null || entry.breakdownMarks[offset] == mark) {
        continue;
      }
      nextTimeline[block.startIndex] = _withMark(entry, offset, mark);
      changed = true;
    }
    return changed ? before.copyWith(timeline: nextTimeline) : null;
  }
}

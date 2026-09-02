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
    return hasBreakdownDotAt(layer.timeline, frameIndex);
  }

  /// Inbetween dots live on the HELD cells of a real drawing block only
  /// (offset 1..length-1): a block start is the drawing itself, an empty
  /// cell has no block to own the dot (author an unnamed frame first), and
  /// ghosts are derived — their dots come from the source block.
  bool canToggleMarkAt({required Layer layer, required int frameIndex}) {
    if (frameIndex < 0) {
      return false;
    }
    final block = coveringDrawingBlockAt(layer.timeline, frameIndex);
    return block != null && !block.entry.ghost && frameIndex > block.startIndex;
  }

  void toggleMarkForLayer({required LayerId layerId}) {
    final before = _controller._requireLayer(layerId);
    final frameIndex = _controller._editFrameIndexFor(layerId);
    if (!canToggleMarkAt(layer: before, frameIndex: frameIndex)) {
      return;
    }

    final block = coveringDrawingBlockAt(before.timeline, frameIndex)!;
    final offset = frameIndex - block.startIndex;
    final entry = block.entry;
    final nextTimeline = SplayTreeMap<int, TimelineExposure>.from(
      before.timeline,
    );
    nextTimeline[block.startIndex] = entry.copyWith(
      breakdownOffsets: entry.hasBreakdownAt(offset)
          ? [
              for (final existing in entry.breakdownOffsets)
                if (existing != offset) existing,
            ]
          : [...entry.breakdownOffsets, offset],
    );
    _controller._applyLayerEdit(
      before: before,
      after: before.copyWith(timeline: nextTimeline),
    );
  }

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

  /// Whether every frame in [framesByLayer] already carries a mark — the
  /// question that turns a toggle into a SET.
  bool bandFramesAreAllMarked(Map<LayerId, List<int>> framesByLayer) {
    for (final entry in framesByLayer.entries) {
      final layer = _controller._requireLayer(entry.key);
      for (final frameIndex in entry.value) {
        final block = coveringDrawingBlockAt(layer.timeline, frameIndex);
        if (block == null ||
            !block.entry.hasBreakdownAt(frameIndex - block.startIndex)) {
          return false;
        }
      }
    }
    return true;
  }

  /// Marks or clears every frame in [framesByLayer] — ONE undo step.
  ///
  /// ⚠️SET, not toggle-each. A band holding a mix would otherwise INVERT
  /// under the hand and hand back the complement of what was there, which is
  /// the one outcome nobody presses a button for. The caller asks
  /// [bandFramesAreAllMarked] which way to go, so the whole band moves
  /// together the way Delete's does.
  void setMarksForFrames(
    Map<LayerId, List<int>> framesByLayer, {
    required bool marked,
  }) {
    final commands = <Command>[];
    for (final entry in framesByLayer.entries) {
      final before = _controller._requireLayer(entry.key);
      final after = _markedFramesLayer(before, entry.value, marked: marked);
      if (after != null) {
        commands.add(
          _controller._layerEditCommand(before: before, after: after),
        );
      }
    }
    _controller._executeCommands(commands, description: 'Mark selected cells');
  }

  Layer? _markedFramesLayer(
    Layer before,
    List<int> frameIndexes, {
    required bool marked,
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
      if (entry == null || entry.hasBreakdownAt(offset) == marked) {
        continue;
      }
      nextTimeline[block.startIndex] = entry.copyWith(
        breakdownOffsets: marked
            ? [...entry.breakdownOffsets, offset]
            : [
                for (final existing in entry.breakdownOffsets)
                  if (existing != offset) existing,
              ],
      );
      changed = true;
    }
    return changed ? before.copyWith(timeline: nextTimeline) : null;
  }
}

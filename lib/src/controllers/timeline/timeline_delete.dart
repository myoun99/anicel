part of '../timeline_controller.dart';

/// DELETING — a cell, a block, blocks across layers, and the layer left
/// behind — as their own object.
///
/// 🚨A collaborator carved out of `TimelineController` (the audit's SRP
/// cut, 2026-09-02). It reaches the controller through `_controller`.
class _TimelineDelete {
  _TimelineDelete(this._controller);

  final TimelineController _controller;

  /// Standing ANYWHERE inside a real drawing block deletes it (UI-R17 #1)
  /// — the old head-only rule made held cells feel dead.
  bool canDeleteCellAt({required Layer layer, required int frameIndex}) {
    final block = coveringDrawingBlockAt(layer.timeline, frameIndex);
    return block != null && !block.entry.ghost;
  }

  void deleteCellForLayer({required LayerId layerId}) {
    final before = _controller._requireLayer(layerId);
    final frameIndex = _controller._editFrameIndexFor(layerId);
    if (!canDeleteCellAt(layer: before, frameIndex: frameIndex)) {
      return;
    }
    deleteBlocksForLayer(
      layerId: layerId,
      blockStartIndexes: [
        coveringDrawingBlockAt(before.timeline, frameIndex)!.startIndex,
      ],
    );
  }

  /// Deletes every block starting at [blockStartIndexes] in ONE undo step
  /// (UI-R17 #2 — multi-selection delete). Ghost instances are skipped
  /// (derived); frames no longer referenced anywhere are GC'd with them.
  void deleteBlocksForLayer({
    required LayerId layerId,
    required List<int> blockStartIndexes,
  }) {
    deleteBlocksForLayers({layerId: blockStartIndexes});
  }

  /// The cross-layer form (UI-R17 #8): every layer's deletions compose
  /// into ONE undo step.
  void deleteBlocksForLayers(Map<LayerId, List<int>> blockStartsByLayer) =>
      _controller._editLayersAsOneStep(
        blockStartsByLayer,
        edit: _deletedBlocksLayer,
        description: 'Delete selected cells',
      );

  Layer? _deletedBlocksLayer(Layer before, List<int> blockStartIndexes) {
    final nextTimeline = SplayTreeMap<int, TimelineExposure>.from(
      before.timeline,
    );
    final removedFrameIds = <FrameId>{};
    for (final startIndex in blockStartIndexes) {
      final entry = before.timeline[startIndex];
      if (entry == null || !entry.isDrawing || entry.ghost) {
        continue;
      }
      nextTimeline.remove(startIndex);
      final frameId = entry.frameId;
      if (frameId != null) {
        removedFrameIds.add(frameId);
      }
    }
    if (nextTimeline.length == before.timeline.length) {
      return null;
    }
    var nextFrames = before.frames;
    final unreferenced = removedFrameIds
        .where(
          (frameId) =>
              !_controller._timelineReferencesFrame(nextTimeline, frameId),
        )
        .toSet();
    if (unreferenced.isNotEmpty) {
      nextFrames = before.frames
          .where((frame) => !unreferenced.contains(frame.id))
          .toList(growable: false);
    }
    return before.copyWith(
      frames: nextFrames,
      timeline: nextTimeline,
      audioClips: _controller._audioClipsForFrames(before, nextFrames),
    );
  }
}

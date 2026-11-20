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
    return authoredDrawingBlockAt(layer.timeline, frameIndex) != null;
  }

  /// Whether a block stands at [at] on [layerId]'s OWN row, in its edit
  /// keys — what a 잘라내기 made standing lifts, wherever its press stands
  /// (`FrameClipboard.canCutAt`: the cut's playhead, or the track's while
  /// the storyboard is parked in a gap — F-281).
  bool blockStandsOn(LayerId layerId, {required int at}) => canDeleteCellAt(
    layer: _controller._requireLayer(layerId),
    frameIndex: at,
  );

  /// [blockStandsOn] under the playhead — what [deleteCellForLayer] takes.
  bool blockStandsAtPlayheadOn(LayerId layerId) =>
      blockStandsOn(layerId, at: _controller._editFrameIndexFor(layerId));

  void deleteCellForLayer({required LayerId layerId}) {
    final before = _controller._requireLayer(layerId);
    final frameIndex = _controller._editFrameIndexFor(layerId);
    if (!blockStandsAtPlayheadOn(layerId)) {
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
    for (final startIndex in blockStartIndexes) {
      final entry = before.timeline[startIndex];
      if (entry == null || !entry.isDrawing || entry.ghost) {
        continue;
      }
      nextTimeline.remove(startIndex);
    }
    if (nextTimeline.length == before.timeline.length) {
      return null;
    }
    // F-136: a cel another lane of the bank still exposes is not this row's
    // to take — the same answer the second 「1」 on this row gets.
    return _controller._leavingWhatItOrphaned(
      before,
      before.copyWith(timeline: nextTimeline),
    );
  }
}

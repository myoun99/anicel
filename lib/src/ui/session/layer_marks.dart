part of '../editor_session_manager.dart';

/// The LAYER MARKS — the mark a layer carries, the frames a selection can
/// mark, and toggling a mark at the current frame — as their own object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Dry-run before cutting: the rest reads none of it.
class _LayerMarks {
  _LayerMarks(this._session);

  final EditorSessionManager _session;

  /// Sets [layerId]'s organizational color mark. One undo step.
  void setLayerMark(LayerId layerId, LayerMark mark) {
    final cutId = _session._editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    _session._cutCommandCoordinator.setLayerMark(
      cutId: cutId,
      layerId: layerId,
      mark: mark,
    );
    _session._notifyChanged();
  }

  /// Clears every layer mark of the active cut (track-owned SE rows
  /// included, like the sheet sweep) — one undo.
  void clearAllLayerMarks() {
    final cut = _session.activeCutOrNull;
    if (cut == null) {
      return;
    }
    final cutId = cut.id;
    final commands = <Command>[
      for (final layer in [...cut.layers, ..._session.activeTrack.seLayers])
        if (layer.mark != LayerMark.none)
          UpdateLayerMarkCommand(
            repository: _session._repository,
            cutId: cutId,
            layerId: layer.id,
            mark: LayerMark.none,
          ),
    ];
    if (commands.isEmpty) {
      return;
    }
    _session._historyManager.execute(
      CompositeCommand(
        description: 'Clear all layer marks',
        commands: commands,
      ),
    );
    _session._notifyChanged();
  }

  /// 🚨결정 9 / R8-c (유저 확정 2026-08-22) — **THE MARK LEARNED THE BAND.**
  ///
  /// > 「지우기 눌렀다고해서 **현재 행만 지우는게아니라 선택된 모든게
  /// > 지워지는걸** 말하는거임. **복사든 뭐든 마찬가지**」
  ///
  /// The swept frames of the swept rows, or empty when no band is up. This
  /// is the rung the ● did not have: it used to END the ladder at a live
  /// band ([_session.bandNamesRowsThisPressWouldMiss]) because dotting the active row
  /// while the highlight sat elsewhere would edit something nobody swept.
  /// Refusing was the honest answer for a verb that could only reach one
  /// row; now that it can reach the band, serving it is.
  ///
  /// ⚠️SYNCED attach and non-drawing rows are filtered HERE rather than in
  /// the controller, for the same reason the delete collector does it: the
  /// button and the dispatch have to read one answer, and three downstream
  /// copies of a filter is how they stop agreeing.
  Map<LayerId, List<int>> _markableFramesForSelection() {
    final selection = _session.frameRangeSelection.value;
    if (selection == null) {
      return const {};
    }
    final ids = <LayerId>[];
    for (final id in selection.spanLayerIds) {
      final layer = _session._rangeLayerById(id);
      if (layer == null ||
          !layerKindHoldsDrawings(layer.kind) ||
          isSyncedAttachedLayer(layer)) {
        continue;
      }
      ids.add(id);
    }
    if (ids.isEmpty) {
      return const {};
    }
    return _session._timelineController.markableFramesInBand(
      layerIds: ids,
      startIndex: selection.startIndex,
      endIndexExclusive: selection.endIndexExclusive,
    );
  }

  bool get canToggleMarkForSelection =>
      _markableFramesForSelection().isNotEmpty;

  bool get canToggleMarkAtCurrentFrame {
    if (canToggleMarkForSelection) {
      return true;
    }
    // ⛔A band that names rows this press would miss still ENDS the ladder.
    // The band rung above is the whole of the new reach: a band holding
    // nothing markable makes the press a no-op, never a redirect onto
    // whatever row happens to be active (a cell drag never moves the active
    // layer, so those are routinely different rows).
    if (_session.bandNamesRowsThisPressWouldMiss) {
      return false;
    }
    final layer = _session.activeLayer;
    // SYNCED attach rows carry no cell marks (the base's sheet row
    // does); free attach rows mark like normal (UI-R21 #3).
    if (layer == null ||
        !layerKindHoldsDrawings(layer.kind) ||
        isSyncedAttachedLayer(layer)) {
      return false;
    }

    return _session._timelineController.canToggleMarkAt(
      layer: layer,
      frameIndex: _session._timelineController.currentFrameIndex,
    );
  }

  void toggleMarkAtCurrentFrame() {
    final banded = _markableFramesForSelection();
    if (banded.isNotEmpty) {
      // SET the whole band one way, never toggle each frame: a mixed band
      // would invert under the hand and hand back the complement of what
      // was there. All marked → clear; anything unmarked → mark them all.
      _session._timelineController.setMarksForFrames(
        banded,
        marked: !_session._timelineController.bandFramesAreAllMarked(banded),
      );
      _session._notifyChanged();
      return;
    }
    final layer = _session.activeLayer;
    if (layer == null || !canToggleMarkAtCurrentFrame) {
      return;
    }

    _session._timelineController.toggleMarkForLayer(layerId: layer.id);
    _session._notifyChanged();
  }

  bool hasMarkForLayer(Layer layer, int frameIndex) {
    if (!layerKindHoldsDrawings(layer.kind)) {
      return false;
    }
    return _session._timelineController.hasMarkAt(
      layer: layer,
      frameIndex: frameIndex,
    );
  }
}

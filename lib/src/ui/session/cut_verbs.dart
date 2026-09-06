part of '../editor_session_manager.dart';

/// The CUT VERBS — creating, deleting, duplicating, renaming and moving
/// the active cut, linking it, resizing its canvas, its note, guides and
/// thumbnail frame — as their own object. Each is a command over the
/// repository; the session stays the facade that names them.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: nothing of its own and twelve
/// session members touched; the rest reads none of it. It reaches the
/// session through `_session`.
class _CutVerbs {
  _CutVerbs(this._session);

  final EditorSessionManager _session;

  void createCut() {
    final plan = _session.cutCreationPlan;
    if (plan == null) {
      return;
    }
    _session.cutCommandCoordinator.createCut(
      trackId: plan.trackId,
      // New cuts inherit the active cut's canvas size, like new scenes in
      // TVPaint/Clip Studio inherit the project size.
      canvasSize: _session.activeCutOrNull?.canvasSize,
      placement: plan.index == null
          ? null
          : (
              index: plan.index,
              leadingGapFrames: plan.leadingGapFrames,
              duration: plan.duration,
            ),
    );
    _session.refreshAfterCutCommand();
    _session.notifyChanged();
  }

  void resizeActiveCutCanvas(
    CanvasSize canvasSize, {
    CanvasResizeAnchor anchor = CanvasResizeAnchor.center,
  }) {
    final cutId = _session.editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    _session.cutCommandCoordinator.resizeCutCanvas(
      cutId: cutId,
      canvasSize: canvasSize,
      anchor: anchor,
    );
    _session.refreshAfterCutCommand();
    _session.notifyChanged();
  }

  void duplicateActiveCut() {
    final cutId = _session.editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    _session.cutCommandCoordinator.duplicateCut(
      sourceCutId: cutId,
      targetTrackId: _session.selectedTrackId,
    );
    _session.refreshAfterCutCommand();
    _session.notifyChanged();
  }

  void deleteActiveCut() {
    // With a cut RANGE selection live, the delete command acts on the
    // whole run instead of the active cut (UI-R18 #1).
    if (_session.storyboardSelectedCutIds.isNotEmpty) {
      deleteSelectedCuts();
      return;
    }
    final cutId = _session.editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    _session.cutCommandCoordinator.deleteCut(cutId: cutId);
    _session.refreshAfterCutCommand();
    _session.notifyChanged();
  }

  CutPosition? get _activeCutPositionOrNull {
    final cutId = _session.editingSession.activeCutId;
    if (cutId == null) {
      return null;
    }
    return _session._cutReorderPlanner.findCutPosition(
      project: _session.repository.requireProject(),
      cutId: cutId,
    );
  }

  CutPosition get _activeCutPosition {
    final position = _activeCutPositionOrNull;
    if (position == null) {
      throw StateError(
        'Active Cut not found: ${_session.editingSession.activeCutId}',
      );
    }
    return position;
  }

  bool get canMoveActiveCutLeft => _canMoveActiveCut(CutMoveDirection.left);

  bool get canMoveActiveCutRight => _canMoveActiveCut(CutMoveDirection.right);

  void moveActiveCutLeft() => _moveActiveCut(CutMoveDirection.left);

  void moveActiveCutRight() => _moveActiveCut(CutMoveDirection.right);

  bool _canMoveActiveCut(CutMoveDirection direction) {
    final position = _activeCutPositionOrNull;
    return position != null &&
        _session._cutReorderPlanner.canMove(position, direction);
  }

  /// ⛔ONE MOVE, WITH A SIGN. The two verbs used to be written out, guard
  /// and command and refresh each, so a step that stopped refreshing after
  /// the reorder would have done it in one direction only.
  void _moveActiveCut(CutMoveDirection direction) {
    final position = _activeCutPosition;
    if (!_session._cutReorderPlanner.canMove(position, direction)) {
      return;
    }
    _session.cutCommandCoordinator.reorderCut(
      trackId: position.trackId,
      cutId: position.cutId,
      newIndex: _session._cutReorderPlanner.moveTargetIndex(
        position,
        direction,
      ),
    );
    _session.refreshAfterCutCommand();
    _session.notifyChanged();
  }

  String? get activeCutNote => _session.activeCutOrNull?.metadata.note;

  void updateActiveCutNote(String note) {
    final cutId = _session.editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    _session.cutCommandCoordinator.updateCutNote(cutId: cutId, note: note);
    _session.refreshAfterCutCommand();
    _session.notifyChanged();
  }

  /// Whether the active cut's storyboard thumbnail is pinned to the
  /// playhead frame (drives the toolbar toggle's state).
  bool get isActiveCutThumbnailPinnedHere =>
      _session.activeCutOrNull?.metadata.thumbnailFrameIndex ==
          _session.timelineController.currentFrameIndex &&
      _session.activeCutOrNull?.metadata.thumbnailFrameIndex != null;

  /// Pins the active cut's storyboard thumbnail to the playhead frame, or
  /// releases the pin back to the first frame when pressed on the pinned
  /// frame itself (toggle; one undo step either way).
  void toggleActiveCutThumbnailFrame() {
    final cut = _session.activeCutOrNull;
    if (cut == null) {
      return;
    }
    final frame = _session.timelineController.currentFrameIndex;
    final pinned = cut.metadata.thumbnailFrameIndex;
    _session.cutCommandCoordinator.updateCutThumbnailFrame(
      cutId: cut.id,
      frameIndex: pinned == frame ? null : frame,
    );
    _session.refreshAfterCutCommand();
    _session.notifyChanged();
  }

  void renameActiveCut(String newName) {
    final cutId = _session.editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    _session.cutCommandCoordinator.renameCut(cutId: cutId, newName: newName);
    _session.refreshAfterCutCommand();
    _session.notifyChanged();
  }

  /// R26 #32: sets the PROJECT's frame rate (one undo step, no-op when
  /// unchanged). Everything timed — ruler seconds, sheet rows, playback,
  /// audio placement — reads this one axis, so this single write moves
  /// the whole project's time.
  /// The active cut's drawing guides — empty when parked in a gap.
  CutGuides get activeCutGuides =>
      _session.activeCutOrNull?.guides ?? CutGuides.empty;

  /// Writes the active cut's guides, fanning out to its 겸용 siblings in one
  /// undoable step (see [SetCutGuidesCommand]).
  ///
  /// Handle DRAGS call this once, at release. The live preview in between
  /// paints from the drag layer's own value and never touches the project,
  /// so a drag is one undo entry rather than one per pointer sample.
  void setActiveCutGuides(CutGuides guides) {
    final cut = _session.activeCutOrNull;
    if (cut == null || cut.guides == guides) {
      return;
    }
    _session.historyManager.execute(
      SetCutGuidesCommand(
        repository: _session.repository,
        cutId: cut.id,
        guides: guides,
      ),
    );
    _session.notifyChanged();
  }

  /// 겸용컷 생성: a new cut whose drawing layers are all LINKED to the
  /// active cut's (empty timelines — same pictures, own timing).
  void createLinkedCutFromActiveCut() {
    final cutId = _session.editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    _session.cutCommandCoordinator.createLinkedCut(sourceCutId: cutId);
    _session.refreshAfterCutCommand();
    _session.notifyChanged();
  }

  /// 겸용 변경 preview: what linking the active cut with [targetCutId]
  /// would do (drives the confirmation dialog's 안내문). Null when there
  /// is no active cut or the target is the active cut itself.
  ConvertToLinkedCutPlan? convertToLinkedCutPreview(CutId targetCutId) {
    final originCutId = _session.editingSession.activeCutId;
    if (originCutId == null || originCutId == targetCutId) {
      return null;
    }
    return _session.cutCommandCoordinator.convertToLinkedCutPreview(
      originCutId: originCutId,
      targetCutId: targetCutId,
    );
  }

  /// Cuts the active cut can 겸용-convert WITH (every other cut, all
  /// tracks — dialog picker data).
  List<({CutId id, String name})> get convertToLinkedCutCandidates {
    final activeCutId = _session.editingSession.activeCutId;
    if (activeCutId == null) {
      return const [];
    }
    return [
      for (final track in _session.repository.requireProject().tracks)
        for (final cut in track.cuts)
          if (cut.id != activeCutId) (id: cut.id, name: cut.name),
    ];
  }

  /// [convertToLinkedCutPreview] resolved to display strings for the
  /// 안내문 dialog. Null under the preview's own null conditions.
  ConvertToLinkedCutPreviewData? convertToLinkedCutPreviewData(
    CutId targetCutId,
  ) {
    final plan = convertToLinkedCutPreview(targetCutId);
    final originCut = _session.activeCutOrNull;
    if (plan == null || originCut == null) {
      return null;
    }
    final project = _session.repository.requireProject();
    Cut? targetCut;
    for (final track in project.tracks) {
      for (final cut in track.cuts) {
        if (cut.id == targetCutId) {
          targetCut = cut;
        }
      }
    }
    if (targetCut == null) {
      return null;
    }
    String layerName(Cut cut, LayerId layerId) =>
        cut.layers.firstWhere((layer) => layer.id == layerId).name;
    return ConvertToLinkedCutPreviewData(
      targetCutName: targetCut.name,
      linkingLayerNames: [
        for (final pair in plan.layerPairs)
          layerName(originCut, pair.originLayerId),
      ],
      layerNamesAppearingInTarget: [
        for (final id in plan.originOnlyLayerIds) layerName(originCut, id),
      ],
      layerNamesAppearingInOrigin: [
        for (final id in plan.targetOnlyLayerIds) layerName(targetCut, id),
      ],
      replacedFrameCount: plan.replacedFrameCount,
      joiningFrameCount: plan.joiningFrameCount,
      linksAnything: plan.linksAnything,
      canvasSizesDiffer: originCut.canvasSize != targetCut.canvasSize,
    );
  }

  /// 겸용 변경: links the active cut (origin — 원본 승리) with
  /// [targetCutId]. Callers confirm through the preview dialog first.
  void convertActiveCutToLinked(CutId targetCutId) {
    final originCutId = _session.editingSession.activeCutId;
    if (originCutId == null || originCutId == targetCutId) {
      return;
    }
    _session.cutCommandCoordinator.convertCutToLinked(
      originCutId: originCutId,
      targetCutId: targetCutId,
    );
    _session.refreshAfterCutCommand();
    _session.notifyChanged();
  }

  /// Whether the selection can delete: cuts selected AND at least one
  /// cut survives (the project never empties).
  bool get canDeleteSelectedCuts {
    final selection = _session._liveSelectedCutIds;
    if (selection.isEmpty) {
      return false;
    }
    var total = 0;
    for (final track in _session.repository.requireProject().tracks) {
      total += track.cuts.length;
    }
    return total > selection.length;
  }

  /// Deletes every selected cut as ONE undo step (UI-R18 #1: the cut
  /// delete button acts on the selection).
  void deleteSelectedCuts() {
    if (!canDeleteSelectedCuts) {
      return;
    }
    _session.cutCommandCoordinator.deleteCuts(
      cutIds: _session._liveSelectedCutIds,
    );
    _session.clearStoryboardCutSelection();
    _session.refreshAfterCutCommand();
    _session.notifyChanged();
  }
}

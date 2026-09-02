part of '../editor_session_manager.dart';

/// The STORYBOARD CURSOR — what the cell under the storyboard cursor is,
/// and the verbs that act there: the comma, deleting the block, creating an
/// SE entry or a panel, the cell action — as its own object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: nothing of its own and seventeen
/// session members touched. It reaches the session through `_session`.
class _StoryboardCursor {
  _StoryboardCursor(this._session);

  final EditorSessionManager _session;

  /// Why the storyboard toggle is refused, or null when it is allowed.
  ///
  /// A cut holds at most ONE storyboard row: the conte has one strip per
  /// cut and the coverage rule has one row to tile it. The toggle says so
  /// rather than silently doing nothing, and rather than making the second
  /// row that used to red-screen the V row.
  String? get targetLayerStoryboardRefusal {
    final targetLayer = _session._targetLayerForKindToggle;
    if (targetLayer == null || targetLayer.kind == LayerKind.storyboard) {
      return null;
    }
    final cut = _session.activeCutOrNull;
    if (cut == null ||
        cutAcceptsAnotherStoryboardLayer(cut, exceptLayerId: targetLayer.id)) {
      return null;
    }
    return AppText.strings.sbOneStoryboardRowPerCut;
  }

  /// Writes a conte cell's ACTION text, undoably.
  ///
  /// A cell is a panel of the cut's storyboard row, so the text lands on the
  /// exposure that OPENS it — block-owned like the inbetween dots, which is
  /// what lets it ride every move and copy with no re-indexing. Typing into
  /// a cut with no storyboard row does nothing yet: there is no block to
  /// hang it on until the row exists.
  void setStoryboardCellAction({
    required CutId cutId,
    required int cellIndex,
    required String action,
  }) {
    final cut = _session.cutById(cutId);
    if (cut == null) {
      return;
    }
    final layer = storyboardLayerForCut(cut);
    if (layer == null) {
      return;
    }
    final cells = storyboardCoverageCells(
      timeline: layer.timeline,
      cutDuration: cut.duration,
    );
    if (cellIndex < 0 || cellIndex >= cells.length) {
      return;
    }
    final blockStart = cells[cellIndex].startIndex;
    final entry = layer.timeline[blockStart];
    if (entry == null || !entry.isDrawing || entry.ghost) {
      return;
    }
    _session._cutCommandCoordinator.updateExposureMemo(
      cutId: cutId,
      layerId: layer.id,
      blockStartIndex: blockStart,
      memo: (entry.memo ?? const ExposureMemo.empty()).copyWith(
        actionMemo: action,
      ),
    );
    _session._notifyChanged();
  }

  /// The BLOCK under the storyboard cursor, whatever its kind: the standing
  /// V row's cut, the standing S row's SE block, or the transition row's
  /// span. Null where the cursor covers nothing (a gap is an honest
  /// nothing, not a fallback to the other panel's subject).
  _StoryboardCursorBlock? _storyboardCursorBlockOrNull() {
    switch (_session.selectedRow) {
      case LayerRowAddress(:final layerId)
          when _session.isTrackTransitionLayerId(layerId):
        final span = _session.transitionSpanAt(_session.editingGlobalFrame);
        if (span == null) {
          return null;
        }
        return _StoryboardCursorTransitionSpan(span.key, span.value.length);
      case LayerRowAddress(:final layerId):
        final global = _session.trackSeGlobalLayerById(layerId);
        final frame = _session.editingGlobalFrame;
        if (global == null || frame < 0) {
          return null;
        }
        final block = coveringDrawingBlockAt(global.timeline, frame);
        if (block == null || block.entry.ghost) {
          return null;
        }
        return _StoryboardCursorSeBlock(layerId, block.startIndex);
      case LaneRowAddress():
        // A lane row holds keys, not blocks — the lane-verb family owns it.
        return null;
      case TrackRowAddress():
        // Not parked in a gap ⇒ the cut-local playhead sits inside the
        // ACTIVE cut, so the cut under the cursor is that cut by
        // construction (the storyboard's cell press promotes it).
        if (_session.editingPlayheadInGap) {
          return null;
        }
        final cut = _session.activeCutOrNull;
        if (cut == null) {
          return null;
        }
        // D28: with a storyboard layer on the cut, the frame verbs target
        // the PANEL under the cut-local cursor. A ghost or uncovered cell
        // (junk the coverage rule merely tolerates) falls back to the cut
        // block rather than lighting a verb the machinery will refuse
        // (T25); a cut with NO storyboard layer keeps the old cut-block
        // law outright.
        final row = storyboardLayerForCut(cut);
        if (row != null) {
          final panel = coveringDrawingBlockAt(
            row.timeline,
            _session._timelineController.currentFrameIndex,
          );
          if (panel != null && !panel.entry.ghost && panel.startIndex >= 0) {
            return _StoryboardCursorStoryboardPanel(
              cut,
              row,
              panel.startIndex,
              panel.entry.length!,
            );
          }
        }
        return _StoryboardCursorCutBlock(cut);
    }
  }

  /// Whether the storyboard's comma press (1/2/3/4/N) has a target: a live
  /// selection's blocks — either axis — else the block under the cursor.
  bool get canSetCommaForStoryboardCursor {
    if (_session._selectionBlockStartsByLayer() != null) {
      return true;
    }
    // Its own dispatch already stops at a live band ([setCommaForStoryboardCursor]
    // returns inside the selection branch), so the gate stops there too —
    // otherwise the band falls through to the CURSOR rung and lights the
    // buttons off a cut block the press will never reach.
    if (_session.cellSelectionClaimsSubject) {
      return false;
    }
    return switch (_storyboardCursorBlockOrNull()) {
      null => false,
      // ⛔An SE block used to answer `activeCutOrNull != null` here, on the
      // grounds that "a parked playhead has no cut to lens through" — the
      // lens is 0 for a track row and the lookup no longer wants a cut
      // (H11). A global row is reachable wherever it is standing.
      _StoryboardCursorSeBlock() ||
      _StoryboardCursorCutBlock() ||
      _StoryboardCursorTransitionSpan() ||
      _StoryboardCursorStoryboardPanel() => true,
    };
  }

  /// Whether the storyboard's delete has a block under the cursor (its
  /// selection rungs are asked separately — see the toolbar context).
  bool get canDeleteBlockAtStoryboardCursor =>
      switch (_storyboardCursorBlockOrNull()) {
        null => false,
        // H11: a track row answers wherever it stands — see the create gate.
        _StoryboardCursorSeBlock() ||
        _StoryboardCursorCutBlock() ||
        _StoryboardCursorTransitionSpan() ||
        // D28 ⚠️: delete keeps the CUT answer for now — whether the shared
        // delete should remove the PANEL instead is a recorded user
        // question (the frame pill retargeted; the verb matrix beyond it
        // is the user's to rule).
        _StoryboardCursorStoryboardPanel() => true,
      };

  /// Deletes THE BLOCK UNDER THE CURSOR, whatever its kind — the cut, the
  /// SE block, or the transition span, each through its own existing
  /// removal verb. One undo step each, like the cell delete it mirrors.
  void deleteBlockAtStoryboardCursor() {
    switch (_storyboardCursorBlockOrNull()) {
      case null:
        return;
      case _StoryboardCursorCutBlock() || _StoryboardCursorStoryboardPanel():
        _session.deleteActiveCut();
      case _StoryboardCursorSeBlock(:final layerId, :final blockStartIndex):
        // ⛔This used to return when `activeCutOrNull == null` — the fourth
        // copy of the sentence H11 retired (「a parked playhead has no cut
        // to lens through」, 유저 2026-08-22: 「각 행들은 독립적인 글로벌행이라
        // 뭐든 가능해야함」). The gate above already lights the verb in a
        // gap; the lookup below finds the track row without a cut; the verb
        // was the one still refusing. Found by the adversarial check on the
        // 2026-09-02 cut — the verb had no test of its own.
        _session._timelineController.deleteBlocksForLayers({
          layerId: [blockStartIndex],
        });
        _session._notifyChanged();
      case _StoryboardCursorTransitionSpan():
        _session.removeTransitionSpanAt(_session.editingGlobalFrame);
    }
  }

  /// Whether the frame `＋` can author a fresh SE entry on the standing S
  /// row: standing there, on an EMPTY cursor frame. That is the whole gate.
  ///
  /// ⛔It used to ask for an ACTIVE CUT as well, so the button went dead in
  /// a gap — 「S행이 컷이 없는 갭에서 프레임추가가 안됨. 버튼활성안됨」
  /// (유저 H11, 2026-08-22). The cut was never this row's business; it was
  /// standing in for `_requireLayer`, which demanded a cut before it would
  /// reach the track's own layers. That lookup answers for a track row now.
  bool get canCreateSeEntryAtStoryboardCursor {
    // Standing on one of the row's LANES answers with the row (C3-lane-move,
    // and [LaneRowAddress]'s own law: standing on a property must never cost
    // you the layer).
    final rowLayerId = _session.selectedRow.owningLayerId;
    if (rowLayerId == null || _session.isTrackTransitionLayerId(rowLayerId)) {
      return false;
    }
    final global = _session.trackSeGlobalLayerById(rowLayerId);
    final frame = _session.editingGlobalFrame;
    return global != null &&
        frame >= 0 &&
        coveringDrawingBlockAt(global.timeline, frame) == null;
  }

  /// One blank one-frame dialogue entry at the cursor — the cut-scoped SE
  /// creation ([_session.createSeEntryAtCurrentFrame]) said of the standing row, via
  /// the SAME fills funnel the track-range create commits through.
  void createSeEntryAtStoryboardCursor() {
    if (!canCreateSeEntryAtStoryboardCursor) {
      return;
    }
    final row = _session.selectedRow as LayerRowAddress;
    final layerId = row.layerId;
    _session._frameSequence += 1;
    // ⚠️The fills funnel re-applies the track-SE display lens on the way in
    // (the active cut's global start) — pre-subtract the SAME expression,
    // exactly as [_createTrackSeEntriesForRange] does, or the entry lands
    // double-shifted.
    final commands = _session._timelineController
        .drawingFramesCommandsForLayers({
          layerId: [
            (
              startIndex:
                  _session.editingGlobalFrame -
                  _session.activeCutGlobalStartFrame,
              length: 1,
              frameId: FrameId(_session._nextFrameId(layerId)),
              name: '',
            ),
          ],
        });
    if (commands.isEmpty) {
      return;
    }
    _session._historyManager.execute(
      commands.length == 1
          ? commands.single
          : CompositeCommand(
              description: 'Create SE entry',
              commands: commands,
            ),
    );
    _session._notifyChanged();
  }

  /// D28: whether the frame ＋ can DIVIDE the storyboard panel under the
  /// cursor. An existing division START refuses — there is nothing to
  /// divide there (the timeline's own creation law); gate and dispatch
  /// read the ONE cursor resolver (T25).
  bool get canCreateStoryboardPanelAtCursor {
    if (_storyboardCursorBlockOrNull() case _StoryboardCursorStoryboardPanel(
      :final panelStartIndex,
    )) {
      return _session._timelineController.currentFrameIndex != panelStartIndex;
    }
    return false;
  }

  /// D28: divides the panel under the cursor — the covering division
  /// splits, the new drawing taking the rest of the hold, exactly as the
  /// timeline's ＋ divides a held block.
  void createStoryboardPanelAtCursor() {
    if (_storyboardCursorBlockOrNull() case _StoryboardCursorStoryboardPanel(
      :final row,
      :final panelStartIndex,
    )) {
      if (_session._timelineController.currentFrameIndex == panelStartIndex) {
        return;
      }
      _session._frameSequence += 1;
      _session._timelineController.createDrawingFrameForLayer(
        layerId: row.id,
        frameId: FrameId(_session._nextFrameId(row.id)),
      );
      _session._notifyChanged();
    }
  }
}

part of '../editor_workspace.dart';

/// The FLIP HUD — the snapshot the flip HUD shows for the row you stand on,
/// in the panel you are working in, and keeping its axis in step with that
/// panel — as its own object.
///
/// 🚨A collaborator carved out of `_EditorWorkspaceState` (the audit's SRP cut,
/// 2026-09-02). It reaches the State through `_state`.
class _WorkspaceFlipHud {
  _WorkspaceFlipHud(this._state);

  final _EditorWorkspaceState _state;

  /// F-28: the canvas flip reads its frame direction off the sheet the user
  /// is looking at — 「타임라인패널 x시트일 경우 … 세로가 프레임이동 가로가
  /// 레이어이동 되도록. 그게 직관적임」.
  ///
  /// The sheet is the PANEL BEING WORKED IN (유저 2026-09-24: 「마지막으로 만진
  /// 패널」): the X-sheet runs its frames down the page and the storyboard
  /// never does. ↩️It followed the timeline's switch alone, so with the
  /// timeline turned to an X-sheet a flip over the storyboard walked its
  /// rows sideways.
  ///
  /// Told to the HUD rather than threaded down to the gesture layer: the HUD
  /// is already the one object this shell and the canvas gesture both hold,
  /// and it is the flip's own state.
  void syncFlipAxis() {
    final vertical =
        _state.widget.session.workingPanel == WorkingPanel.timeline &&
        _state._timelineOrientation.value == TimelineOrientation.vertical;
    _state.widget.flipHud?.framesRunVertically = vertical;
  }

  /// What the flip HUD draws: the rows the panel being worked in is
  /// DISPLAYING, in its order, filtered and folded exactly as they are on
  /// screen.
  ///
  /// Same inputs as [_state._stepDisplayedLayer] on purpose — the window and
  /// the walk must not be able to disagree about which rows exist. The HUD
  /// reads this AFTER a step has landed; it never predicts one.
  FlipHudSnapshot flipHudSnapshot(FlipHudAxis axis) {
    final session = _state.widget.session;
    if (session.workingPanel == WorkingPanel.storyboard) {
      // The storyboard's own rows, drawn by the panel that stacks them.
      // ↩️This drew the TIMELINE's rows whatever panel you were in, so a
      // flip on the V row showed the active layer's blocks while it walked
      // cuts.
      return _state._storyboardRows.snapshotFor(axis) ??
          _flipHudTrackSnapshot(session);
    }
    final cut = session.activeCutOrNull;
    if (cut == null) {
      // Parked in a GAP. There is no cut, so there are no layer rows —
      // but there IS a row: the track, whose blocks are its panels. That is
      // the axis the flip actually walks here, so the window shows it
      // rather than going blank on the one occasion you most need to know
      // where you are.
      return _flipHudTrackSnapshot(session);
    }
    final rows = buildTimelineDisplayRows(
      layers: horizontalLayerDisplayOrder(session.layers),
      expandedLayerIds: _state._expandedLaneLayerIds.value,
      lanesForLayer: (layer) => timelineLanesForLayer(
        layer: layer,
        session: session,
        expandedGroupKeys: _state._expandedLaneGroupKeys.value,
      ),
      hiddenSections: session.railView.hiddenSections.value,
      rowFilter: session.railView.rowFilter.value,
      collapsedAttachBaseIds: session.railView.collapsedAttachBaseIds.value,
      activeLayerId: session.activeLayerId,
      fxEnabledOf: session.effectsAndFx.isLayerFxEnabled,
      stack: session.layers,
    );
    if (rows.isEmpty) {
      return FlipHudSnapshot.empty;
    }
    var rowIndex = indexOfDisplayRow(
      rows,
      current: session.currentRow,
      activeLayerId: session.activeLayerId,
    );
    if (rowIndex == -1) {
      rowIndex = 0;
    }
    // A frame-axis window draws ONE row, so only that row's blocks are
    // worth building. The others still take their place in the list (the
    // row index has to keep meaning what it means), but scanning every
    // layer's timeline for runs nobody draws is work per flip step.
    final onlyCurrent = axis == FlipHudAxis.frame;
    final hudRows = <FlipHudRow>[
      for (var index = 0; index < rows.length; index += 1)
        if (rows[index].lane case final lane?)
          flipHudLaneRow(
            lane,
            kind: rows[index].layer.kind,
            withRuns: !onlyCurrent || index == rowIndex,
          )
        else
          flipHudLayerRow(
            rows[index].layer,
            withRuns: !onlyCurrent || index == rowIndex,
            celNameAt: session.frameVerbs.frameNameForLayer,
            // The lookup the storyboard's transition row draws its terms with.
            spanDefById: session.camera.cameraInstructionSet.defById,
          ),
    ];
    return FlipHudSnapshot(
      rows: hudRows,
      rowIndex: rowIndex,
      frameIndex: session.currentFrameIndex,
      // The axis has to reach wherever the cursor stands: rightward the
      // flip walks past the cut's end into the timeline's runway, and an
      // axis that stopped at the duration would show the last column as
      // the one you are on.
      frameCount: math.max(cut.duration, session.currentFrameIndex + 1),
      playbackFrameCount: cut.duration,
    );
  }

  /// The gap's window: one row — the track — with its panels as blocks.
  ///
  /// Same model, same columns, same haptic rule; only the material
  /// changes, which is exactly what the flip itself does down in the
  /// session. A panel is a run, the space between cuts is uncovered.
  FlipHudSnapshot _flipHudTrackSnapshot(EditorSessionManager session) {
    final trackId = session.selectedTrackId;
    final entries = [
      for (final entry in session.projectSettings.projectLayout())
        if (entry.trackId == trackId) entry,
    ];
    if (entries.isEmpty) {
      return FlipHudSnapshot.empty;
    }
    // Where the storyboard shows the playhead — the frame the track's flip
    // leaves from ([TrackFrameAxis.storyboardFrameOf]).
    final globalFrame =
        storyboardPlayheadFrame(session) ?? session.editingGlobalFrame;
    return FlipHudSnapshot(
      rows: [
        flipHudTrackRow(
          name: session.trackOwningCut(entries.first.cutId)?.name ?? 'Track',
          panels: storyboardPanelsOnTrack(entries),
        ),
      ],
      rowIndex: 0,
      frameIndex: globalFrame,
      // Rightwards never runs out, so the playhead can stand PAST the
      // last cut. The axis has to reach wherever it is standing or the
      // window would show the final cut as the column you are on.
      frameCount: math.max(entries.last.endFrame, globalFrame + 1),
    );
  }
}

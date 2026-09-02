part of '../editor_workspace.dart';

/// The FLIP HUD — the snapshot the flip HUD shows for the active row or
/// track, and keeping its axis in step with the timeline — as its own
/// object.
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
  /// Told to the HUD rather than threaded down to the gesture layer: the HUD
  /// is already the one object this shell and the canvas gesture both hold,
  /// and it is the flip's own state.
  void syncFlipAxisWithTimeline() {
    _state.widget.flipHud?.framesRunVertically =
        _state._timelineOrientation.value == TimelineOrientation.vertical;
  }

  /// What the flip HUD draws: the rows the timeline is DISPLAYING, in its
  /// order, filtered and folded exactly as they are on screen.
  ///
  /// Same inputs as [_state._stepDisplayedLayer] on purpose — the window and the
  /// walk must not be able to disagree about which rows exist. The HUD
  /// reads this AFTER a step has landed; it never predicts one.
  FlipHudSnapshot flipHudSnapshot(FlipHudAxis axis) {
    final session = _state.widget.session;
    final cut = session.activeCutOrNull;
    if (cut == null) {
      // Parked in a GAP. There is no cut, so there are no layer rows —
      // but there IS a row: the track, whose blocks are its cuts. That is
      // the axis the flip actually walks here (`_flipCuts`), so the
      // window shows it rather than going blank on the one occasion you
      // most need to know where you are.
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
      hiddenSections: _state._hiddenTimelineSections.value,
      rowFilter: _state._timelineRowFilter.value,
      collapsedAttachBaseIds: _state._collapsedAttachBaseIds.value,
      activeLayerId: session.activeLayerId,
      fxEnabledOf: session.isLayerFxEnabled,
      stack: session.layers,
    );
    if (rows.isEmpty) {
      return FlipHudSnapshot.empty;
    }
    final currentRow = session.currentRow;
    var rowIndex = -1;
    for (var index = 0; index < rows.length; index += 1) {
      final row = rows[index];
      final address = row.isLane
          ? LaneRowAddress(row.layer.id, row.lane!.laneId)
          : LayerRowAddress(row.layer.id);
      if (address == currentRow) {
        rowIndex = index;
        break;
      }
    }
    if (rowIndex == -1) {
      // The row on record is not on screen — a track row (the storyboard
      // owns one), or a row a filter has hidden. The ↑/↓ walk falls back
      // to the active layer's own row in exactly this case, so the window
      // does too rather than pointing at whatever sits at the top.
      final activeLayerId = session.activeLayerId;
      for (var index = 0; index < rows.length; index += 1) {
        if (!rows[index].isLane && rows[index].layer.id == activeLayerId) {
          rowIndex = index;
          break;
        }
      }
    }
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
        _state._collapsedRows.flipHudRow(
          rows[index],
          session,
          withRuns: !onlyCurrent || index == rowIndex,
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

  /// The gap's window: one row — the track — with its cuts as blocks.
  ///
  /// Same model, same columns, same haptic rule; only the material
  /// changes, which is exactly what the flip itself does down in the
  /// session. A cut is a run, the space between cuts is uncovered.
  FlipHudSnapshot _flipHudTrackSnapshot(EditorSessionManager session) {
    final trackId = session.selectedTrackId;
    final entries = [
      for (final entry in session.projectTimelineLayout())
        if (entry.trackId == trackId) entry,
    ];
    if (entries.isEmpty) {
      return FlipHudSnapshot.empty;
    }
    final globalFrame = session.editingGlobalFrame;
    return FlipHudSnapshot(
      rows: [
        FlipHudRow(
          name: session.trackOwningCut(entries.first.cutId)?.name ?? 'Track',
          kind: LayerKind.storyboard,
          // A track is not a layer; the rail shows its name alone.
          showsKindIcon: false,
          // The space between cuts is not a missing drawing, so it
          // carries no timesheet X.
          holdsDrawings: false,
          runs: [
            for (final entry in entries)
              FlipHudRun(
                startIndex: entry.startFrame,
                length: entry.duration,
                label: entry.cut.name,
              ),
          ],
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

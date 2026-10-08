part of '../storyboard_panel.dart';

/// WHERE THE STORYBOARD STANDS — the ring around the standing cell, the
/// block under the playhead, the active cut of a track and the band a
/// track row spans — as its own object.
///
/// 🚨A collaborator carved out of `_StoryboardPanelState` (the audit's SRP
/// cut, 2026-09-02). Measured before cutting: one State member shared.
/// It reaches the State through `_state`.
class _StoryboardStanding {
  _StoryboardStanding(this._state);

  final _StoryboardPanelState _state;

  /// The ACTIVE cut when it lives on [track]; null otherwise (the rail's
  /// lane controls then stand down, like the S-row layer controls).
  Cut? activeCutOf(Track track) {
    for (final cut in track.cuts) {
      if (cut.id == _state.widget.activeCutId) {
        return cut;
      }
    }
    return null;
  }

  /// The cut sitting under the current global playhead on track
  /// [trackIndex] (UI-R13 #2: the V-row fx/eye act on THIS, each track
  /// independently). Null when the playhead is unwired or the index is a
  /// gap on this track — the buttons then no-op, never gray out.
  Cut? cutAtPlayheadOn(int trackIndex) {
    final globalFrame = _state.widget.playheadFrame?.value;
    if (globalFrame == null) {
      return null;
    }
    for (final entry in buildStoryboardTimelineLayout(_state.widget.project)) {
      if (entry.trackIndex == trackIndex &&
          globalFrame >= entry.startFrame &&
          globalFrame < entry.endFrame) {
        return entry.cut;
      }
    }
    return null;
  }

  /// Where you STAND on this track, said to semantics and to the probes that
  /// read it: the cell under the playhead on the row you stand on. It
  /// paints nothing — the timeline's standing cell ([TimelineCursorLayer]),
  /// on this rail's own row geometry, on every row kind (S rows, the V row
  /// and the lane rows of both).
  ///
  /// 🗣️F-212 (유저 2026-09-28): 「현재 블록이나 갭 등 위치를 알리는 실루엣
  /// 라인 … 삭제하고싶음. 현재 재생헤드의 세로 바탕색 오버레이만으로
  /// 충분」 — the playhead's wash says where you stand. ↩️The row you stood
  /// on wore a ring round the block under the playhead (the cut on the V
  /// row, the sound or the transition span on the S rows — riding a drag,
  /// H12) and a 3px ring on a cell with no block (R5 ③b).
  ///
  /// Subscribes to the cursor and the current row itself, the cursor-layer
  /// pattern: a playhead tick or a stand-elsewhere moves THIS overlay and
  /// rebuilds no rows. 🚨[TimelineCurrentRowHooks.currentRow] publishes
  /// WITHOUT a session notify, so it has to be read inside its own
  /// subscription — read outside, this would answer for the row the user
  /// has already left.
  ///
  /// That current row is the session's GLOBAL answer, and its default is a
  /// cel layer inside the active cut — a row this rail does not have. So a
  /// row this rail cannot place falls back to [StoryboardPanel.selectedRow],
  /// the rail's own answer, exactly as the timeline's falls back from an
  /// off-screen lane to the active layer's row: showing nothing reads as
  /// broken rather than as elsewhere.
  Widget trackStandingCell(Track track, TimelineScale scale) {
    final currentRow = _state.widget.currentRowHooks?.currentRow;
    final playhead = _state.widget.playheadFrame;
    if (currentRow == null || playhead == null || scale.pixelsPerFrame <= 0) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<TimelineRowAddress?>(
      valueListenable: currentRow,
      builder: (context, standing, _) {
        final on = _standingOn(track, standing);
        if (on == null) {
          return const SizedBox.shrink();
        }
        final standingRow = on.row;
        final rowBand = on.band;
        final dragPreview = _state.widget.dragPreview;
        return ListenableBuilder(
          listenable: Listenable.merge([playhead, ?dragPreview]),
          builder: (context, _) {
            final frame = playhead.value;
            final unit = frame == null
                ? null
                : _standingUnit(track, standingRow, frame);
            return Stack(
              children: [
                if (unit != null) _washOver(unit, rowBand, scale),
                if (frame != null)
                  Positioned(
                    left: scale.leftForFrame(frame),
                    top: rowBand.top,
                    width: scale.spanWidth(frame, frame + 1),
                    height: rowBand.height,
                    child: Semantics(
                      key: const ValueKey<String>('storyboard-standing-cell'),
                      label: AppText.strings.tlSelectedCell,
                      container: true,
                      child: const SizedBox.expand(),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  /// The row you stand on in [track]'s group and the band it lies in: the
  /// session's [current] row where this rail has it, the rail's own
  /// [StoryboardPanel.selectedRow] otherwise (see [trackStandingCell]) — ONE
  /// answer for the standing cell, the wash and the V row's bands.
  ({TimelineRowAddress row, ({double top, double height}) band})? _standingOn(
    Track track,
    TimelineRowAddress? current,
  ) {
    for (final row in [current, _state.widget.selectedRow]) {
      if (row == null) {
        continue;
      }
      final band = _trackRowBand(track, row);
      if (band != null) {
        return (row: row, band: band);
      }
    }
    return null;
  }

  /// The cut whose bands wear the standing wash on [track]'s V row — the cut
  /// under the playhead while that row is the one you stand on; null where
  /// the panel is handed no cut.
  ValueListenable<CutId?>? standingCutOn(Track track) {
    final cut = _state.widget.cutUnderPlayhead;
    if (cut == null) {
      return null;
    }
    final currentRow = _state.widget.currentRowHooks?.currentRow;
    return StandingCut(
      changes: Listenable.merge([cut, ?currentRow]),
      standsOnRow: () =>
          _standingOn(track, currentRow?.value)?.row ==
          TrackRowAddress(track.id),
      cut: cut,
    );
  }

  /// 🗣️F-248 (유저 2026-09-30 「외곽라인말고 블럭을 바탕색으로서 강조색
  /// 표시. 전처럼 연하게」, 10-01 「재생헤드가 선 블록」): the unit you stand on
  /// wears the standing wash, as on the timeline — an S row's sound or span,
  /// a lane's cell. The V row's cut wears it on its bands instead, never
  /// over its pictures ([standingCutOn]; 10-01 「썸네일 제외한 띠 부분」) —
  /// so no unit here.
  StandingUnit? _standingUnit(
    Track track,
    TimelineRowAddress row,
    int frame,
  ) => switch (row) {
    TrackRowAddress() => null,
    LaneRowAddress() => (
      startIndex: frame,
      endIndexExclusive: frame + 1,
      block: false,
    ),
    LayerRowAddress(:final layerId) => _unitOn(track, layerId, frame),
  };

  /// The standing wash over [unit], in the row's [band].
  Widget _washOver(
    StandingUnit unit,
    ({double top, double height}) band,
    TimelineScale scale,
  ) {
    return Positioned(
      left: scale.leftForFrame(unit.startIndex),
      top: band.top,
      width: scale.spanWidth(unit.startIndex, unit.endIndexExclusive),
      height: band.height,
      child: DecoratedBox(
        key: const ValueKey<String>('storyboard-standing-wash'),
        decoration: timelineStandingWashDecorationAt(
          cellExtent: scale.pixelsPerFrame,
          crossExtent: band.height,
          block: unit.block,
        ),
      ),
    );
  }

  /// The unit under [frame] on a layer row of the track: what a click there
  /// selects ([trackRowMaterialBlocks] — its sound, its span or its panel,
  /// else the one cell), read off the row as it is shown: through a drag,
  /// previewed (H12); while a take rolls, the take.
  ///
  /// The CONTE row is shown as the cuts' conte layers on the track's axis
  /// ([trackConteRowShown]), on the cuts as a drag in flight lays them — so
  /// its unit is the panel, and a cut with no conte layer holds one cell.
  StandingUnit _unitOn(
    Track track,
    LayerId layerId,
    int frame,
  ) {
    if (trackIdOfConteRow(layerId) != null) {
      return standingUnitAt(
        lanes: [
          trackRowMaterialBlocks(
            trackConteRowShown(track.id, _cutsAsShownOn(track)),
            spans: false,
          ),
        ],
        index: frame,
      );
    }
    final spans = layerId == track.transitionLayer.id;
    var shown = timelineDragPreviewGlobalLayerFor(
      _state.widget.dragPreview?.value,
      layerId,
    );
    if (shown == null && spans) {
      shown = track.transitionLayer;
    }
    for (var slot = 0; shown == null && slot < _seSlotCount(track); slot++) {
      if (_trackSeAt(track, slot)?.id == layerId) {
        shown = _state._seDisplayAt(track, slot);
      }
    }
    return standingUnitAt(
      lanes: [if (shown != null) trackRowMaterialBlocks(shown, spans: spans)],
      index: frame,
    );
  }

  /// [track]'s cuts on its axis as the panel shows them now — re-timed by a
  /// drag in flight ([_StoryboardRailRows._previewedEntriesFor]), else as
  /// committed.
  List<StoryboardTimelineLayoutEntry> _cutsAsShownOn(Track track) {
    final trackIndex = _state.widget.project.tracks.indexOf(track);
    return _state._railRows._previewedEntriesFor(
      trackIndex,
      _state.widget.dragPreview?.value,
      [
        for (final entry in buildStoryboardTimelineLayout(
          _state.widget.project,
        ))
          if (entry.trackIndex == trackIndex) entry,
      ],
    );
  }

  /// The cross-axis band [row] occupies inside this track's group, or null
  /// when the row belongs to another track (or is not on screen).
  ///
  /// Reads the SAME table the selection bands and the select-drag's row
  /// resolver read, so the row a visual lands on and the row the gesture
  /// reaches cannot become two different answers.
  ({double top, double height})? _trackRowBand(
    Track track,
    TimelineRowAddress row,
  ) {
    var y = 0.0;
    for (final slot in _state._railRows._trackGroupRowGeometry(track)) {
      if (_standingAddressOf(slot) == row) {
        return (top: y, height: slot.height);
      }
      y += slot.height;
    }
    return null;
  }
}

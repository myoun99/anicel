part of '../storyboard_panel.dart';

/// One track's GROUP of the sheet as its rows are drawn: the track, its V
/// row's name, and its cuts on the track's axis — what the V row's blocks
/// are made of.
typedef _SheetTrackGroup = ({
  Track track,
  String vRowName,
  List<StoryboardTimelineLayoutEntry> cuts,
});

/// THE STORYBOARD AS A SHEET — the rows this panel stacks, in its order, and
/// the flip window's picture of them — handed to the shell
/// ([StoryboardRowsChannel]) for the time the storyboard is the panel being
/// worked in.
///
/// 🗣️유저 2026-09-24: 「마지막으로 만진 패널 … v행에 서있다가 위 키 누르면
/// S1행으로 … 위아래 이동이 타임라인 내부로 샌다거나 그런거 싹 다 해결」.
///
/// ★Read off [_StoryboardRailRows._trackGroupRowGeometry] — the one table
/// this rail, its bands and its select-drag already read — so the walk, the
/// window and the screen are the same list.
///
/// A collaborator of `_StoryboardPanelState`, reaching it through `_state`.
class _StoryboardSheet {
  _StoryboardSheet(this._state);

  final _StoryboardPanelState _state;

  /// Every track's rows, top to bottom — each track's group as the strip
  /// column stacks it (the transition row, the S rows and their lanes, the
  /// V row and its lanes).
  List<TimelineRowAddress> rows() => [
    for (final track in _state.widget.project.tracks)
      for (final slot in _state._railRows._trackGroupRowGeometry(track))
        ?(slot.row ?? slot.laneRow),
  ];

  /// The flip window's picture of [rows]: each row's blocks on the TRACK's
  /// axis — the storyboard's rows are the track's own, not a cut's copy —
  /// drawn by the builders the timeline's window uses.
  FlipHudSnapshot flipHudSnapshot(FlipHudAxis axis) {
    final project = _state.widget.project;
    final layout = buildStoryboardTimelineLayout(project);
    final addresses = rows();
    if (addresses.isEmpty || layout.isEmpty) {
      return FlipHudSnapshot.empty;
    }
    final standing = _state.widget.currentRowHooks?.currentRow.value;
    var rowIndex = standing == null ? -1 : addresses.indexOf(standing);
    if (rowIndex == -1) {
      rowIndex = _state.widget.selectedRow == null
          ? -1
          : addresses.indexOf(_state.widget.selectedRow!);
    }
    if (rowIndex == -1) {
      rowIndex = 0;
    }
    // A frame-axis window draws ONE row — the timeline window's rule.
    final onlyCurrent = axis == FlipHudAxis.frame;
    final hudRows = <FlipHudRow>[];
    for (var trackIndex = 0; trackIndex < project.tracks.length; trackIndex++) {
      final track = project.tracks[trackIndex];
      final group = (
        track: track,
        vRowName: _vRowName(trackIndex),
        cuts: [
          for (final entry in layout)
            if (entry.trackId == track.id) entry,
        ],
      );
      for (final slot in _state._railRows._trackGroupRowGeometry(track)) {
        final address = slot.row ?? slot.laneRow;
        if (address == null) {
          continue;
        }
        hudRows.add(
          _rowFor(
            group,
            address,
            withRuns: !onlyCurrent || hudRows.length == rowIndex,
          ),
        );
      }
    }
    final frame = _state.widget.playheadFrame?.value ?? 0;
    var end = 0;
    for (final entry in layout) {
      end = entry.endFrame > end ? entry.endFrame : end;
    }
    return FlipHudSnapshot(
      rows: hudRows,
      rowIndex: rowIndex,
      frameIndex: frame,
      // Rightwards never runs out: the axis reaches wherever the playhead
      // stands, past the last cut included.
      frameCount: frame + 1 > end ? frame + 1 : end,
    );
  }

  FlipHudRow _rowFor(
    _SheetTrackGroup group,
    TimelineRowAddress address, {
    required bool withRuns,
  }) {
    final track = group.track;
    switch (address) {
      case TrackRowAddress():
        return flipHudTrackRow(
          name: group.vRowName,
          panels: withRuns ? storyboardPanelsOnTrack(group.cuts) : const [],
        );
      case LayerRowAddress(:final layerId):
        final slot = _seSlotOf(track, layerId);
        return flipHudLayerRow(
          // The S row as this rail draws it (a take in flight stands in for
          // its lane), else the one other layer row a track group has.
          slot == -1
              ? track.transitionLayer
              : (_state._seDisplayAt(track, slot) ?? track.transitionLayer),
          withRuns: withRuns,
          // The strip's own writing on its blocks: the cel each opens with.
          celNameAt: (layer, frame) {
            final frameId = layer.timeline[frame]?.frameId;
            return frameId == null ? null : layer.frameById(frameId)?.name;
          },
          spanDefById: _state.widget.transitionDefById,
        );
      case LaneRowAddress(:final layerId, :final laneId):
        final carried = trackIdOfTransformLaneCarrier(layerId) != null;
        final lanes = carried
            ? _state._railRows._trackEffectLanes(track)
            : _state._railRows._seLanes(track, _seSlotOf(track, layerId));
        final lane = lanes.where((lane) => lane.laneId == laneId).firstOrNull;
        if (lane == null) {
          return const FlipHudRow(name: '', kind: LayerKind.se, runs: []);
        }
        return flipHudLaneRow(
          lane,
          // A V track's lanes belong to no layer — the track row's kind.
          kind: carried ? LayerKind.storyboard : LayerKind.se,
          withRuns: withRuns,
        );
    }
  }

  int _seSlotOf(Track track, LayerId layerId) {
    for (var slot = 0; slot < _seSlotCount(track); slot += 1) {
      if (_trackSeAt(track, slot)?.id == layerId) {
        return slot;
      }
    }
    return -1;
  }
}

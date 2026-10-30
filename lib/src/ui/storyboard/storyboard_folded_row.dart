part of '../storyboard_panel.dart';

/// THE ROW THE STORYBOARD STANDS ON, AS ITS FOLDED OVERLAY SHOWS IT.
///
/// 🗣️F-322 (유저 2026-10-09): 「콘티패널 간편오버레이가 제대로 서있는곳 행에
/// 맞춰서 안보여주고 V행고정인데 서있는곳 보여주도록. 타임라인패널이랑
/// 통일」. The timeline's folded row is the row you stand on, mounted as the
/// timeline draws it (⑩ 뿌리 C: the overlay owns no drawing code of its
/// own) at that row's height (D15: 「간편오버레이 높이도 해당 행
/// 높이에따라서 맞춤」). This is that, for this rail: the row's own label
/// and its own strip, built by this panel — display-only and chromeless —
/// for the workspace's overlay to lay over the artwork.
///
/// ↩️The folded storyboard showed its V row whatever row stood: the
/// workspace drew the track row itself and never asked which row it was.
///
/// The V row is the overlay's own track row still, and a lane is drawn from
/// the window's picture of it, as the timeline's folded lanes are.
///
/// A collaborator of `_StoryboardPanelState`, reaching it through `_state`.
class _StoryboardFolded {
  _StoryboardFolded(this._state);

  final _StoryboardPanelState _state;

  /// A window that never moves: the overlay lays its strip out over the
  /// frames it shows, so nothing is windowed past them (a zero viewport
  /// asks the painters for the strip's own bounds).
  static const ValueListenable<int> _still = AlwaysStoppedAnimation<int>(0);

  /// [standing] as the folded overlay shows it; null for the V row, and
  /// for a row this rail does not draw.
  ///
  /// Laid by the rail's own table from the rail's inputs as the session
  /// holds them NOW ([StoryboardPanel.railNow]): the workspace asks before
  /// this panel is rebuilt with them.
  StoryboardFoldedRow? rowFor(TimelineRowAddress standing) {
    final rows = switch (_state.widget.railNow) {
      final now? => _StoryboardRailRows(_state, inputs: now()),
      null => _state._railRows,
    };
    final project = rows._in.project;
    final tracks = project.tracks;
    for (var index = 0; index < tracks.length; index += 1) {
      for (final slot in rows._trackGroupRowGeometry(tracks[index])) {
        if (_standingAddressOf(slot) == standing) {
          return _rowOf(project, tracks[index], index, slot, standing);
        }
      }
    }
    return null;
  }

  StoryboardFoldedRow? _rowOf(
    Project project,
    Track track,
    int trackIndex,
    _StoryboardRailSlot slot,
    TimelineRowAddress standing,
  ) {
    if (slot.row is TrackRowAddress) {
      return null;
    }
    FlipHudSnapshot snapshot() =>
        _state._sheet.flipHudSnapshot(FlipHudAxis.frame, standing: standing);
    if (slot.lane) {
      return (
        height: slot.height,
        snapshot: snapshot,
        rail: null,
        frames: null,
        dashes: const [],
      );
    }
    final entries = [
      for (final entry in buildStoryboardTimelineLayout(project))
        if (entry.trackId == track.id) entry,
    ];
    final strip = _stripOf(project, track, trackIndex, slot, entries);
    return (
      height: slot.height,
      snapshot: snapshot,
      rail: strip.rail,
      frames: strip.frames,
      dashes: _StoryboardRailRows._dashedOn(slot, entries),
    );
  }

  /// [slot]'s label and strip — the rail's own widgets for its kind.
  _FoldedStrip _stripOf(
    Project project,
    Track track,
    int trackIndex,
    _StoryboardRailSlot slot,
    List<StoryboardTimelineLayoutEntry> entries,
  ) {
    if (slot.standRow case final stood?) {
      return switch (trackConteRowOf(stood.layerId)) {
        final conte? => _conte(track, conte.seat, entries, slot.height),
        null => _camera(project, track, entries, slot.height),
      };
    }
    if (slot.seSlot case final seSlot?) {
      return _se(track, (index: trackIndex, slot: seSlot), slot.height);
    }
    return _transition(track, slot.height);
  }

  _FoldedStrip _conte(
    Track track,
    int seat,
    List<StoryboardTimelineLayoutEntry> entries,
    double height,
  ) => (
    rail: () => _state._rows._conteLabel(track, seat, chromeless: true),
    frames: (context, geometry) => _StoryboardConteRow(
      trackId: track.id,
      seat: seat,
      layoutEntries: entries,
      width: 0,
      height: height,
      timelineScale: _state._scale,
      frameGeometry: geometry,
      windowBucket: _still,
      showSeconds: _state.widget.showSeconds,
      projectFrameRate: _state.widget.projectFrameRate,
      conteCelContent: _state.widget.conteCelContent,
      stepsUntilShown: _state.widget.stepsUntilShown,
    ),
  );

  _FoldedStrip _camera(
    Project project,
    Track track,
    List<StoryboardTimelineLayoutEntry> entries,
    double height,
  ) {
    final instructions = project.cameraInstructions;
    return (
      rail: () => _state._rows._cameraLabel(track, chromeless: true),
      frames: (context, geometry) => _StoryboardCameraRow(
        trackId: track.id,
        reaches: cameraRowReachesOf(
          entries,
          transitionRowSpans(track.transitionLayer, instructions),
        ),
        width: 0,
        height: height,
        timelineScale: _state._scale,
        frameGeometry: geometry,
        windowBucket: _still,
        viewportWidth: 0,
        instructionDefById: instructions.defById,
      ),
    );
  }

  /// An S row: [at] is its track's place among the tracks and its slot.
  _FoldedStrip _se(
    Track track,
    ({int index, int slot}) at,
    double height,
  ) => (
    rail: () => _state._rows._seLabel(track, at.slot, chromeless: true),
    frames: (context, geometry) => _StoryboardSeRow(
      trackIndex: at.index,
      slot: at.slot,
      layer: _state._seDisplayAt(track, at.slot),
      width: 0,
      height: height,
      timelineScale: _state._scale,
      projectFrameRate: _state.widget.projectFrameRate,
      frameGeometry: geometry,
      windowBucket: _still,
      viewportWidth: 0,
      showSeconds: _state.widget.showSeconds,
      audioPeaksFor: _state.widget.audioPeaksFor,
      moveRows: _state._railRows._seMoveRows(track),
    ),
  );

  _FoldedStrip _transition(Track track, double height) {
    final widget = _state.widget;
    final transition = track.transitionLayer;
    return (
      rail: () => _state._rows._transitionLabel(track, chromeless: true),
      frames: (context, geometry) => _StoryboardTransitionRow(
        trackId: track.id,
        layer:
            widget.transitionRowShown?.call(track, transition) ?? transition,
        width: 0,
        height: height,
        timelineScale: _state._scale,
        frameGeometry: geometry,
        windowBucket: _still,
        showSeconds: widget.showSeconds,
        projectFrameRate: widget.projectFrameRate,
        defById: widget.transitionDefById,
      ),
    );
  }
}

/// A folded row's label and strip ([_StoryboardFolded]).
typedef _FoldedStrip = ({
  Widget Function() rail,
  Widget Function(BuildContext, TimelineFrameGeometryHandle) frames,
});

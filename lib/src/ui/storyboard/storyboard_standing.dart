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

  /// The RING on the cell you are STANDING on — the timeline's standing
  /// visual (R5 ③b), on this rail's own row geometry.
  ///
  /// The band says what is SELECTED, the ring says where you STAND; the
  /// storyboard had the first and not the second, so the one row that is
  /// actually the subject of every lane verb was the one row that said
  /// nothing about it. Every row kind wears it — S rows, the V row, and
  /// the lane rows of both.
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
  /// the rail's own answer, exactly as the timeline's ring falls back from
  /// an off-screen lane to the active layer's row: showing nothing reads as
  /// broken rather than as elsewhere.
  /// 🚨H12 (유저 2026-08-22) — **THE OUTLINE RIDES THE DRAG.**
  ///
  /// > 「스토리보드패널, **이 패널만** 선택범위로 선택하고 드래그시,
  /// > 선택범위의 **ui 실루엣이 원래 블록 자리에 남음.** 드래그 끝나야
  /// > 사라짐. **타임라인패널이랑 다르니까 통일**」
  ///
  /// The band above this one was never the problem — it is drawn from the
  /// selection's own frame numbers and the cut drag republishes those every
  /// step. THIS is what stayed behind: the standing outline resolved its
  /// rect from the COMMITTED project and subscribed to nothing but the
  /// standing row and the playhead, so while the blocks moved underneath it
  /// the accent rectangle held the seat the run had left.
  ///
  /// ⚠️The timeline's twin already did the right thing —
  /// `TimelineCursorLayer` merges the drag preview into its listenables and
  /// reads its selected-exposure outline off the PREVIEWED layer. Same
  /// sentence, said on this axis.
  Widget trackStandingCellRing(Track track, TimelineScale scale) {
    final currentRow = _state.widget.currentRowHooks?.currentRow;
    final playhead = _state.widget.playheadFrame;
    if (currentRow == null || playhead == null || scale.pixelsPerFrame <= 0) {
      return const SizedBox.shrink();
    }
    final dragPreview = _state.widget.dragPreview;
    if (dragPreview == null) {
      return _standingCellRingFor(track, scale, currentRow, playhead, null);
    }
    return ValueListenableBuilder<TimelineDragPreview?>(
      valueListenable: dragPreview,
      builder: (context, preview, _) =>
          _standingCellRingFor(track, scale, currentRow, playhead, preview),
    );
  }

  Widget _standingCellRingFor(
    Track track,
    TimelineScale scale,
    ValueListenable<TimelineRowAddress?> currentRow,
    ValueListenable<int?> playhead,
    TimelineDragPreview? preview,
  ) {
    return ValueListenableBuilder<TimelineRowAddress?>(
      valueListenable: currentRow,
      builder: (context, standing, _) {
        var row = standing;
        var band = row == null ? null : _trackRowBand(track, row);
        if (band == null) {
          row = _state.widget.selectedRow;
          band = row == null ? null : _trackRowBand(track, row);
        }
        if (row == null || band == null) {
          return const SizedBox.shrink();
        }
        final standingRow = row;
        final rowBand = band;
        return ValueListenableBuilder<int?>(
          valueListenable: playhead,
          builder: (context, frame, _) {
            if (frame == null) {
              return const SizedBox.shrink();
            }
            final block = _standingBlockAt(
              track,
              standingRow,
              frame,
              preview: preview,
            );
            final ring = Semantics(
              key: const ValueKey<String>('storyboard-standing-cell'),
              label: AppText.strings.tlSelectedCell,
              container: true,
              // On a block the OUTLINE is the standing visual; the ring
              // would draw a second one inside it (the timeline's UI-R10
              // #8 rule). The node stays so the row still says where you
              // are to semantics and to the probes that read it.
              child: block == null
                  ? DecoratedBox(decoration: timelineStandingCellDecoration)
                  : const SizedBox.expand(),
            );
            return Stack(
              children: [
                if (block != null)
                  Positioned(
                    left: scale.leftForFrame(block.startIndex),
                    top: rowBand.top,
                    width:
                        (block.endIndexExclusive - block.startIndex) *
                        scale.pixelsPerFrame,
                    height: rowBand.height,
                    child: DecoratedBox(
                      key: const ValueKey<String>('storyboard-standing-block'),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: timelineSelectedFrameBorderColor,
                          width: 2,
                        ),
                        borderRadius: const BorderRadius.all(
                          Radius.circular(6),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: scale.leftForFrame(frame),
                  top: rowBand.top,
                  width: scale.pixelsPerFrame,
                  height: rowBand.height,
                  child: ring,
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// The block under [frame] on the row you are standing on, when that row
  /// HAS blocks: an S row's sounds, read from the very list the row paints
  /// its spans from, so the outline and the block cannot disagree.
  ///
  /// On the V row the blocks are CUTS, and the same sentence holds: the cut
  /// the playhead is inside is the block you are standing on. The cut block
  /// painter used to say this itself, in its own words — a 2px accent
  /// border on the active cut — which is exactly the not-unified-with-the-
  /// timeline shape this round exists to retire. That fork is gone; the
  /// standing outline says it now, in the timeline's words, on every row.
  ({int startIndex, int endIndexExclusive})? _standingBlockAt(
    Track track,
    TimelineRowAddress row,
    int frame, {
    required TimelineDragPreview? preview,
  }) {
    switch (row) {
      case LayerRowAddress(:final layerId):
        // The transition row's blocks are its SPANS: standing on one outlines
        // the whole span, the way standing on a sound outlines its block.
        if (layerId == track.transitionLayer.id) {
          final span = instructionSpanCovering(
            track.transitionLayer.instructions,
            frame,
          );
          return span == null
              ? null
              : (
                  startIndex: span.key,
                  endIndexExclusive: span.key + span.value.length,
                );
        }
        for (var slot = 0; slot < _seSlotCount(track); slot += 1) {
          final layer = _state._seDisplayAt(track, slot);
          if (layer != null && layer.id == layerId) {
            final block = coveringDrawingBlockAt(layer.timeline, frame);
            return block == null
                ? null
                : (
                    startIndex: block.startIndex,
                    endIndexExclusive: block.endIndexExclusive,
                  );
          }
        }
        return null;
      case TrackRowAddress(:final trackId):
        if (trackId != track.id) {
          return null;
        }
        // The same walk [cutAtPlayheadOn] takes, which is what decides
        // which cut is active — so the outline and the active cut are one
        // answer rather than two that agree by luck.
        CutId? standingCut;
        for (final entry in buildStoryboardTimelineLayout(
          _state.widget.project,
        )) {
          if (entry.trackId == track.id &&
              frame >= entry.startFrame &&
              frame < entry.endFrame) {
            standingCut = entry.cut.id;
            break;
          }
        }
        if (standingCut == null) {
          return null;
        }
        // 🚨H12: WHICH cut you stand on is a committed fact — a drag does
        // not change it — but WHERE that cut is is the previewed one. Ask
        // the two questions of the two films.
        //
        // ⛔Asking both of the previewed film reads as "hold still": the
        // playhead does not travel with the run, so a neighbour slides
        // under it and the outline lands on the same pixels wearing a
        // different cut's name. That is the shape this bug already had.
        for (final entry in buildStoryboardTimelineLayout(
          projectWithTimelineDragPreview(_state.widget.project, preview),
        )) {
          if (entry.trackId == track.id && entry.cut.id == standingCut) {
            return (
              startIndex: entry.startFrame,
              endIndexExclusive: entry.endFrame,
            );
          }
        }
        return null;
      case LaneRowAddress():
        // A lane holds keys, not blocks — the plain ring, as in the
        // timeline.
        return null;
    }
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
      if (slot.row == row || slot.laneRow == row) {
        return (top: y, height: slot.height);
      }
      y += slot.height;
    }
    return null;
  }
}

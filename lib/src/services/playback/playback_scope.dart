import '../../models/cut_id.dart';
import '../../models/project.dart';
import '../../models/storyboard_timeline_layout.dart';
import '../../models/track_id.dart';
import '../../models/track_transitions.dart'
    show cutDrawnFrameCount, cutMediaStartFrame;
import 'playback_frame_mapping.dart';

/// What plays: the active cut (timeline context) or every cut of the active
/// track in sequence (storyboard context).
enum PlaybackScope { activeCut, allCuts }

/// What a run of [scope] plays of [project]: the cuts it shows, and the
/// stretch of its track it plays ([PlaybackWindow]) — the cut
/// [activeCutId] alone, or every cut of the track [activeTrackId]. Null =
/// nothing to play alone: the session stands in a gap.
///
/// The canvas's run plays it, and the audio scrubber lays its sound over
/// the same window, so scrubbed sound and played sound can never disagree
/// about what sits where (`CanvasPlaybackController.windowForScope`).
({List<StoryboardTimelineLayoutEntry> playlist, PlaybackWindow window})?
playbackRunOf(
  Project project,
  PlaybackScope scope, {
  required CutId? activeCutId,
  required TrackId activeTrackId,
}) {
  switch (scope) {
    case PlaybackScope.activeCut:
      final alone = _cutAlone(project, activeCutId);
      if (alone == null) {
        return null;
      }
      return (
        playlist: [alone],
        window: PlaybackWindow(
          trackId: alone.trackId,
          // Its frame 0 is where its material starts — ahead of the conte
          // start in a cut an O.L arrives into (F-227 ④) — so the sound
          // plays from there too.
          trackStart: cutMediaStartFrame(project, alone.cutId)!,
          frames: alone.duration,
        ),
      );
    case PlaybackScope.allCuts:
      return (
        playlist: buildStoryboardTimelineLayout(
          project,
        ).where((entry) => entry.trackId == activeTrackId).toList(),
        // The movie, to the end line the storyboard draws: past the last
        // cut its trailing frames play as the gap void (UI-R20 #3) — and
        // with no cut at all, those frames alone (F-341).
        window: PlaybackWindow(
          trackId: activeTrackId,
          trackStart: 0,
          frames: movieEndFrames(project),
        ),
      );
  }
}

/// The cut [activeCutId] as a run of its own: from its frame 0. Null = no
/// cut is active.
StoryboardTimelineLayoutEntry? _cutAlone(Project project, CutId? activeCutId) {
  for (final entry in buildStoryboardTimelineLayout(project)) {
    if (entry.cutId == activeCutId) {
      // 🗣️F-227 (유저 2026-09-29): 「재생도 타임라인패널의 재생이면 여백까지
      // 재생」 — the cut plays every frame it is DRAWN for, through the
      // のりしろ an O.L asks of it, not to the red line.
      final duration = cutDrawnFrameCount(project, entry.cutId)!;
      return StoryboardTimelineLayoutEntry(
        trackId: entry.trackId,
        cutId: entry.cutId,
        trackIndex: entry.trackIndex,
        cutIndex: entry.cutIndex,
        startFrame: 0,
        endFrame: duration,
        duration: duration,
        cut: entry.cut,
      );
    }
  }
  return null;
}

import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/project_frame_rate.dart';
import '../../models/transition_geometry.dart';
import '../../ui/storyboard_timeline_layout.dart';

/// Wall-clock elapsed time → global frame index at [rate]. Elapsed-based
/// mapping is what makes playback drop frames instead of slowing down.
///
/// RT: the rate is the exact fraction, so a 23.976 project maps time to
/// frames without the 0.1% error a rounded 24 would accumulate — after an
/// hour that error is 3.6 seconds of drift.
int elapsedToGlobalFrame(Duration elapsed, ProjectFrameRate rate) {
  return rate.frameAtElapsed(elapsed);
}

/// Where a global playlist frame lands: which cut, and which local frame.
class PlaybackPosition {
  const PlaybackPosition({
    required this.cut,
    required this.localFrameIndex,
    required this.globalFrameIndex,
  });

  /// The cut snapshot from the playlist (frozen at play start).
  final Cut cut;
  final int localFrameIndex;
  final int globalFrameIndex;

  CutId get cutId => cut.id;

  @override
  String toString() =>
      'PlaybackPosition(cut: ${cut.id}, local: $localFrameIndex, '
      'global: $globalFrameIndex)';
}

/// Resolves [globalFrameIndex] against sequential playlist entries
/// (endFrame exclusive); `null` when out of range or on zero-length cuts.
PlaybackPosition? resolvePlaybackPosition({
  required List<StoryboardTimelineLayoutEntry> playlist,
  required int globalFrameIndex,
}) {
  for (final entry in playlist) {
    if (globalFrameIndex >= entry.startFrame &&
        globalFrameIndex < entry.endFrame) {
      return PlaybackPosition(
        cut: entry.cut,
        localFrameIndex: globalFrameIndex - entry.startFrame,
        globalFrameIndex: globalFrameIndex,
      );
    }
  }
  return null;
}

int playlistTotalFrames(List<StoryboardTimelineLayoutEntry> playlist) {
  return playlist.isEmpty ? 0 : playlist.last.endFrame;
}

/// One cut's contribution to a global frame while a transition is running.
class TransitionContribution {
  const TransitionContribution({
    required this.cut,
    required this.localFrameIndex,
    required this.opacity,
  });

  final Cut cut;

  /// The frame INSIDE the cut, counted from its first frame of MATERIAL —
  /// which is the cut's conte start only when it owes no head のりしろ.
  ///
  /// A cut on the incoming side of an O.L supplies pictures before its own
  /// block begins, so its frame 0 sits `head` frames earlier on the global
  /// axis. The block has not moved: the conte range still says which cut
  /// OWNS a frame, and every consumer asking that question keeps reading it.
  final int localFrameIndex;

  /// 1 outside a transition; the ramp while one crosses this cut's boundary.
  final double opacity;

  @override
  String toString() =>
      'TransitionContribution(cut: ${cut.id}, local: $localFrameIndex, '
      'opacity: $opacity)';
}

/// Everything visible at [globalFrameIndex] on ONE track, transitions
/// included — the resolution a compositor wants.
///
/// Ordinary frames answer with a single contribution at full opacity, so a
/// project without transitions behaves exactly as it did. Inside an O.L two
/// come back, OUTGOING FIRST: the cut being replaced, then the one arriving
/// over it. Painting them in that order is the cross-dissolve.
///
/// ★ This widens [resolvePlaybackPosition] in one specific way and no
/// other: it asks which cuts have MATERIAL here (the media range) rather
/// than which cut owns the frame (the conte range). The two differ only
/// where a transition reaches across a boundary — exactly where a second
/// picture is supposed to exist.
List<TransitionContribution> resolveTransitionContributions({
  required List<StoryboardTimelineLayoutEntry> playlist,
  required List<TransitionSpan> spans,
  required int globalFrameIndex,
}) {
  final contributions = <TransitionContribution>[];
  for (final entry in playlist) {
    final handles = cutTransitionHandles(
      cutStart: entry.startFrame,
      cutEnd: entry.endFrame,
      spans: spans,
    );
    final media = cutMediaRange(
      cutStart: entry.startFrame,
      cutEnd: entry.endFrame,
      handles: handles,
    );
    if (globalFrameIndex < media.start || globalFrameIndex >= media.end) {
      continue;
    }
    contributions.add(
      TransitionContribution(
        cut: entry.cut,
        localFrameIndex: globalFrameIndex - media.start,
        opacity: cutOpacityAt(
          cutStart: entry.startFrame,
          cutEnd: entry.endFrame,
          spans: spans,
          globalFrame: globalFrameIndex,
        ),
      ),
    );
  }
  return contributions;
}

/// The multitrack display resolution: [globalFrameIndex] answered by EVERY
/// track of a multi-track [layout] — at most one position per track, the
/// entry that STRICTLY contains the frame. Gap frames and frames past a
/// track's last cut contribute nothing (never the owner-rule runway the
/// editing axis uses), so a track without picture at this frame is simply
/// absent from the result.
///
/// Track axes each start at global frame 0 (buildStoryboardTimelineLayout
/// resets per track), so one shared index addresses all tracks in parallel;
/// entries within one track never overlap, and cross-track startFrame
/// overlap is fine because containment is tested per entry. The result
/// keeps layout order (= project track order): painting it in order stacks
/// later tracks on top.
List<PlaybackPosition> resolveTrackStackPositions({
  required List<StoryboardTimelineLayoutEntry> layout,
  required int globalFrameIndex,
}) {
  return [
    for (final entry in layout)
      if (globalFrameIndex >= entry.startFrame &&
          globalFrameIndex < entry.endFrame)
        PlaybackPosition(
          cut: entry.cut,
          localFrameIndex: globalFrameIndex - entry.startFrame,
          globalFrameIndex: globalFrameIndex,
        ),
  ];
}

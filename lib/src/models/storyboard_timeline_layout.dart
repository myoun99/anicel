import 'cut.dart';
import 'cut_id.dart';
import 'project.dart';
import 'track.dart';
import 'track_id.dart';

class StoryboardTimelineLayoutEntry {
  const StoryboardTimelineLayoutEntry({
    required this.trackId,
    required this.cutId,
    required this.trackIndex,
    required this.cutIndex,
    required this.startFrame,
    required this.endFrame,
    required this.duration,
    required this.cut,
  });

  final TrackId trackId;
  final CutId cutId;
  final int trackIndex;
  final int cutIndex;
  final int startFrame;
  final int endFrame;
  final int duration;
  final Cut cut;
}

List<StoryboardTimelineLayoutEntry> buildStoryboardTimelineLayout(
  Project project,
) {
  final entries = <StoryboardTimelineLayoutEntry>[];

  for (var trackIndex = 0; trackIndex < project.tracks.length; trackIndex++) {
    final track = project.tracks[trackIndex];
    var cutIndex = 0;
    for (final span in cutSpansOf(track)) {
      entries.add(
        StoryboardTimelineLayoutEntry(
          trackId: track.id,
          cutId: span.cut.id,
          trackIndex: trackIndex,
          cutIndex: cutIndex,
          startFrame: span.startFrame,
          endFrame: span.endFrame,
          duration: span.cut.duration,
          cut: span.cut,
        ),
      );
      cutIndex += 1;
    }
  }

  return entries;
}

/// ONE cumulative pass over [track]'s cuts: each cut's global start and end
/// on the track's axis. A cut's leading gap = empty (black) frames before
/// it; list order stays the sequence authority, the layout stays one
/// cumulative pass.
///
/// THE walk. The storyboard layout, the SE tags and the SE window all read
/// a cut's start from here. Until 2026-09-03 the session manager kept a
/// second copy of this loop — one that said it was "kept in a single place
/// so the SE tags and the SE window can never disagree with the
/// storyboard", which a second loop cannot promise. Now it is one loop.
Iterable<({Cut cut, int startFrame, int endFrame})> cutSpansOf(Track track) =>
    cutSpansOfCuts(track.cuts);

/// [cutSpansOf] over a bare cut list, in list order.
///
/// An export selection is a subset of a track's cuts and an audio plan
/// walks every track's, so both need the axis without holding a [Track].
/// ⛔THE SAME walk, not a second one: four call sites had re-typed this
/// loop and each was one `leadingGapFrames` away from putting a sound or
/// a wipe on a different frame than the one that plays (2026-09-05).
Iterable<({Cut cut, int startFrame, int endFrame})> cutSpansOfCuts(
  Iterable<Cut> cuts,
) sync* {
  var nextStartFrame = 0;
  for (final cut in cuts) {
    final startFrame = nextStartFrame + cut.leadingGapFrames;
    final endFrame = startFrame + cut.duration;
    yield (cut: cut, startFrame: startFrame, endFrame: endFrame);
    nextStartFrame = endFrame;
  }
}

/// [cutId]'s global start on [track]'s axis, or null when [cutId] is null or
/// the track does not hold it.
int? cutGlobalStartFrameIn(Track track, CutId? cutId) {
  if (cutId == null) {
    return null;
  }
  for (final span in cutSpansOf(track)) {
    if (span.cut.id == cutId) {
      return span.startFrame;
    }
  }
  return null;
}

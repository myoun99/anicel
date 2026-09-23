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

/// Where the MOVIE ends (UI-R20 #3): the furthest cut end on any track in
/// [layout], plus the project's trailing gap — the frame the storyboard's
/// end line stands at.
int movieEndFramesOver(
  List<StoryboardTimelineLayoutEntry> layout, {
  required int trailingFrames,
}) {
  var end = 0;
  for (final entry in layout) {
    if (entry.endFrame > end) {
      end = entry.endFrame;
    }
  }
  return end + trailingFrames;
}

/// [movieEndFramesOver] for [project] as it stands.
int movieEndFrames(Project project) => movieEndFramesOver(
  buildStoryboardTimelineLayout(project),
  trailingFrames: project.trailingFrames,
);

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

/// Every cut's place on its track's axis, and which track owns it.
///
/// Track-owned SE rows live on this axis, so a sound's window is stated
/// in these coordinates — by playback and by export alike.
typedef TrackAxis = ({
  Map<CutId, int> startByCutId,
  Map<CutId, Track> trackByCutId,
});

/// [cutSpansOf] over every track of [project], as a lookup. A null
/// project has no tracks and answers an empty axis.
TrackAxis trackAxisOf(Project? project) {
  final startByCutId = <CutId, int>{};
  final trackByCutId = <CutId, Track>{};
  for (final track in project?.tracks ?? const <Track>[]) {
    for (final placed in cutSpansOf(track)) {
      startByCutId[placed.cut.id] = placed.startFrame;
      trackByCutId[placed.cut.id] = track;
    }
  }
  return (startByCutId: startByCutId, trackByCutId: trackByCutId);
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

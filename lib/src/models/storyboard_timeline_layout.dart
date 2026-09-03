import 'cut.dart';
import 'cut_id.dart';
import 'project.dart';
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
    var nextStartFrame = 0;

    for (var cutIndex = 0; cutIndex < track.cuts.length; cutIndex++) {
      final cut = track.cuts[cutIndex];
      // A cut's leading gap = empty (black) frames before it; list order
      // stays the sequence authority, the layout stays one cumulative
      // pass.
      final startFrame = nextStartFrame + cut.leadingGapFrames;
      final endFrame = startFrame + cut.duration;

      entries.add(
        StoryboardTimelineLayoutEntry(
          trackId: track.id,
          cutId: cut.id,
          trackIndex: trackIndex,
          cutIndex: cutIndex,
          startFrame: startFrame,
          endFrame: endFrame,
          duration: cut.duration,
          cut: cut,
        ),
      );

      nextStartFrame = endFrame;
    }
  }

  return entries;
}

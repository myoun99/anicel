import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/playback/playback_frame_mapping.dart';
import 'package:anicel/src/ui/storyboard_timeline_layout.dart';

void main() {
  Cut cut(String id, int duration) => Cut(
    id: CutId(id),
    name: id,
    layers: const [],
    duration: duration,
    canvasSize: const CanvasSize(width: 8, height: 8),
  );

  List<StoryboardTimelineLayoutEntry> playlist() {
    return buildStoryboardTimelineLayout(
      Project(
        id: const ProjectId('project'),
        name: 'Project',
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'Track',
            cuts: [cut('cut-a', 4), cut('cut-b', 6)],
          ),
        ],
        createdAt: DateTime.utc(2026),
      ),
    );
  }

  test('elapsedToGlobalFrame maps wall clock to frames at fps', () {
    const fps24 = ProjectFrameRate.integer(24);
    const fps12 = ProjectFrameRate.integer(12);
    expect(elapsedToGlobalFrame(Duration.zero, fps24), 0);
    expect(elapsedToGlobalFrame(const Duration(milliseconds: 41), fps24), 0);
    expect(elapsedToGlobalFrame(const Duration(milliseconds: 42), fps24), 1);
    expect(elapsedToGlobalFrame(const Duration(seconds: 1), fps24), 24);
    expect(elapsedToGlobalFrame(const Duration(seconds: 2), fps12), 24);
  });

  test('23.976 runs slower than 24 by exactly the NTSC 1000/1001', () {
    const ntsc = ProjectFrameRate.ntsc(24);
    // One second of wall clock shows frame 23, not 24 — the pulldown rate
    // genuinely is slower, and the clock must not round that away.
    expect(elapsedToGlobalFrame(const Duration(seconds: 1), ntsc), 23);
    // 1001/1000 seconds is exactly 24 frames.
    expect(elapsedToGlobalFrame(const Duration(milliseconds: 1001), ntsc), 24);
  });

  test('the clock does not drift over an hour of playback', () {
    // The failure this whole program exists to prevent: a rate held as a
    // double accumulates error, and after an hour the picture and the
    // sound are seconds apart. Frame N must land on frame N no matter how
    // far from zero it is, so we check the clock against the exact frame
    // boundary at the one-hour mark rather than integrating small steps.
    for (final rate in const [
      ProjectFrameRate.integer(24),
      ProjectFrameRate.ntsc(24),
      ProjectFrameRate.ntsc(30),
    ]) {
      final anHourOfFrames = rate.countingBase * 60 * 60;
      final boundary = rate.frameStart(anHourOfFrames);
      expect(
        elapsedToGlobalFrame(boundary, rate),
        anHourOfFrames,
        reason: '$rate lands exactly on its own frame boundary',
      );
      expect(
        elapsedToGlobalFrame(
          boundary - const Duration(microseconds: 1),
          rate,
        ),
        anHourOfFrames - 1,
        reason: '$rate is still on the previous frame a microsecond before',
      );
    }
  });

  test('resolvePlaybackPosition finds the cut and local frame', () {
    final entries = playlist();

    final inFirst = resolvePlaybackPosition(
      playlist: entries,
      globalFrameIndex: 3,
    )!;
    expect(inFirst.cutId, const CutId('cut-a'));
    expect(inFirst.localFrameIndex, 3);

    final inSecond = resolvePlaybackPosition(
      playlist: entries,
      globalFrameIndex: 4,
    )!;
    expect(inSecond.cutId, const CutId('cut-b'));
    expect(inSecond.localFrameIndex, 0);

    expect(
      resolvePlaybackPosition(playlist: entries, globalFrameIndex: 10),
      isNull,
    );
    expect(
      resolvePlaybackPosition(playlist: entries, globalFrameIndex: -1),
      isNull,
    );
  });

  test('playlistTotalFrames sums sequential cut durations', () {
    expect(playlistTotalFrames(playlist()), 10);
    expect(playlistTotalFrames(const []), 0);
  });

  test('gap frames resolve to null (black) but still count toward the '
      'total', () {
    final entries = buildStoryboardTimelineLayout(
      Project(
        id: const ProjectId('gap-project'),
        name: 'Gaps',
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'Track',
            cuts: [
              cut('cut-a', 4),
              Cut(
                id: const CutId('cut-b'),
                name: 'cut-b',
                layers: const [],
                duration: 6,
                leadingGapFrames: 3,
                canvasSize: const CanvasSize(width: 8, height: 8),
              ),
            ],
          ),
        ],
        createdAt: DateTime.utc(2026),
      ),
    );

    // Frames 4..6 sit in the gap: no cut plays there.
    expect(
      resolvePlaybackPosition(playlist: entries, globalFrameIndex: 3),
      isNotNull,
    );
    for (var frame = 4; frame < 7; frame += 1) {
      expect(
        resolvePlaybackPosition(playlist: entries, globalFrameIndex: frame),
        isNull,
        reason: 'frame $frame is in the gap',
      );
    }
    final afterGap = resolvePlaybackPosition(
      playlist: entries,
      globalFrameIndex: 7,
    )!;
    expect(afterGap.cutId, const CutId('cut-b'));
    expect(afterGap.localFrameIndex, 0);

    // The playback clock runs THROUGH the gap: total = last end.
    expect(playlistTotalFrames(entries), 13);
  });
}

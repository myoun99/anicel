import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/storyboard_timeline_layout.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/playback/audio_playback_schedule.dart';

/// 🚨SE ROWS LIVE ON THE TRACK'S GLOBAL AXIS; A CUT SHOWS A WINDOW ONTO
/// THEM.
///
/// So the schedule's real work is mapping each playlist entry back onto
/// that axis — and two parts of that had nothing pinning them (the
/// audit's cognitive split, 2026-09-05):
///
/// * a PLAYED leading gap is covered by the window, so a sound starting
///   inside the gap is scheduled rather than dropped;
/// * a run START also carries sounds spilling in from before the window,
///   while interior entries emit only spans starting in theirs — which is
///   what keeps one sound from being scheduled twice.
void main() {
  const rate = ProjectFrameRate.fps24;
  const canvas = CanvasSize(width: 64, height: 64);

  /// A sound on an SE row sits where its BLOCK sits: the row's timeline
  /// places a drawing block on the track's global axis, and the clip
  /// rides it.
  Layer seRow({required int start, required int length}) => Layer(
    id: const LayerId('se'),
    name: 'SE',
    frames: const [],
    timeline: {
      start: TimelineExposure.drawing(const FrameId('f'), length: length),
    },
    kind: LayerKind.se,
    audioClips: const [AudioClip(filePath: '/take.wav', frameId: FrameId('f'))],
  );

  Cut cut(String id, {int duration = 10, int leadingGap = 0}) => Cut(
    id: CutId(id),
    name: id,
    layers: const [],
    duration: duration,
    leadingGapFrames: leadingGap,
    canvasSize: canvas,
  );

  Project projectWith({
    required List<Cut> cuts,
    required ({int start, int length}) sound,
  }) => Project(
    id: const ProjectId('p'),
    name: 'P',
    frameRate: rate,
    cameraSize: canvas,
    createdAt: DateTime.utc(2026, 9, 5),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'V',
        seLayers: [seRow(start: sound.start, length: sound.length)],
        cuts: cuts,
      ),
    ],
  );

  StoryboardTimelineLayoutEntry entry(Cut source, {required int startFrame}) =>
      StoryboardTimelineLayoutEntry(
        trackId: const TrackId('t'),
        cutId: source.id,
        trackIndex: 0,
        cutIndex: 0,
        startFrame: startFrame,
        endFrame: startFrame + source.duration,
        duration: source.duration,
        cut: source,
      );

  List<ScheduledAudioClip> schedule({
    required Project project,
    required List<StoryboardTimelineLayoutEntry> playlist,
  }) => buildAudioPlaybackSchedule(
    playlist: playlist,
    project: project,
    rate: rate,
    durationSecondsFor: (_) => 100,
  );

  test('a sound inside a cut is scheduled at the entry that shows it', () {
    final only = cut('c1');
    final scheduled = schedule(
      project: projectWith(cuts: [only], sound: (start: 2, length: 3)),
      playlist: [entry(only, startFrame: 0)],
    );

    expect(scheduled, hasLength(1));
    expect(scheduled.single.startFrame, 2);
  });

  test('🚨a sound starting inside a PLAYED leading gap is scheduled — the '
      'window reaches back over the gap the playlist plays as black', () {
    final second = cut('c2', leadingGap: 4);
    final first = cut('c1');
    final scheduled = schedule(
      project: projectWith(
        cuts: [first, second],
        // Track frames 10..13 are the gap before c2.
        sound: (start: 11, length: 2),
      ),
      playlist: [entry(first, startFrame: 0), entry(second, startFrame: 14)],
    );

    expect(
      scheduled,
      hasLength(1),
      reason: 'a sound in a played gap is not a sound nobody hears',
    );
    expect(scheduled.single.startFrame, 11);
  });

  test('🚨a sound spanning a cut boundary is scheduled ONCE — the interior '
      'entry emits only spans STARTING in its window', () {
    final first = cut('c1');
    final second = cut('c2');
    final scheduled = schedule(
      project: projectWith(cuts: [first, second], sound: (start: 8, length: 8)),
      playlist: [entry(first, startFrame: 0), entry(second, startFrame: 10)],
    );

    expect(scheduled, hasLength(1));
    expect(scheduled.single.startFrame, 8);
  });

  test('🚨a playlist that STARTS mid-sound still plays it — the run start '
      'takes the spill and bumps the file offset by the clipped lead', () {
    final second = cut('c2');
    final scheduled = schedule(
      project: projectWith(
        cuts: [cut('c1'), second],
        sound: (start: 6, length: 10),
      ),
      // The playlist is c2 alone, rebased to 0: the sound began before it.
      playlist: [entry(second, startFrame: 0)],
    );

    expect(scheduled, hasLength(1));
    expect(
      scheduled.single.startFrame,
      0,
      reason: 'it is already playing when the window opens',
    );
    expect(
      scheduled.single.offsetFrames,
      greaterThan(0),
      reason: 'and it starts part-way into the file',
    );
  });

  test('🚨a playlist that JUMPS starts a new run mid-list — c1 then c3, and '
      'the sound running across the skipped c2 is still heard', () {
    final third = cut('c3');
    final scheduled = schedule(
      project: projectWith(
        cuts: [cut('c1'), cut('c2'), third],
        // Track 18..23: it begins inside the SKIPPED c2 and runs into c3.
        sound: (start: 18, length: 6),
      ),
      // Two frames of playlist that are not two frames of track: the
      // entries are adjacent in the list and far apart on the axis.
      playlist: [entry(cut('c1'), startFrame: 0), entry(third, startFrame: 12)],
    );

    expect(
      scheduled,
      hasLength(1),
      reason: 'the jump makes c3 a run start, and a run start takes the spill',
    );
    expect(
      scheduled.single.startFrame,
      12,
      reason:
          'at the entry, NOT two frames early — the playlist gap here is '
          'not a played leading gap, so the window does not reach back',
    );
    expect(
      scheduled.single.offsetFrames,
      2,
      reason: 'and the part heard before the jump is skipped in the file',
    );
  });

  test('⛔a MUTED row is silent', () {
    final only = cut('c1');
    final project = projectWith(cuts: [only], sound: (start: 2, length: 3));
    final scheduled = buildAudioPlaybackSchedule(
      playlist: [entry(only, startFrame: 0)],
      project: project,
      rate: rate,
      durationSecondsFor: (_) => 100,
      mutedLayerIds: {const LayerId('se')},
    );

    expect(scheduled, isEmpty);
  });

  test('⛔SOLO narrows to itself — a row that is not soloed is silent', () {
    final only = cut('c1');
    final project = projectWith(cuts: [only], sound: (start: 2, length: 3));
    final scheduled = buildAudioPlaybackSchedule(
      playlist: [entry(only, startFrame: 0)],
      project: project,
      rate: rate,
      durationSecondsFor: (_) => 100,
      soloedLayerIds: {const LayerId('somebody-else')},
    );

    expect(scheduled, isEmpty);
  });
}

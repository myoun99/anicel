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
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/se_sound.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/playback/playback_frame_mapping.dart';
import 'package:anicel/src/ui/playback/audio_playback_schedule.dart';

/// 🚨SE ROWS LIVE ON THE TRACK'S GLOBAL AXIS; A RUN SHOWS A WINDOW ONTO
/// THEM ([PlaybackWindow]) — and the sound is read off the track through
/// it, never through the run's cuts (F-341, 유저 10-12: 「분명 독립적인
/// 글로벌 행이라고 했는데 아직도 연관시켜버린 코드가 존재하나본데」).
///
/// So a sound is heard wherever the window is: inside a cut, in a gap, in
/// the movie's trailing frames, on a track with no cut at all. ↩️It was
/// laid cut by cut: a track with no cut was silent, a sound in the
/// trailing frames was never scheduled, and one running into them stopped
/// at the last cut's end.
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
    audioClips: [AudioClip(filePath: '/take.wav', frameId: const FrameId('f'))],
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

  PlaybackWindow window({required int trackStart, required int frames}) =>
      PlaybackWindow(
        trackId: const TrackId('t'),
        trackStart: trackStart,
        frames: frames,
      );

  List<ScheduledAudioClip> schedule({
    required Project project,
    required PlaybackWindow window,
  }) => buildAudioPlaybackSchedule(
    window: window,
    project: project,
    rate: rate,
    durationSecondsFor: (_) => 100,
  );

  test('a sound inside a cut is scheduled where the window shows it', () {
    final scheduled = schedule(
      project: projectWith(cuts: [cut('c1')], sound: (start: 2, length: 3)),
      window: window(trackStart: 0, frames: 10),
    );

    expect(scheduled, hasLength(1));
    expect(scheduled.single.startFrame, 2);
    expect(scheduled.single.endFrameExclusive, 5);
  });

  test('a sound starting inside a gap between cuts is scheduled', () {
    final scheduled = schedule(
      project: projectWith(
        cuts: [cut('c1'), cut('c2', leadingGap: 4)],
        // Track frames 10..13 are the gap before c2.
        sound: (start: 11, length: 2),
      ),
      window: window(trackStart: 0, frames: 24),
    );

    expect(
      scheduled,
      hasLength(1),
      reason: 'a sound in a played gap is not a sound nobody hears',
    );
    expect(scheduled.single.startFrame, 11);
  });

  test('a sound spanning a cut boundary is scheduled ONCE, whole', () {
    final scheduled = schedule(
      project: projectWith(
        cuts: [cut('c1'), cut('c2')],
        sound: (start: 8, length: 8),
      ),
      window: window(trackStart: 0, frames: 20),
    );

    expect(scheduled, hasLength(1));
    expect(scheduled.single.startFrame, 8);
    expect(scheduled.single.endFrameExclusive, 16);
  });

  test('🚨a window that opens mid-sound still plays it — from where it has '
      'got to, the file offset bumped by the clipped lead', () {
    final scheduled = schedule(
      project: projectWith(
        cuts: [cut('c1'), cut('c2')],
        sound: (start: 6, length: 10),
      ),
      // c2 played alone: its frame 0 is track frame 10.
      window: window(trackStart: 10, frames: 10),
    );

    expect(scheduled, hasLength(1));
    expect(
      scheduled.single.startFrame,
      0,
      reason: 'it is already playing when the window opens',
    );
    expect(
      scheduled.single.offsetFrames,
      4,
      reason: 'and it starts four frames into the file',
    );
    expect(scheduled.single.endFrameExclusive, 6);
  });

  test('🚨F-341: a track with NO cut is heard all the same — the window is '
      'the track\'s, not its cuts\'', () {
    final scheduled = schedule(
      project: projectWith(cuts: const [], sound: (start: 10, length: 4)),
      window: window(trackStart: 0, frames: 48),
    );

    expect(scheduled, hasLength(1));
    expect(scheduled.single.startFrame, 10);
    expect(scheduled.single.endFrameExclusive, 14);
  });

  test('🚨F-341: a sound in the movie\'s trailing frames is heard, and one '
      'running into them is not cut off at the last cut', () {
    final starting = schedule(
      project: projectWith(cuts: [cut('c1')], sound: (start: 14, length: 3)),
      // The cut's 10 frames and 10 trailing ones.
      window: window(trackStart: 0, frames: 20),
    );
    expect(starting.single.startFrame, 14);

    final running = schedule(
      project: projectWith(cuts: [cut('c1')], sound: (start: 8, length: 8)),
      window: window(trackStart: 0, frames: 20),
    );
    expect(
      running.single.endFrameExclusive,
      16,
      reason: 'it runs to its own end, past the last cut\'s 10',
    );
  });

  test('the window\'s end is the sound\'s end — and nothing past it plays', () {
    final project = projectWith(
      cuts: [cut('c1')],
      sound: (start: 15, length: 10),
    );
    expect(
      schedule(
        project: project,
        window: window(trackStart: 0, frames: 20),
      ).single.endFrameExclusive,
      20,
    );
    expect(
      schedule(project: project, window: window(trackStart: 0, frames: 15)),
      isEmpty,
      reason: 'a sound starting where the window ends is not in it',
    );
  });

  // Asking a file's length starts its conform on the first ask
  // (`AudioConformStore.durationSecondsFor`): a scrub over one cut must not
  // set every sound on the track decoding.
  test('a sound outside the window is never looked up — on either side', () {
    final project = projectWith(
      cuts: [cut('c1')],
      sound: (start: 15, length: 10),
    );
    final asked = <String>[];
    for (final outside in [
      window(trackStart: 0, frames: 15),
      window(trackStart: 25, frames: 5),
    ]) {
      buildAudioPlaybackSchedule(
        window: outside,
        project: project,
        rate: rate,
        durationSecondsFor: (path) {
          asked.add(path);
          return 100;
        },
      );
    }

    expect(asked, isEmpty);
  });

  test('⛔a MUTED row is silent', () {
    final project = projectWith(
      cuts: [cut('c1')],
      sound: (start: 2, length: 3),
    );
    final scheduled = buildAudioPlaybackSchedule(
      window: window(trackStart: 0, frames: 10),
      project: project,
      rate: rate,
      durationSecondsFor: (_) => 100,
      mutedLayerIds: {const LayerId('se')},
    );

    expect(scheduled, isEmpty);
  });

  test('⛔SOLO narrows to itself — a row that is not soloed is silent', () {
    final project = projectWith(
      cuts: [cut('c1')],
      sound: (start: 2, length: 3),
    );
    final scheduled = buildAudioPlaybackSchedule(
      window: window(trackStart: 0, frames: 10),
      project: project,
      rate: rate,
      durationSecondsFor: (_) => 100,
      soloedLayerIds: {const LayerId('somebody-else')},
    );

    expect(scheduled, isEmpty);
  });

  group('the row\'s sound rides every entry (I-140)', () {
    Project soundedWith(
      SeSound sound, {
      required ({int start, int length}) at,
    }) => Project(
      id: const ProjectId('p'),
      name: 'P',
      frameRate: rate,
      cameraSize: canvas,
      createdAt: DateTime.utc(2026, 10, 28),
      tracks: [
        Track(
          id: const TrackId('t'),
          name: 'V',
          seLayers: [
            seRow(
              start: at.start,
              length: at.length,
            ).copyWith(seSound: sound),
          ],
          cuts: [cut('c1'), cut('c2')],
        ),
      ],
    );

    /// The volume an entry's line passes at [frame] — straight between its
    /// points and held past its ends, as the mixer draws it.
    double lineAt(List<ScheduledVolumePoint> line, int frame) {
      if (frame <= line.first.frame) {
        return line.first.gain;
      }
      for (var index = 1; index < line.length; index += 1) {
        final (before, after) = (line[index - 1], line[index]);
        if (frame <= after.frame) {
          final share = (frame - before.frame) / (after.frame - before.frame);
          return before.gain + (after.gain - before.gain) * share;
        }
      }
      return line.last.gain;
    }

    test('🎯a window opening mid-sound reads the volume on the TRACK\'s '
        'frames — where the ramp has climbed to, not where it began', () {
      final sound = SeSound(
        pan: -0.5,
        volume: PropertyTrack<double>(
          keys: {0: const PropertyKey(0.0), 20: const PropertyKey(1.0)},
        ),
      );
      final entry = schedule(
        project: soundedWith(sound, at: (start: 6, length: 10)),
        window: window(trackStart: 10, frames: 10),
      ).single;

      expect([entry.startFrame, entry.endFrameExclusive], [0, 6]);
      expect([for (final point in entry.volume) point.frame], [0, 6]);
      expect(entry.volume.first.gain, closeTo(0.5, 1e-9));
      expect(entry.volume.last.gain, closeTo(0.8, 1e-9));
      expect(entry.pan, -0.5);
    });

    test('an eased key is met at EVERY frame the entry sounds — the mixer\'s '
        'line is straight, so the curve is laid frame by frame', () {
      final sound = SeSound(
        volume: PropertyTrack<double>(
          keys: {
            0: const PropertyKey(0.2, outgoing: EaseSide()),
            6: const PropertyKey(1.6, incoming: EaseSide()),
          },
        ),
      );
      final entry = schedule(
        project: soundedWith(sound, at: (start: 2, length: 8)),
        window: window(trackStart: 0, frames: 20),
      ).single;

      for (var frame = 0; frame <= 8; frame += 1) {
        expect(
          lineAt(entry.volume, frame),
          closeTo(sound.volumeAt(2.0 + frame), 1e-9),
          reason: 'entry frame $frame is track frame ${2 + frame}',
        );
      }
    });

    test('an unkeyed row lays no line — the entry plays as recorded', () {
      final entry = schedule(
        project: soundedWith(
          const SeSound(pan: 0.25),
          at: (start: 2, length: 3),
        ),
        window: window(trackStart: 0, frames: 10),
      ).single;

      expect(entry.volume, isEmpty);
      expect(entry.pan, 0.25);
    });
  });
}

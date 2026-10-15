import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/native/qa_audio_device.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/conform_pcm_codec.dart';
import 'package:anicel/src/services/audio/conform_pcm_stream.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/playback/audio_scrubber.dart';
import 'package:anicel/src/ui/playback/audio_windowed_upload.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';

import '../../helpers/native_engine_path.dart';
import '../../helpers/temp_dir.dart';

/// The audio scrub, driven for real on the null backend: each crossed
/// frame plays exactly its slice of the mix; release silences; playback
/// owning the device refuses the gesture; a silent cut never arms; a scrub
/// that crosses into another cut hears that cut; a sound that streams is
/// heard wherever a drag goes.
Project _project({
  bool withSound = true,
  int frames = 10,
  String sound = 'tone.wav',
}) => Project(
  id: const ProjectId('scrub-project'),
  name: 'Scrub',
  createdAt: DateTime.utc(2026, 7, 21),
  tracks: [
    Track(
      id: const TrackId('track'),
      name: 'Video',
      cuts: [
        Cut(
          id: const CutId('cut-a'),
          name: 'A',
          duration: frames,
          canvasSize: const CanvasSize(width: 640, height: 360),
          layers: const [],
        ),
      ],
      seLayers: [
        if (withSound)
          Layer(
            id: const LayerId('se'),
            name: 'S1',
            kind: LayerKind.se,
            frames: [
              Frame(
                id: const FrameId('se-frame'),
                duration: 1,
                strokes: const [],
              ),
            ],
            timeline: {
              0: TimelineExposure.drawing(
                const FrameId('se-frame'),
                length: frames,
              ),
            },
            audioClips: [
              AudioClip(
                filePath: sound,
                frameId: const FrameId('se-frame'),
              ),
            ],
          ),
      ],
    ),
  ],
);

/// Two cuts on the track, A on its frames 0–9 and B on 10–19, with the
/// track's sound under [soundUnder] alone.
Project _twoCuts({required String soundUnder}) => Project(
  id: const ProjectId('scrub-project'),
  name: 'Scrub',
  createdAt: DateTime.utc(2026, 10, 10),
  tracks: [
    Track(
      id: const TrackId('track'),
      name: 'Video',
      cuts: [
        for (final id in ['cut-a', 'cut-b'])
          Cut(
            id: CutId(id),
            name: id,
            duration: 10,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: const [],
          ),
      ],
      seLayers: [
        Layer(
          id: const LayerId('se'),
          name: 'S1',
          kind: LayerKind.se,
          frames: [
            Frame(id: const FrameId('se-frame'), duration: 1, strokes: const []),
          ],
          timeline: {
            (soundUnder == 'cut-a' ? 0 : 10): const TimelineExposure.drawing(
              FrameId('se-frame'),
              length: 10,
            ),
          },
          audioClips: [
            AudioClip(filePath: 'tone.wav', frameId: const FrameId('se-frame')),
          ],
        ),
      ],
    ),
  ],
);

/// A track whose sound sits where no cut is (F-341): [cut] or none on frames
/// 0–9, a 20-frame movie, the sound on [soundAt]..+3.
Project _soundWhereNoCutIs({required bool cut, required int soundAt}) =>
    Project(
      id: const ProjectId('scrub-project'),
      name: 'Scrub',
      createdAt: DateTime.utc(2026, 10, 12),
      trailingFrames: cut ? 10 : 20,
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'Video',
          cuts: [
            if (cut)
              Cut(
                id: const CutId('cut-a'),
                name: 'A',
                duration: 10,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: const [],
              ),
          ],
          seLayers: [
            Layer(
              id: const LayerId('se'),
              name: 'S1',
              kind: LayerKind.se,
              frames: [
                Frame(
                  id: const FrameId('se-frame'),
                  duration: 1,
                  strokes: const [],
                ),
              ],
              timeline: {
                soundAt: const TimelineExposure.drawing(
                  FrameId('se-frame'),
                  length: 4,
                ),
              },
              audioClips: [
                AudioClip(
                  filePath: 'tone.wav',
                  frameId: const FrameId('se-frame'),
                ),
              ],
            ),
          ],
        ),
      ],
    );

AudioConformStore _residentStore() => AudioConformStore(
  resolveConformPath: (_) => null,
  runner: (request) async => ConformResult(
    outcome: ConformOutcome.built,
    samples: Float32List(48000)..fillRange(0, 48000, 0.05),
    channels: 1,
    sampleRate: 48000,
    frames: 48000,
  ),
  log: (_) {},
);

Future<bool> _waitFor(bool Function() check, {int millis = 3000}) async {
  final deadline = DateTime.now().add(Duration(milliseconds: millis));
  while (DateTime.now().isBefore(deadline)) {
    if (check()) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return check();
}

void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();
  final available = libraryPath != null;
  final skip = available ? false : nativeEngineMissingSkipReason;

  setUp(() {
    QaAudioDevice.debugResetForTests();
    debugQaEngineLibraryPathOverride = libraryPath;
  });

  tearDown(() {
    try {
      QaAudioDevice.instance?.close();
    } on Object {
      // A device that never opened is fine to "close".
    }
    QaAudioDevice.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
  });

  CanvasPlaybackController buildController(Project project) =>
      CanvasPlaybackController(
        resolveProject: () => project,
        resolveActiveCutId: () => const CutId('cut-a'),
        resolveActiveTrackId: () => const TrackId('track'),
        resolveFrameRate: () => const ProjectFrameRate.integer(10),
      );

  QaAudioDevice openNullDevice() {
    final device = QaAudioDevice.instance!;
    expect(
      device.open(sampleRate: 48000, channels: 2, useNullBackend: true),
      greaterThan(0),
    );
    return device;
  }

  test('each crossed frame plays exactly its slice, and release silences',
      () async {
    final device = openNullDevice();
    final project = _project();
    final controller = buildController(project);
    final store = _residentStore();
    store.resultFor('tone.wav');
    await pumpEventQueue();

    final scrubber = AudioScrubber(
      controller: controller,
      resolveFrameRate: () => const ProjectFrameRate.integer(10),
      resolveProject: () => project,
      conformStore: store,
      resolveDevice: () => QaAudioDevice.instance,
    );

    // Frame 3 at 10fps/48k = samples [14400, 19200).
    scrubber.onScrubFrame(3);
    expect(scrubber.isArmed, isTrue);
    expect(await _waitFor(() => device.positionSamples >= 14400), isTrue);
    // The slice runs out on its own at the frame boundary.
    expect(await _waitFor(() => !device.isPlaying), isTrue);
    expect(device.positionSamples, lessThanOrEqualTo(19200));

    // The next crossed frame re-arms the same uploaded schedule.
    scrubber.onScrubFrame(7);
    expect(await _waitFor(() => device.positionSamples >= 33600), isTrue);

    scrubber.onScrubEnd();
    expect(await _waitFor(() => !device.isPlaying), isTrue);
    expect(scrubber.isArmed, isFalse);
    scrubber.dispose();
    controller.dispose();
    store.dispose();
  }, skip: skip);

  test('active playback owns the device: the scrub stays visual', () async {
    openNullDevice();
    final project = _project();
    final controller = buildController(project);
    final store = _residentStore();
    store.resultFor('tone.wav');
    await pumpEventQueue();
    final scrubber = AudioScrubber(
      controller: controller,
      resolveFrameRate: () => const ProjectFrameRate.integer(10),
      resolveProject: () => project,
      conformStore: store,
      resolveDevice: () => QaAudioDevice.instance,
    );

    controller.play(scope: PlaybackScope.activeCut);
    scrubber.onScrubFrame(3);
    expect(scrubber.isArmed, isFalse);
    controller.stop();
    scrubber.dispose();
    controller.dispose();
    store.dispose();
  }, skip: skip);

  test('a cut with no sound never arms (no device churn for silence)',
      () async {
    final project = _project(withSound: false);
    final controller = buildController(project);
    final store = _residentStore();
    var deviceAsked = false;
    final scrubber = AudioScrubber(
      controller: controller,
      resolveFrameRate: () => const ProjectFrameRate.integer(10),
      resolveProject: () => project,
      conformStore: store,
      resolveDevice: () {
        deviceAsked = true;
        return QaAudioDevice.instance;
      },
    );

    scrubber.onScrubFrame(3);
    expect(scrubber.isArmed, isFalse);
    expect(deviceAsked, isFalse,
        reason: 'an empty schedule must not open a device');
    scrubber.dispose();
    controller.dispose();
    store.dispose();
  });

  group('🗣️I-57 ②: a scrub that crosses into another cut hears THAT cut — '
      'the mix is decided again for the cut it reached', () {
    Future<
      ({
        AudioScrubber scrubber,
        QaAudioDevice device,
        void Function(CutId) standIn,
      })
    >
    scrubOver(Project project) async {
      final device = openNullDevice();
      var active = const CutId('cut-a');
      final controller = CanvasPlaybackController(
        resolveProject: () => project,
        resolveActiveCutId: () => active,
        resolveActiveTrackId: () => const TrackId('track'),
        resolveFrameRate: () => const ProjectFrameRate.integer(10),
      );
      final store = _residentStore();
      store.resultFor('tone.wav');
      await pumpEventQueue();
      final scrubber = AudioScrubber(
        controller: controller,
        resolveFrameRate: () => const ProjectFrameRate.integer(10),
        resolveProject: () => project,
        conformStore: store,
        resolveDevice: () => QaAudioDevice.instance,
      );
      addTearDown(() {
        scrubber.dispose();
        controller.dispose();
        store.dispose();
      });
      return (
        scrubber: scrubber,
        device: device,
        standIn: (CutId cut) => active = cut,
      );
    }

    test('from a silent cut into one with sound: it sounds', () async {
      final (:scrubber, :device, :standIn) = await scrubOver(
        _twoCuts(soundUnder: 'cut-b'),
      );

      scrubber.onScrubFrame(3);
      expect(scrubber.isArmed, isFalse, reason: 'fixture: cut A is silent');

      standIn(const CutId('cut-b'));
      scrubber.onScrubFrame(3);
      expect(scrubber.isArmed, isTrue, reason: 'cut B has sound of its own');
      expect(await _waitFor(() => device.positionSamples >= 14400), isTrue);
      scrubber.onScrubEnd();
    }, skip: skip);

    test('from a cut with sound into a silent one: the cut it left goes '
        'quiet — never played at the frame numbers of the cut it reached',
        () async {
      final (:scrubber, :device, :standIn) = await scrubOver(
        _twoCuts(soundUnder: 'cut-a'),
      );

      scrubber.onScrubFrame(3);
      expect(scrubber.isArmed, isTrue, reason: 'fixture: cut A sounds');

      standIn(const CutId('cut-b'));
      scrubber.onScrubFrame(5);
      expect(scrubber.isArmed, isFalse);
      expect(await _waitFor(() => !device.isPlaying), isTrue);
      scrubber.onScrubEnd();
    }, skip: skip);
  });

  group('🗣️F-341: where no cut is, a scrub hears the TRACK\'s sound — a sound '
      'row is the track\'s, not its cuts\'', () {
    Future<({AudioScrubber scrubber, QaAudioDevice device})> scrubOver(
      Project project, {
      required CutId? standingIn,
    }) async {
      final device = openNullDevice();
      final controller = CanvasPlaybackController(
        resolveProject: () => project,
        resolveActiveCutId: () => standingIn,
        resolveActiveTrackId: () => const TrackId('track'),
        resolveFrameRate: () => const ProjectFrameRate.integer(10),
      );
      final store = _residentStore();
      store.resultFor('tone.wav');
      await pumpEventQueue();
      final scrubber = AudioScrubber(
        controller: controller,
        resolveFrameRate: () => const ProjectFrameRate.integer(10),
        resolveProject: () => project,
        conformStore: store,
        resolveDevice: () => QaAudioDevice.instance,
      );
      addTearDown(() {
        scrubber.dispose();
        controller.dispose();
        store.dispose();
      });
      return (scrubber: scrubber, device: device);
    }

    test('a track with no cut at all', () async {
      final (:scrubber, :device) = await scrubOver(
        _soundWhereNoCutIs(cut: false, soundAt: 2),
        standingIn: null,
      );

      // Frame 3 at 10fps/48k = samples [14400, 19200).
      scrubber.onScrubTrackFrame(3);
      expect(scrubber.isArmed, isTrue);
      expect(await _waitFor(() => device.positionSamples >= 14400), isTrue);
      scrubber.onScrubEnd();
    }, skip: skip);

    test('out of a silent cut into the movie\'s trailing frames: the sound '
        'there, at the track\'s own frame', () async {
      final (:scrubber, :device) = await scrubOver(
        _soundWhereNoCutIs(cut: true, soundAt: 12),
        standingIn: const CutId('cut-a'),
      );

      scrubber.onScrubFrame(3);
      expect(scrubber.isArmed, isFalse, reason: 'fixture: cut A is silent');

      // Frame 13 = samples [62400, 67200).
      scrubber.onScrubTrackFrame(13);
      expect(scrubber.isArmed, isTrue);
      expect(await _waitFor(() => device.positionSamples >= 62400), isTrue);
      scrubber.onScrubEnd();
    }, skip: skip);
  });

  test('missing PCM stands the gesture down and kicks the conform for the '
      'next one', () async {
    openNullDevice();
    final project = _project();
    final controller = buildController(project);
    final store = _residentStore(); // nothing warmed yet
    final scrubber = AudioScrubber(
      controller: controller,
      resolveFrameRate: () => const ProjectFrameRate.integer(10),
      resolveProject: () => project,
      conformStore: store,
      resolveDevice: () => QaAudioDevice.instance,
    );

    scrubber.onScrubFrame(3);
    expect(scrubber.isArmed, isFalse);
    scrubber.onScrubEnd();

    await pumpEventQueue(); // the kicked conform lands
    scrubber.onScrubFrame(4);
    expect(scrubber.isArmed, isTrue);
    scrubber.onScrubEnd();
    scrubber.dispose();
    controller.dispose();
    store.dispose();
  }, skip: skip);

  group('🚨a sound past two minutes streams from a window, and a scrub hears '
      'it wherever the drag goes (scrub-recentres-by-its-own-rule)', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('qa-scrub-stream');
    });

    tearDown(() => deleteTempQuietly(directory));

    // Ten seconds past the line where a conform stays on disk, at 10 fps:
    // frame 1000 is a hundred seconds in.
    const frames = (conformStreamingThresholdSeconds + 10) * 10;

    /// A scrubber over 'long.wav', which streams from a conform on disk
    /// whose every sample is 0.25.
    Future<AudioScrubber> scrubbing() async {
      const samples = (conformStreamingThresholdSeconds + 10) * 48000;
      final path = '${directory.path}/long.conform';
      File(path).writeAsBytesSync(
        encodeConform(
          samples: Float32List(samples)..fillRange(0, samples, 0.25),
          channels: 1,
          sampleRate: 48000,
        ),
      );
      final store = AudioConformStore(
        resolveConformPath: (_) => path,
        runner: (request) async => ConformResult(
          outcome: ConformOutcome.built,
          conformBytes: mediaAppFileSource(path),
          channels: 1,
          sampleRate: 48000,
          frames: samples,
        ),
        log: (_) {},
      );
      addTearDown(store.dispose);
      store.resultFor('long.wav');
      await pumpEventQueue();
      expect(store.isStreaming('long.wav'), isTrue, reason: 'fixture');
      final project = _project(frames: frames, sound: 'long.wav');
      final controller = buildController(project);
      addTearDown(controller.dispose);
      final scrubber = AudioScrubber(
        controller: controller,
        resolveFrameRate: () => const ProjectFrameRate.integer(10),
        resolveProject: () => project,
        conformStore: store,
        resolveDevice: () => QaAudioDevice.instance,
      );
      addTearDown(scrubber.dispose);
      return scrubber;
    }

    test('🚨a drag backwards past the window\'s trailing edge is '
        'heard', () async {
      final device = openNullDevice();
      final scrubber = await scrubbing();
      scrubber.onScrubFrame(1000);
      expect(scrubber.isArmed, isTrue);
      expect(await _waitFor(() => !device.isPlaying), isTrue);
      device.stop(); // and the meter reads silence again

      scrubber.onScrubFrame(950);
      expect(await _waitFor(() => !device.isPlaying), isTrue);

      expect(
        device.peakFor(0),
        closeTo(0.25, 0.01),
        reason: 'five seconds behind where the window stood: ↩️the scrubber '
            'moved it only past half the playing lead (15 s) either way, and '
            'this slice played silence',
      );
      scrubber.onScrubEnd();
    }, skip: skip);

    test('a scrub\'s window reaches a second behind and two ahead — and moves '
        'once a drag is past half its lead', () async {
      openNullDevice();
      final scrubber = await scrubbing();
      final window = scrubber.debugWindow;

      scrubber.onScrubFrame(1000);
      expect(window.reach, AudioStreamingWindow.scrubbing);
      expect(window.centerSample, 1000 * 4800);
      scrubber.onScrubFrame(1010); // a second on: half the lead
      expect(window.centerSample, 1000 * 4800);
      scrubber.onScrubFrame(1011);
      expect(
        window.centerSample,
        1011 * 4800,
        reason: '↩️the playing reach — 32 s read at every move — would move '
            'it only fifteen seconds on',
      );
      scrubber.onScrubEnd();
    }, skip: skip);
  });
}

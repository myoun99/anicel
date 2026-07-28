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
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/playback/audio_scrubber.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';

import '../../helpers/native_engine_path.dart';

/// The audio scrub, driven for real on the null backend: each crossed
/// frame plays exactly its slice of the mix; release silences; playback
/// owning the device refuses the gesture; a silent cut never arms.
Project _project({bool withSound = true}) => Project(
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
          duration: 10,
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
                length: 10,
              ),
            },
            audioClips: [
              const AudioClip(
                filePath: 'tone.wav',
                frameId: FrameId('se-frame'),
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
}

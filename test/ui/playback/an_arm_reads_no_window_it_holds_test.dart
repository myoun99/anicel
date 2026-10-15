import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/conform_pcm_codec.dart';
import 'package:anicel/src/services/audio/conform_pcm_stream.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/playback/audio_device_transport.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';

import '../../helpers/native_engine_path.dart';
import '../../helpers/temp_dir.dart';

/// 🚨AN ARM READS NO WINDOW IT ALREADY HOLDS (play-press-first-frame-stall
/// Ⓐ, 10-15). A sound past two minutes streams from disk through a window
/// two seconds behind and thirty ahead. An arm — the press, a run going on,
/// a seek — re-centres it only where the window does not hold the arm
/// point, by the rule that moves it under a playing stream. ↩️Every arm
/// re-centred, and a run going on from where its press had just centred
/// the window read it off the disk and copied it twice: 🔬66ms and a GC on
/// the AMMI OP press.
///
/// The store counts the windows read; the device is the null backend at
/// 8 kHz, so a sound past the threshold stays small on disk.
void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();
  final skip = libraryPath != null ? false : nativeEngineMissingSkipReason;
  const deviceRate = 8000;
  const fps = ProjectFrameRate.integer(10);
  const soundFrames = deviceRate * (conformStreamingThresholdSeconds + 1);

  late Directory directory;

  setUp(() async {
    QaAudioDevice.debugResetForTests();
    debugQaEngineLibraryPathOverride = libraryPath;
    directory = await Directory.systemTemp.createTemp('qa-arm-window');
  });

  tearDown(() {
    try {
      QaAudioDevice.instance?.close();
    } on Object {
      // A device that never opened is fine to "close".
    }
    QaAudioDevice.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    deleteTempQuietly(directory);
  });

  test('a run going on from where its press centred the window, and a seek '
      'inside it, read nothing — a seek past it reads the window there',
      () async {
    final device = QaAudioDevice.instance!;
    expect(
      device.open(sampleRate: deviceRate, channels: 2, useNullBackend: true),
      deviceRate,
      reason: 'fixture: the null device runs at the rate it is asked',
    );
    final conformPath = '${directory.path}/long.wav.wav';
    File(conformPath).writeAsBytesSync(
      encodeConform(
        samples: Float32List(soundFrames)..fillRange(0, soundFrames, 0.1),
        channels: 1,
        sampleRate: deviceRate,
      ),
    );
    final store = _WindowCountingStore(
      resolveConformPath: (_) => conformPath,
      projectSampleRate: deviceRate,
      runner: (request) async => ConformResult(
        outcome: ConformOutcome.built,
        conformBytes: mediaAppFileSource(conformPath),
        channels: 1,
        sampleRate: deviceRate,
        frames: soundFrames,
      ),
      log: (_) {},
    );
    addTearDown(store.dispose);
    store.resultFor('long.wav');
    await pumpEventQueue();
    expect(store.isStreaming('long.wav'), isTrue, reason: 'fixture');

    final controller = CanvasPlaybackController(
      resolveProject: () => _project,
      resolveActiveCutId: () => const CutId('cut'),
      resolveActiveTrackId: () => const TrackId('track'),
      resolveFrameRate: () => fps,
    );
    addTearDown(controller.dispose);
    final transport = AudioDeviceTransport(
      controller: controller,
      resolveFrameRate: () => fps,
      resolveProject: () => _project,
      conformStore: store,
      resolveDevice: () => QaAudioDevice.instance,
    )..attach();
    addTearDown(transport.dispose);

    controller.play(scope: PlaybackScope.activeCut);
    expect(transport.carryingPlayback, isTrue, reason: 'fixture');
    expect(store.windowsRead, 1, reason: 'the press centres it, once');

    controller.seekToGlobalFrame(100); // 10 s — inside its near half
    expect(store.windowsRead, 1, reason: 'it holds ten seconds in');

    controller.seekToGlobalFrame(300); // 30 s — past its near half
    expect(store.windowsRead, 2, reason: 'thirty seconds in, it reads there');

    controller.seekToGlobalFrame(290); // a second behind the new centre
    expect(store.windowsRead, 2, reason: 'a step back inside reads nothing');
    controller.stop();
  }, skip: skip);
}

/// Forty seconds of film at 10 fps, one sound under all of it.
final Project _project = Project(
  id: const ProjectId('arm-window'),
  name: 'Arm window',
  createdAt: DateTime.utc(2026, 10, 15),
  tracks: [
    Track(
      id: const TrackId('track'),
      name: 'Video',
      cuts: [
        Cut(
          id: const CutId('cut'),
          name: 'A',
          duration: 400,
          canvasSize: const CanvasSize(width: 64, height: 36),
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
            0: const TimelineExposure.drawing(FrameId('se-frame'), length: 400),
          },
          audioClips: [
            AudioClip(filePath: 'long.wav', frameId: const FrameId('se-frame')),
          ],
        ),
      ],
    ),
  ],
);

/// A store that counts the windows read out of its streaming conforms — a
/// window upload asks for the reader once for each streaming clip.
class _WindowCountingStore extends AudioConformStore {
  _WindowCountingStore({
    required super.resolveConformPath,
    super.runner,
    super.projectSampleRate,
    super.log,
  });

  int windowsRead = 0;

  @override
  ConformPcmStreamReader? streamReaderFor(String sourcePath) {
    windowsRead += 1;
    return super.streamReaderFor(sourcePath);
  }
}

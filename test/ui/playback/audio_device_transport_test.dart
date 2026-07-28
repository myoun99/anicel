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
import 'package:anicel/src/ui/playback/audio_device_transport.dart';
import 'package:anicel/src/ui/playback/audio_playback_sync.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';

import '../../helpers/native_engine_path.dart';

/// The transport driven for real: miniaudio's null backend runs the actual
/// callback on an actual thread, so arming, the clock, pause/resume, seeks
/// and the loop re-arm are all genuinely exercised — everything short of a
/// speaker.
class _SilentClipPlayer implements AudioClipPlayer {
  _SilentClipPlayer(this.log);

  final List<String> log;

  @override
  Future<void> prepare(String filePath) async => log.add('prepare $filePath');

  @override
  Future<void> startAt(Duration position) async => log.add('start');

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

/// fps 10, ONE cut of 10 frames (exactly 1 s), one SE sound spanning it.
final Project _project = Project(
  id: const ProjectId('transport-project'),
  name: 'Transport',
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
        Layer(
          id: const LayerId('se'),
          name: 'S1',
          kind: LayerKind.se,
          frames: [
            Frame(id: const FrameId('se-frame'), duration: 1, strokes: const []),
          ],
          timeline: {
            0: TimelineExposure.drawing(const FrameId('se-frame'), length: 10),
          },
          audioClips: [
            const AudioClip(filePath: 'tone.wav', frameId: FrameId('se-frame')),
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
    // 1 s of quiet mono at 48k — length matches the 10-frame window.
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

  late CanvasPlaybackController controller;

  CanvasPlaybackController buildController() => CanvasPlaybackController(
    resolveProject: () => _project,
    resolveActiveCutId: () => const CutId('cut-a'),
    resolveActiveTrackId: () => const TrackId('track'),
    resolveFrameRate: () => const ProjectFrameRate.integer(10),
  );

  setUp(() {
    QaAudioDevice.debugResetForTests();
    debugQaEngineLibraryPathOverride = libraryPath;
    controller = buildController();
  });

  tearDown(() {
    controller.dispose();
    try {
      QaAudioDevice.instance?.close();
    } on Object {
      // A device that never opened is fine to "close".
    }
    QaAudioDevice.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
  });

  /// A null-backend device, pre-opened so the transport's lazy open is a
  /// no-op (the transport itself never asks for the null backend — that
  /// flag exists for tests and CI runners with no sound card).
  QaAudioDevice openNullDevice() {
    final device = QaAudioDevice.instance!;
    expect(
      device.open(sampleRate: 48000, channels: 2, useNullBackend: true),
      greaterThan(0),
    );
    return device;
  }

  AudioDeviceTransport buildTransport(
    AudioConformStore store, {
    int Function(int sampleRate)? offset,
  }) => AudioDeviceTransport(
    controller: controller,
    resolveFrameRate: () => const ProjectFrameRate.integer(10),
    resolveProject: () => _project,
    conformStore: store,
    resolveDevice: () => QaAudioDevice.instance,
    resolveUserOffsetSamples: offset,
  )..attach();

  test('no device → the transport stands down and the platform players '
      'carry the run', () async {
    final store = _residentStore();
    store.resultFor('tone.wav');
    await pumpEventQueue();

    final log = <String>[];
    final transport = AudioDeviceTransport(
      controller: controller,
      resolveFrameRate: () => const ProjectFrameRate.integer(10),
      resolveProject: () => _project,
      conformStore: store,
      resolveDevice: () => null,
    )..attach();
    final sync = AudioPlaybackSync(
      controller: controller,
      resolveFrameRate: () => const ProjectFrameRate.integer(10),
      durationSecondsFor: store.durationSecondsFor,
      playerFactory: () => _SilentClipPlayer(log),
      resolveProject: () => _project,
      deviceCarriesPlayback: () => transport.carryingPlayback,
    )..attach();

    controller.play(scope: PlaybackScope.activeCut);
    expect(transport.carryingPlayback, isFalse);
    expect(transport.clockStatus(), isNull);
    expect(log, contains('prepare tone.wav'),
        reason: 'the fallback must carry the run — silence is never OK');
    controller.stop();
    sync.dispose();
    transport.dispose();
    store.dispose();
  });

  test('PCM not resident yet → this run stands down and the NEXT one rides '
      'the device', () async {
    openNullDevice();
    final store = _residentStore();
    final transport = buildTransport(store);

    controller.play(scope: PlaybackScope.activeCut);
    expect(transport.carryingPlayback, isFalse,
        reason: 'nothing resident at activation — the fallback carries');
    controller.stop();

    await pumpEventQueue(); // the kicked conform lands
    controller.play(scope: PlaybackScope.activeCut);
    expect(transport.carryingPlayback, isTrue);
    controller.stop();
    transport.dispose();
    store.dispose();
  }, skip: skip);

  test('carrying a run: the device plays, the clock reads frames, pause '
      'stops the transport, resume re-arms', () async {
    final device = openNullDevice();
    final store = _residentStore();
    store.resultFor('tone.wav');
    await pumpEventQueue();

    final log = <String>[];
    final transport = buildTransport(store);
    final sync = AudioPlaybackSync(
      controller: controller,
      resolveFrameRate: () => const ProjectFrameRate.integer(10),
      durationSecondsFor: store.durationSecondsFor,
      playerFactory: () => _SilentClipPlayer(log),
      resolveProject: () => _project,
      deviceCarriesPlayback: () => transport.carryingPlayback,
    )..attach();

    controller.play(scope: PlaybackScope.activeCut);
    expect(transport.carryingPlayback, isTrue);
    expect(log, isEmpty,
        reason: 'the device carries — platform players must stand down');
    expect(await _waitFor(() => device.positionSamples > 0), isTrue,
        reason: 'the callback never ran');

    final status = transport.clockStatus();
    expect(status, isNotNull);
    expect(status!.globalFrame, inInclusiveRange(0, 9));
    expect(status.ended, isFalse);

    controller.pause();
    expect(await _waitFor(() => !device.isPlaying), isTrue);

    controller.resume();
    expect(await _waitFor(() => device.isPlaying), isTrue);
    controller.stop();
    expect(await _waitFor(() => !device.isPlaying), isTrue);
    sync.dispose();
    transport.dispose();
    store.dispose();
  }, skip: skip);

  test('arming mid-timeline clamps the clock at the arm frame while the '
      'device latency drains', () async {
    openNullDevice();
    final store = _residentStore();
    store.resultFor('tone.wav');
    await pumpEventQueue();
    final transport = buildTransport(store);

    controller.play(scope: PlaybackScope.activeCut, startGlobalFrame: 5);
    final status = transport.clockStatus();
    expect(status, isNotNull);
    expect(status!.globalFrame, greaterThanOrEqualTo(5),
        reason: 'pressing play at frame 5 must never flash frame 4');
    controller.stop();
    transport.dispose();
    store.dispose();
  }, skip: skip);

  test('a live seek re-arms the transport at the target frame', () async {
    final device = openNullDevice();
    final store = _residentStore();
    store.resultFor('tone.wav');
    await pumpEventQueue();
    final transport = buildTransport(store);

    controller.play(scope: PlaybackScope.activeCut);
    expect(await _waitFor(() => device.positionSamples > 0), isTrue);

    controller.seekToGlobalFrame(7); // frame 7 at 10fps/48k = sample 33600
    expect(await _waitFor(() => device.positionSamples >= 33600), isTrue);
    expect(transport.clockStatus()!.globalFrame, greaterThanOrEqualTo(7));
    controller.stop();
    transport.dispose();
    store.dispose();
  }, skip: skip);

  test('play-once: the device runs out and the clock reports the end',
      () async {
    final device = openNullDevice();
    final store = _residentStore();
    store.resultFor('tone.wav');
    await pumpEventQueue();
    final transport = buildTransport(store);

    controller.loopMode = PlaybackLoopMode.once;
    // Start near the end so the run is short (0.2 s + latency).
    controller.play(scope: PlaybackScope.activeCut, startGlobalFrame: 8);
    expect(await _waitFor(() => !device.isPlaying), isTrue,
        reason: 'the stop point must end the run');
    final status = transport.clockStatus();
    expect(status!.ended, isTrue);
    expect(status.globalFrame, 9);
    controller.stop();
    transport.dispose();
    store.dispose();
  }, skip: skip);

  test('a loop armed mid-timeline re-arms from zero after its first pass — '
      'and from then on the C wrap owns the seam', () async {
    final device = openNullDevice();
    final store = _residentStore();
    store.resultFor('tone.wav');
    await pumpEventQueue();
    final transport = buildTransport(store);

    controller.loopMode = PlaybackLoopMode.loop;
    controller.play(scope: PlaybackScope.activeCut, startGlobalFrame: 8);
    expect(await _waitFor(() => device.positionSamples > 0), isTrue);

    // First pass runs out (it was armed WITHOUT the C loop flag)...
    expect(await _waitFor(() => !device.isPlaying), isTrue);
    // ...and the next clock read re-arms from zero, looping.
    final status = transport.clockStatus();
    expect(status!.ended, isFalse);
    expect(status.globalFrame, 0);
    expect(await _waitFor(() => device.isPlaying), isTrue);

    // The pass after that is the C's own sample-exact wrap: it keeps
    // playing and never leaves the window.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(device.isPlaying, isTrue);
    expect(transport.clockStatus()!.globalFrame, inInclusiveRange(0, 9));
    controller.stop();
    transport.dispose();
    store.dispose();
  }, skip: skip);

  test('refreshSchedule swaps the mix MID-RUN (AUDIO-PRO R3): a layer '
      'fader change is heard without stopping the transport', () async {
    final device = openNullDevice();
    var project = _project;
    final liveController = CanvasPlaybackController(
      resolveProject: () => project,
      resolveActiveCutId: () => const CutId('cut-a'),
      resolveActiveTrackId: () => const TrackId('track'),
      resolveFrameRate: () => const ProjectFrameRate.integer(10),
    );
    final store = _residentStore();
    store.resultFor('tone.wav');
    await pumpEventQueue();
    final transport = AudioDeviceTransport(
      controller: liveController,
      resolveFrameRate: () => const ProjectFrameRate.integer(10),
      resolveProject: () => project,
      conformStore: store,
      resolveDevice: () => QaAudioDevice.instance,
    )..attach();

    liveController.loopMode = PlaybackLoopMode.loop;
    liveController.play(scope: PlaybackScope.activeCut);
    expect(transport.carryingPlayback, isTrue);
    expect(await _waitFor(() => device.peakFor(0) > 0.03), isTrue,
        reason: 'the 0.05 source should be metering');
    final before = device.positionSamples;

    // The live edit: the layer fader jumps to 10x (0.05 -> 0.5 on the bus).
    final track = project.tracks.first;
    project = project.copyWith(
      tracks: [
        Track(
          id: track.id,
          name: track.name,
          cuts: track.cuts,
          seLayers: [track.seLayers.first.copyWith(audioGain: 10)],
        ),
      ],
    );
    transport.refreshSchedule();

    expect(device.isPlaying, isTrue, reason: 'the swap must not stop audio');
    expect(
      await _waitFor(() => device.peakFor(0) > 0.4),
      isTrue,
      reason: 'the fader change must be heard mid-run',
    );
    expect(device.positionSamples, greaterThanOrEqualTo(before));
    liveController.stop();
    transport.dispose();
    liveController.dispose();
    store.dispose();
  }, skip: skip);

  test('the report reads off the device and converts both ways', () async {
    openNullDevice();
    final store = _residentStore();
    store.resultFor('tone.wav');
    await pumpEventQueue();
    final transport = buildTransport(store, offset: (rate) => rate ~/ 100);

    controller.play(scope: PlaybackScope.activeCut);
    final report = transport.report;
    expect(report.deviceOpen, isTrue);
    expect(report.deviceSampleRate, 48000);
    expect(report.userOffsetSamples, 480);
    expect(report.userOffsetMillis, 10);
    expect(report.summary, contains('48000Hz'));
    controller.stop();
    transport.dispose();
    store.dispose();
  }, skip: skip);
}

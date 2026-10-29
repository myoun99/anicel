import 'dart:developer' show Timeline;
import 'dart:math' as math;
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
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/se_sound.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/native/qa_audio_device.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/audio/sound_cannot_play.dart';
import 'package:anicel/src/ui/playback/audio_device_transport.dart';
import 'package:anicel/src/ui/playback/audio_recorder.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';

import '../../helpers/device_paced.dart';
import '../../helpers/native_engine_path.dart';

// The transport driven for real: miniaudio's null backend runs the actual
// callback on an actual thread, so arming, the clock, the wait for the
// sound, seeks and the loop re-arm are all genuinely exercised — everything
// short of a speaker.

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
            0: const TimelineExposure.drawing(FrameId('se-frame'), length: 10),
          },
          audioClips: [
            AudioClip(filePath: 'tone.wav', frameId: const FrameId('se-frame')),
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
    String? Function()? outputName,
  }) => AudioDeviceTransport(
    controller: controller,
    resolveFrameRate: () => const ProjectFrameRate.integer(10),
    resolveProject: () => _project,
    conformStore: store,
    resolveDevice: () => QaAudioDevice.instance,
    resolveUserOffsetSamples: offset,
    resolveOutputDeviceName: outputName,
  )..attach();

  /// The run's clock asks the transport whether it waits, as the rig's
  /// `PlaybackWait` does ([AudioDeviceTransport.soundIsComing]).
  void waitForTheSound(AudioDeviceTransport transport) =>
      controller.waitsOn = (_, {required placed}) => transport.soundIsComing;

  // playback-waits-for-its-sound (유저 2026-10-16, se-fallback Q2: 「대체
  // 재생을 안 쓰고, 소리가 준비될 때까지 기다린다」 · 「다만 그런식으로
  // 재생못하거나 하는 상황에선 제대로 메시지라던가 뭔가 표시 하도록」).
  // ↩️Each of these stood down onto the platform players, and the next run
  // rode the device.
  test('🚨no device → the run plays without its sound, says so, and does not '
      'wait for what will never come', () async {
    final store = _residentStore();
    store.resultFor('tone.wav');
    await pumpEventQueue();
    final transport = AudioDeviceTransport(
      controller: controller,
      resolveFrameRate: () => const ProjectFrameRate.integer(10),
      resolveProject: () => _project,
      conformStore: store,
      resolveDevice: () => null,
    )..attach();
    waitForTheSound(transport);

    controller.play(scope: PlaybackScope.activeCut);
    expect(transport.carryingPlayback, isFalse);
    expect(transport.outputRefused, isTrue);
    expect(transport.soundIsComing, isFalse);
    expect(controller.isWaiting, isFalse);
    expect(transport.clockStatus(), isNull);
    controller.stop();
    transport.dispose();
    store.dispose();
  });

  test('🚨PCM not resident yet → the run waits where it was put, and rides '
      'the device once the conform lands', () async {
    openNullDevice();
    final store = _residentStore();
    final transport = buildTransport(store);
    waitForTheSound(transport);

    controller.play(scope: PlaybackScope.activeCut, startGlobalFrame: 3);
    expect(transport.soundIsComing, isTrue);
    expect(controller.isWaiting, isTrue, reason: 'it stands for its sound');
    expect(transport.carryingPlayback, isFalse);

    await pumpEventQueue(); // the kicked conform lands
    expect(transport.soundIsComing, isFalse);
    expect(controller.isWaiting, isFalse, reason: 'it goes on');
    expect(transport.carryingPlayback, isTrue);
    expect(controller.playlistFrame, 3, reason: 'from where it was put');
    expect(transport.outputRefused, isFalse);
    expect(transport.cannotPlay, isEmpty);
    controller.stop();
    transport.dispose();
    store.dispose();
  }, skip: skip);

  test('🚨a run whose sound will never come plays without it, and names '
      'it — one undecodable source does not silence the rest', () async {
    openNullDevice();
    final store = AudioConformStore(
      resolveConformPath: (_) => null,
      runner: (request) async => const ConformResult(
        outcome: ConformOutcome.undecodable,
        error: 'fixture',
      ),
      log: (_) {},
    );
    store.resultFor('tone.wav');
    await pumpEventQueue();
    final transport = buildTransport(store);
    waitForTheSound(transport);

    controller.play(scope: PlaybackScope.activeCut);
    expect(transport.soundIsComing, isFalse);
    expect(controller.isWaiting, isFalse);
    expect(transport.cannotPlay, {'tone.wav': SoundCannotPlay.format});
    controller.stop();
    transport.dispose();
    store.dispose();
  }, skip: skip);

  test('🚨a run stopped while it waits for its sound waits no more — the '
      'landing does not start it again', () async {
    openNullDevice();
    final store = _residentStore();
    final transport = buildTransport(store);
    waitForTheSound(transport);

    controller.play(scope: PlaybackScope.activeCut);
    expect(transport.soundIsComing, isTrue, reason: 'fixture');
    controller.stop();
    expect(transport.soundIsComing, isFalse);

    await pumpEventQueue();
    expect(controller.isActive, isFalse);
    expect(transport.carryingPlayback, isFalse);
    transport.dispose();
    store.dispose();
  }, skip: skip);

  test('carrying a run: the device plays, the clock reads frames, stop '
      'stops the device', () async {
    final device = openNullDevice();
    final store = _residentStore();
    store.resultFor('tone.wav');
    await pumpEventQueue();

    final transport = buildTransport(store);

    controller.play(scope: PlaybackScope.activeCut);
    expect(transport.carryingPlayback, isTrue);
    transport.clockStatus(); // the clock's first look starts the device
    expect(
      await waitOnTheDevice(device, () => device.positionSamples > 0),
      isTrue,
      reason: 'the callback never ran',
    );

    final status = transport.clockStatus();
    expect(status, isNotNull);
    expect(status!.globalFrame, inInclusiveRange(0, 9));
    expect(status.ended, isFalse);

    // ⛔T28: the pause/resume round-trip is gone with the state it exercised.
    // What it was really checking — the device follows the controller in and
    // out of playback — is the play/stop pair, which this still covers.
    controller.stop();
    expect(await waitOnTheDevice(device, () => !device.isPlaying), isTrue);
    transport.dispose();
    store.dispose();
  }, skip: skip);

  test('a play over a run that plays is no start: the run keeps the sound it '
      'was made ready with', () async {
    final device = openNullDevice();
    final store = _residentStore();
    store.resultFor('tone.wav');
    await pumpEventQueue();
    final transport = buildTransport(store);

    controller.play(scope: PlaybackScope.activeCut);
    transport.clockStatus(); // the clock's first look starts the device
    expect(device.isPlaying, isTrue, reason: 'fixture');

    controller.play(scope: PlaybackScope.activeCut, startGlobalFrame: 5);
    expect(device.isPlaying, isTrue, reason: 'not made ready again');
    expect(transport.carryingPlayback, isTrue);
    controller.stop();
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

  /// play-press-first-frame-stall (10-15): the device started at the press,
  /// and the clock's first look — on the next frame that began, after the
  /// press's own work and the frame it held up — met a sound frames in. On
  /// the AMMI OP the playhead went 0 → 2, 0 → 3, 0 → 4.
  test('🚨the sound starts on the clock\'s first look, not at the press — a '
      'first look that comes late still stands on the frame play was '
      'pressed on', () async {
    final device = openNullDevice();
    final store = _residentStore();
    store.resultFor('tone.wav');
    await pumpEventQueue();
    final transport = buildTransport(store);

    controller.play(scope: PlaybackScope.activeCut, startGlobalFrame: 2);
    // What comes before the first look: three frames' time at 10 a second.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(device.isPlaying, isFalse, reason: 'the press only arms it');

    expect(
      transport.clockStatus()!.globalFrame,
      2,
      reason: '↩️started at the press, the first look read frame 4 or 5',
    );
    expect(device.isPlaying, isTrue, reason: 'the first look starts it');
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
    transport.clockStatus(); // the clock's first look starts the device
    expect(
      await waitOnTheDevice(device, () => device.positionSamples > 0),
      isTrue,
    );

    controller.seekToGlobalFrame(7); // frame 7 at 10fps/48k = sample 33600
    // The seek's run starts on its own first look, at the target.
    expect(transport.clockStatus()!.globalFrame, greaterThanOrEqualTo(7));
    expect(device.positionSamples, greaterThanOrEqualTo(33600));
    controller.stop();
    transport.dispose();
    store.dispose();
  }, skip: skip);

  /// 유저 2026-10-08: 「그 자리에서 멈췃다가 구워지면 이어서 재생」 — the
  /// sound waits with the clock, or it would be heard ahead of its picture.
  test('🚨a run that waits for its picture stops the device, and going on '
      'arms it again at the frame the run stands on', () async {
    final device = openNullDevice();
    final store = _residentStore();
    store.resultFor('tone.wav');
    await pumpEventQueue();
    final transport = buildTransport(store);
    final missing = <int>{};
    controller.waitsOn =
        (frame, {required placed}) => missing.contains(frame);

    controller.play(scope: PlaybackScope.activeCut);
    transport.clockStatus(); // the clock's first look starts the device
    expect(
      await waitOnTheDevice(device, () => device.positionSamples > 0),
      isTrue,
    );

    // The ruler is dragged onto a frame whose picture is not there.
    missing.add(7);
    final stoodAt = device.positionSamples;
    controller.seekToGlobalFrame(7);
    expect(controller.isWaiting, isTrue, reason: '⛔premise');
    expect(
      (device.positionSamples - stoodAt).abs(),
      lessThan(4800),
      reason: 'the device stands where it was stopped. Armed at frame 7 '
          '(sample 33600) and stopped in the same breath, it sounds a blip '
          'of the frame the run is waiting to show',
    );
    expect(await waitOnTheDevice(device, () => !device.isPlaying), isTrue);
    expect(
      transport.clockStatus(),
      isNull,
      reason: 'a clock that stands reads no device — and above all not '
          '「ended」, which would stop a run that plays once',
    );

    missing.clear();
    controller.lookAgain();
    expect(controller.isWaiting, isFalse);
    transport.clockStatus(); // the clock's first look starts the device
    // Frame 7 at 10fps/48k = sample 33600.
    expect(
      await waitOnTheDevice(
        device,
        () => device.isPlaying && device.positionSamples >= 33600,
      ),
      isTrue,
    );
    expect(transport.clockStatus()!.globalFrame, greaterThanOrEqualTo(7));
    controller.stop();
    transport.dispose();
    store.dispose();
  }, skip: skip);

  test('a run that waits from its first frame arms nothing until it goes on',
      () async {
    final device = openNullDevice();
    final store = _residentStore();
    store.resultFor('tone.wav');
    await pumpEventQueue();
    final transport = buildTransport(store);
    final missing = <int>{0};
    controller.waitsOn =
        (frame, {required placed}) => missing.contains(frame);

    controller.play(scope: PlaybackScope.activeCut);
    expect(transport.carryingPlayback, isTrue, reason: 'the run is its own');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(device.isPlaying, isFalse);

    missing.clear();
    controller.lookAgain();
    transport.clockStatus(); // the clock's first look starts the device
    expect(
      await waitOnTheDevice(device, () => device.positionSamples > 0),
      isTrue,
    );
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
    transport.clockStatus(); // the clock's first look starts the device
    expect(await waitOnTheDevice(device, () => !device.isPlaying), isTrue,
        reason: 'the stop point must end the run');
    final status = transport.clockStatus();
    expect(status!.ended, isTrue);
    expect(status.globalFrame, 9);
    controller.stop();
    transport.dispose();
    store.dispose();
  }, skip: skip);

  group('🗣️F-341: a track with no cut — the device carries the track\'s '
      'sound to the movie\'s end line', () {
    /// [_project]'s sound on a track whose cut was deleted: the end line
    /// stays, held by the trailing frames — 20 frames at fps 10.
    final noCut = _project.copyWith(
      trailingFrames: 20,
      tracks: [_project.tracks.single.copyWith(cuts: const [])],
    );

    ({CanvasPlaybackController controller, AudioDeviceTransport transport})
    rigFor(AudioConformStore store) {
      final controller = CanvasPlaybackController(
        resolveProject: () => noCut,
        resolveActiveCutId: () => null,
        resolveActiveTrackId: () => const TrackId('track'),
        resolveFrameRate: () => const ProjectFrameRate.integer(10),
      );
      final transport = AudioDeviceTransport(
        controller: controller,
        resolveFrameRate: () => const ProjectFrameRate.integer(10),
        resolveProject: () => noCut,
        conformStore: store,
        resolveDevice: () => QaAudioDevice.instance,
      )..attach();
      return (controller: controller, transport: transport);
    }

    test('the sound is heard', () async {
      final device = openNullDevice();
      final store = _residentStore();
      store.resultFor('tone.wav');
      await pumpEventQueue();
      final rig = rigFor(store);

      rig.controller.play(scope: PlaybackScope.allCuts);
      expect(rig.transport.carryingPlayback, isTrue);
      rig.transport.clockStatus(); // the clock's first look starts the device
      expect(
        await waitOnTheDevice(device, () => device.peakFor(0) > 0.03),
        isTrue,
      );
      rig.controller.stop();
      rig.transport.dispose();
      rig.controller.dispose();
      store.dispose();
    }, skip: skip);

    test('played once, the device runs out at the end line', () async {
      final device = openNullDevice();
      final store = _residentStore();
      store.resultFor('tone.wav');
      await pumpEventQueue();
      final rig = rigFor(store);

      rig.controller.loopMode = PlaybackLoopMode.once;
      rig.controller.play(scope: PlaybackScope.allCuts, startGlobalFrame: 18);
      rig.transport.clockStatus(); // the clock's first look starts the device
      expect(await waitOnTheDevice(device, () => !device.isPlaying), isTrue);
      final status = rig.transport.clockStatus();
      expect(status!.ended, isTrue);
      expect(status.globalFrame, 19, reason: 'the movie\'s last frame');
      rig.controller.stop();
      rig.transport.dispose();
      rig.controller.dispose();
      store.dispose();
    }, skip: skip);
  });

  test('a loop armed mid-timeline re-arms from zero after its first pass — '
      'and from then on the C wrap owns the seam', () async {
    final device = openNullDevice();
    final store = _residentStore();
    store.resultFor('tone.wav');
    await pumpEventQueue();
    final transport = buildTransport(store);

    controller.loopMode = PlaybackLoopMode.loop;
    controller.play(scope: PlaybackScope.activeCut, startGlobalFrame: 8);
    transport.clockStatus(); // the clock's first look starts the device
    expect(
      await waitOnTheDevice(device, () => device.positionSamples > 0),
      isTrue,
    );

    // First pass runs out (it was armed WITHOUT the C loop flag)...
    expect(await waitOnTheDevice(device, () => !device.isPlaying), isTrue);
    // ...and the next clock read re-arms from zero, looping.
    final status = transport.clockStatus();
    expect(status!.ended, isFalse);
    expect(status.globalFrame, 0);
    expect(await waitOnTheDevice(device, () => device.isPlaying), isTrue);

    // The pass after that is the C's own sample-exact wrap: it keeps
    // playing and never leaves the window — for a tenth of a second of its
    // own. ↩️Of the wall, which a starved device can sit through.
    final handed = Handed(device);
    await waitOnTheDevice(
      device,
      () => handed.samples >= 4800 || !device.isPlaying,
    );
    expect(device.isPlaying, isTrue);
    expect(transport.clockStatus()!.globalFrame, inInclusiveRange(0, 9));
    controller.stop();
    transport.dispose();
    store.dispose();
  }, skip: skip);

  test('refreshSchedule swaps the mix MID-RUN (AUDIO-PRO R3): a row '
      'volume change is heard without stopping the transport', () async {
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
    transport.clockStatus(); // the clock's first look starts the device
    expect(
      await waitOnTheDevice(device, () => device.peakFor(0) > 0.03),
      isTrue,
      reason: 'the 0.05 source should be metering',
    );
    final before = device.positionSamples;

    // The live edit: the row's volume jumps to 200% (0.05 -> 0.1 on the bus).
    final track = project.tracks.first;
    project = project.copyWith(
      tracks: [
        Track(
          id: track.id,
          name: track.name,
          cuts: track.cuts,
          seLayers: [
            track.seLayers.first.copyWith(
              seSound: SeSound(
                volume: PropertyTrack<double>(
                  keys: {0: const PropertyKey(2.0)},
                ),
              ),
            ),
          ],
        ),
      ],
    );
    transport.refreshSchedule();

    expect(device.isPlaying, isTrue, reason: 'the swap must not stop audio');
    expect(
      await waitOnTheDevice(device, () => device.peakFor(0) > 0.08),
      isTrue,
      reason: 'the volume change must be heard mid-run',
    );
    expect(device.positionSamples, greaterThanOrEqualTo(before));
    liveController.stop();
    transport.dispose();
    liveController.dispose();
    store.dispose();
  }, skip: skip);

  // 유저 2026-10-08: 「늦게바뀌는건 좀 많이 신경쓰이는데. 근본/구조적으로
  // 어떻게 안되나」 → 「소리 싱크나 영상이나 뭐 그런거 정확하기만하면되.」
  // The null device is a real one in every way but the sound: its callback
  // runs on its own thread every 10ms, and hands 480 samples each time.
  group('the picture reads the device\'s count as a line', () {
    test('🚨a frame changes BETWEEN two callbacks, where the stair stands '
        'still: the line has got to it, and the stair has not', () async {
      final device = openNullDevice();
      final store = _residentStore();
      store.resultFor('tone.wav');
      await pumpEventQueue();
      // Heard a little off what the device says, so that a frame's first
      // sample falls halfway up a step of the stair: no callback hands it.
      const step = 480;
      final offset = step ~/ 2 - device.latencySamples % step;
      final transport = buildTransport(store, offset: (_) => offset);

      controller.play(scope: PlaybackScope.activeCut);
      transport.clockStatus(); // the clock's first look starts the device
      expect(
        await waitOnTheDevice(device, () => device.clockPoint != null),
        isTrue,
        reason: 'no callback spoke',
      );

      // A change of frame with the stair the same BEFORE the reading
      // before it and AFTER this one is a change no step of the stair made.
      // Each change seen is a chance to catch one: forty of them, an idle
      // device's four seconds. ↩️Four seconds of the wall — a starved
      // device went two frames in them (10-17, a land gate under six runs).
      final watch = Stopwatch()..start();
      var stairBefore = device.positionSamples;
      var frame = transport.clockStatus()?.globalFrame;
      var changes = 0;
      var whereTheStairStood = 0;
      while (changes < 40 &&
          whereTheStairStood < 3 &&
          watch.elapsed < deviceStoppedAfter) {
        final before = device.positionSamples;
        final now = transport.clockStatus()?.globalFrame;
        final after = device.positionSamples;
        if (now != frame) {
          changes += 1;
          if (after == stairBefore) {
            whereTheStairStood += 1;
          }
        }
        frame = now;
        stairBefore = before;
      }

      expect(changes, greaterThan(2), reason: '⛔premise: frames went by');
      expect(
        whereTheStairStood,
        greaterThan(0),
        reason: 'read off the stair, a frame changes only when the stair '
            'climbs: a step late — here half a step, 5ms',
      );

      controller.stop();
      transport.dispose();
      store.dispose();
    }, skip: skip);

    test('🚨the lap is heard out: just after the device has wrapped, the '
        'picture is still on the lap\'s last frame', () async {
      final device = openNullDevice();
      final store = _residentStore();
      store.resultFor('tone.wav');
      await pumpEventQueue();
      final transport = buildTransport(store);

      // Ten frames at 10 a second, looping from the top: the device wraps
      // its own count every 48000 samples.
      controller.play(scope: PlaybackScope.activeCut);
      transport.clockStatus(); // the clock's first look starts the device
      expect(
        await waitOnTheDevice(device, () => device.clockPoint != null),
        isTrue,
      );

      // The frames read in the moments after a wrap: the latest callback
      // the first of a new lap, and what is HEARD then still 6ms or more
      // short of the lap's end. For as many laps as it takes — up to twelve
      // of the device's own, an idle one's twelve seconds. ↩️Twelve seconds
      // of the wall (10-17: none landed in them, a lane's run under five and
      // six others).
      //
      // ⚠️HEARD SHORT OF THE END, OR NOT AT ALL (10-15, TestFlight #73:
      // `[9, 0, 0, 0]`). A callback asked for late lies under the line by
      // its lateness, and the device has played on through what it carries
      // meanwhile — what the line is for: when a wrap's first callback comes
      // 20ms late, what is heard IS in the new lap, and frame 0 is the right
      // answer. So a reading counts by where it hears: the step's own count,
      // its callback's lateness and the reading's age, less the latency.
      // ↩️「However late that callback came」 — true of none later than the
      // latency less a step.
      // ↩️A callback within 4ms of on time, read within 10ms of it (10-29,
      // Developer ID build 1080: none in twelve laps, 4/4 and alone, while
      // TestFlight's runner passed the same head). The worst reading that
      // let in was heard 480 + 192 + 480 past the wrap, of the 1440 the
      // null device carries: those 288 short of the end stand, the split
      // between lateness and age does not.
      const shortOfTheEnd = 288;
      final lateness = _CallbackLateness(rate: 48000, lap: 48000);
      final justWrapped = <int>[];
      final handed = Handed(device);
      final watch = Stopwatch()..start();
      var nearTheEnd = false;
      // What the wraps offered, for a premise that fails.
      final wrapSteps = <int>{};
      int? nearest;
      var straddled = 0;
      while (justWrapped.length < 4 &&
          handed.samples < 12 * 48000 &&
          watch.elapsed < deviceStoppedAfter) {
        final clock = device.readClock();
        final status = transport.clockStatus();
        final after = device.readClock();
        final point = clock.point;
        if (point == null || status == null) {
          continue;
        }
        final late = lateness.of(point);
        // ⚠️ONE MOMENT OR NONE. The status reads the clock itself, a moment
        // after this reading; a runner that stalls between the two lines
        // answers for a later moment than the one judged below — the mac
        // runner read frame 0 so (10-08: `[0, 9, 9, 9]`), the lap's end
        // heard past by the time the status looked. A reading a callback
        // or 2ms came between is not one.
        if (after.point != point || after.nowMicros - clock.nowMicros > 2000) {
          straddled += 1;
          continue;
        }
        if (point.positionSamples > 40000) {
          nearTheEnd = true;
        } else if (point.positionSamples > 480) {
          nearTheEnd = false;
        } else if (nearTheEnd) {
          // Aged to [after]: the status read its clock before that did, so
          // the moment it answers for is no later.
          final age =
              (after.nowMicros - point.atMicros) *
              48000 ~/
              Duration.microsecondsPerSecond;
          final past = point.positionSamples + late + age;
          wrapSteps.add(point.atMicros);
          nearest = math.min(nearest ?? past, past);
          if (past < device.latencySamples - shortOfTheEnd) {
            justWrapped.add(status.globalFrame);
          }
        }
      }

      expect(
        justWrapped,
        isNotEmpty,
        reason: '⛔premise: no reading landed in the step after a wrap — '
            '${wrapSteps.length} wrap step(s) read, the nearest heard '
            '$nearest past the wrap (under '
            '${device.latencySamples - shortOfTheEnd} lands), $straddled '
            'reading(s) a callback or 2ms came between',
      );
      expect(
        justWrapped,
        everyElement(9),
        reason: 'the device has HANDED the lap\'s last sample, and what is '
            'heard is 30ms short of it: the last frame. ↩️Read off the '
            'wrapped count, the picture was back on frame 0 here',
      );
      expect(
        await waitOnTheDevice(device, () {
          final frame = transport.clockStatus()?.globalFrame;
          return frame != null && frame >= 1 && frame <= 4;
        }),
        isTrue,
        reason: 'and it goes ON into the new lap, once that is heard — the '
            'count is kept through the wrap, and folded into the run',
      );

      controller.stop();
      transport.dispose();
      store.dispose();
    }, skip: skip);

    // What is HEARD is what the device has handed, less its latency and
    // less the user's own correction. The line stands at the stair or past it,
    // and no further past what was handed than the device carries — so one
    // reading, with the stair read before it and after it, is held between
    // the two, however slow the machine is.
    //
    // A frame is 4800 samples here: 10 a second at 48k.
    const frameSamples = 4800;

    test('🚨read at a frame\'s own time, a tick that runs late reads where '
        'one on time reads (the-clock-is-read-when-the-tick-runs)', () async {
      final device = openNullDevice();
      final store = _residentStore();
      store.resultFor('tone.wav');
      await pumpEventQueue();
      final transport = buildTransport(store);

      controller.play(scope: PlaybackScope.activeCut);
      transport.clockStatus(); // the clock's first look starts the device
      expect(
        await waitOnTheDevice(device, () => device.clockPoint != null),
        isTrue,
      );

      // Ticks that each read the time of the frame they run in: the gap
      // between that time and the device's clock is followed.
      Duration frameNow() => Duration(microseconds: device.clockNowMicros);
      for (var tick = 0; tick < 24; tick += 1) {
        transport.clockStatus(frameTime: frameNow());
        await Future<void>.delayed(const Duration(milliseconds: 4));
      }
      final frame = frameNow();
      final onTime = transport.clockStatus(frameTime: frame)!.globalFrame;
      // Late by the device's own three and a half frames — read off its
      // count alone, so the transport's following is not touched; past the
      // most its line stands ahead of its count (its latency, 30ms), three
      // frames. ↩️450ms of the wall: a starved device went none in them
      // (10-17, a land gate under six runs).
      final handed = Handed(device);
      expect(
        await waitOnTheDevice(
          device,
          () => handed.samples >= 3 * frameSamples + frameSamples ~/ 2,
        ),
        isTrue,
        reason: 'the device stopped',
      );
      final late = transport.clockStatus(frameTime: frame)!.globalFrame;
      // Read after it: what the clock says NOW is never stepped back from.
      final now = transport.clockStatus()!.globalFrame;

      // How far on, round the lap: the run loops its ten frames, and a busy
      // machine carries it past the end between two readings. ↩️Taken as
      // read, a wrap between them read -6 (a loaded gate run, 저장 10-15).
      int on(int from, int to) => (to - from) % 10;
      expect(
        on(onTime, now),
        greaterThanOrEqualTo(3),
        reason: '⛔premise: read when it ran, the late tick is frames on',
      );
      expect(
        on(onTime, late),
        lessThanOrEqualTo(1),
        reason: 'the same frame\'s time reads where it read — the gap moves '
            'a sixteenth of a lateness, not all of it',
      );

      controller.stop();
      transport.dispose();
      store.dispose();
    }, skip: skip);

    test('🚨the user\'s own correction moves what is heard: three frames\' '
        'worth of it is three frames', () async {
      final device = openNullDevice();
      final store = _residentStore();
      store.resultFor('tone.wav');
      await pumpEventQueue();
      // The picture three frames EARLIER (a negative correction, as the
      // settings read it): what is heard is three frames further on.
      const correction = -3 * frameSamples;
      final transport = buildTransport(store, offset: (_) => correction);

      controller.play(scope: PlaybackScope.activeCut);
      transport.clockStatus(); // the clock's first look starts the device
      expect(
        await waitOnTheDevice(device, () => device.clockPoint != null),
        isTrue,
      );

      final before = device.positionSamples;
      final frame = transport.clockStatus()!.globalFrame;
      final after = device.positionSamples;
      int frameHeardAt(int handed) =>
          (handed - device.latencySamples - correction) ~/ frameSamples;
      expect(
        after,
        lessThan(6 * frameSamples),
        reason: '⛔premise: still well inside the first lap',
      );
      expect(
        frame,
        inInclusiveRange(
          frameHeardAt(before),
          frameHeardAt(after + device.latencySamples),
        ),
        reason: 'without the correction it would be three frames back',
      );

      controller.stop();
      transport.dispose();
      store.dispose();
    }, skip: skip);

    test('🚨a run started again reads from where it was started: the count '
        'of the run before is not carried into it', () async {
      final device = openNullDevice();
      final store = _residentStore();
      store.resultFor('tone.wav');
      await pumpEventQueue();
      final transport = buildTransport(store);

      controller.play(scope: PlaybackScope.activeCut);
      expect(
        await waitOnTheDevice(
          device,
          () => (transport.clockStatus()?.globalFrame ?? 0) >= 3,
        ),
        isTrue,
        reason: '⛔premise: the first run got somewhere',
      );

      // Back to the top while it plays — the run started again starts on its
      // own first look.
      controller.seekToGlobalFrame(0);
      transport.clockStatus();
      expect(
        await waitOnTheDevice(device, () {
          final point = device.clockPoint;
          return point != null && point.positionSamples < 2 * frameSamples;
        }),
        isTrue,
        reason: 'the run started again never spoke',
      );
      final frame = transport.clockStatus()!.globalFrame;
      final after = device.positionSamples;
      expect(
        frame,
        lessThanOrEqualTo(after ~/ frameSamples),
        reason: 'no further on than the device has handed since it was '
            'started again',
      );

      controller.stop();
      transport.dispose();
      store.dispose();
    }, skip: skip);

    test('🚨a run that plays once has no lap to be folded into: heard past '
        'its end — the user\'s correction can put it there — the picture is '
        'at its end, not back at its first frame', () async {
      final device = openNullDevice();
      final store = _residentStore();
      store.resultFor('tone.wav');
      await pumpEventQueue();
      // Heard two frames early (the picture two frames earlier — a negative
      // correction): while the device hands the run's last frames, what is
      // heard is already past the end of it.
      const correction = -2 * frameSamples;
      final transport = buildTransport(store, offset: (_) => correction);

      controller.loopMode = PlaybackLoopMode.once;
      controller.play(scope: PlaybackScope.activeCut, startGlobalFrame: 7);
      transport.clockStatus(); // the clock's first look starts the device
      final pastTheEnd = <int>[];
      // Until the device has played it out, however long it takes.
      // ↩️Three seconds of the wall, which a starved device can spend on
      // the run's three frames.
      final watch = Stopwatch()..start();
      while (watch.elapsed < deviceStoppedAfter && device.isPlaying) {
        final before = device.positionSamples;
        final status = transport.clockStatus();
        if (status != null &&
            !status.ended &&
            before - device.latencySamples - correction >= 10 * frameSamples) {
          pastTheEnd.add(status.globalFrame);
        }
      }

      expect(
        pastTheEnd,
        isNotEmpty,
        reason: '⛔premise: no reading while the last frames were handed',
      );
      expect(
        pastTheEnd,
        everyElement(greaterThanOrEqualTo(9)),
        reason: 'the run has ten frames; folded into a lap it has not got, '
            'this read frame 0',
      );

      controller.stop();
      transport.dispose();
      store.dispose();
    }, skip: skip);
  });

  // board a-start-is-heard-ahead-of-its-first-picture: a frame is shown
  // refreshes after the look that starts its run, and a device started ON
  // the run's first sample was heard that much ahead of it — the first look
  // read frames on, and the frames between were never shown.
  group('🚨a run\'s first sample is heard as its first picture is shown', () {
    const frameSamples = 4800;

    /// When a look's frame is shown: [ahead] from now, on the FRAME clock —
    /// the clock the engine's frame times are on, which the sound reads them
    /// on (`HeardOnTheDevice`, `FrameTimeOnDevice`). ↩️It was the device's
    /// clock, the frame clock's own on Windows alone: on the Mac runners the
    /// frame clock stood further ahead of it than the 300ms looked ahead,
    /// and the lead came out nothing (release 10-22, macOS · TestFlight).
    Duration shownIn(Duration ahead) =>
        Duration(microseconds: Timeline.now) + ahead;

    test('a first look whose frame is shown three frames on starts the device '
        'that far ahead, in silence, and reads the frame play was pressed on',
        () async {
      final device = openNullDevice();
      final store = _residentStore();
      store.resultFor('tone.wav');
      await pumpEventQueue();
      final transport = buildTransport(store);

      controller.play(scope: PlaybackScope.activeCut, startGlobalFrame: 2);
      final status = transport.clockStatus(
        frameTime: shownIn(const Duration(milliseconds: 300)),
      );
      final handed = device.positionSamples;

      expect(
        status!.globalFrame,
        2,
        reason: '↩️started on its first sample, it read frame 4 — three '
            'frames\' time, less what the device holds, ahead',
      );
      expect(
        handed,
        lessThan(2 * frameSamples),
        reason: 'the device stands ahead of the run\'s first sample',
      );
      controller.stop();
      transport.dispose();
      store.dispose();
    }, skip: skip);

    test('🚨and so does the loop\'s second pass: its run starts afresh at the '
        'look that finds the first pass run out', () async {
      final device = openNullDevice();
      final store = _residentStore();
      store.resultFor('tone.wav');
      await pumpEventQueue();
      final transport = buildTransport(store);

      controller.loopMode = PlaybackLoopMode.loop;
      controller.play(scope: PlaybackScope.activeCut, startGlobalFrame: 8);
      transport.clockStatus(); // the clock's first look starts the device
      expect(await waitOnTheDevice(device, () => !device.isPlaying), isTrue);

      final status = transport.clockStatus(
        frameTime: shownIn(const Duration(milliseconds: 300)),
      );
      final handed = device.positionSamples;
      expect(status!.globalFrame, 0);
      expect(
        handed,
        lessThan(0),
        reason: 'the second pass\'s first sample is heard as its first look '
            'is shown — ↩️started on it, heard three frames ahead',
      );
      controller.stop();
      transport.dispose();
      store.dispose();
    }, skip: skip);
  });

  // take-head-trims-at-the-playback-start (10-15): a take is placed by what
  // the microphone had taken in when its anchor was heard.
  group('🚨a take\'s head is what the microphone had taken in when its '
      'anchor was HEARD', () {
    /// A take of the null microphone with a roll under it that starts, at
    /// frame 2, once the microphone has taken in [late] by its own count;
    /// the head of anchor frame 2 as the clock's looks measure it, measured
    /// again once the roll's device has played [readAgainAfter] more — and
    /// what the microphone had been given when the roll started.
    Future<({int head, int again, int startedAt})> takeWithItsRoll({
      Duration late = Duration.zero,
      Duration readAgainAfter = Duration.zero,
    }) async {
      int samplesOf(Duration span) =>
          span.inMicroseconds * 48000 ~/ Duration.microsecondsPerSecond;
      final device = openNullDevice();
      final store = _residentStore();
      store.resultFor('tone.wav');
      await pumpEventQueue();
      final transport = buildTransport(store);
      final recorder = AudioRecorder(device: device);
      expect(recorder.start(sampleRate: 48000, useNullBackend: true), 48000);
      expect(
        await waitOnTheDevice(
          device,
          () => device.readCaptureClock().stairSamples >= samplesOf(late),
        ),
        isTrue,
        reason: 'the microphone stopped',
      );

      controller.play(scope: PlaybackScope.activeCut, startGlobalFrame: 2);
      transport.clockStatus(); // the clock's first look starts the device
      final startedAt = device.readCaptureClock().stairSamples;
      Future<int> measure() async {
        final heads = <int>[];
        transport.measureTakeHead(
          recorder,
          anchorFrame: 2,
          measured: heads.add,
        );
        expect(
          await waitOnTheDevice(device, () {
            transport.clockStatus(); // a look, a vsync at a time
            return heads.isNotEmpty;
          }),
          isTrue,
          reason: 'the anchor was never heard',
        );
        transport.clockStatus();
        expect(heads, hasLength(1), reason: 'measured once, and it stands');
        return heads.single;
      }

      final head = await measure();
      final handed = Handed(device);
      expect(
        await waitOnTheDevice(
          device,
          () => handed.samples >= samplesOf(readAgainAfter),
        ),
        isTrue,
        reason: 'the device stopped',
      );
      final again = await measure();

      recorder.stop();
      controller.stop();
      transport.dispose();
      store.dispose();
      return (head: head, again: again, startedAt: startedAt);
    }

    // ⚠️FAR APART, AND A QUARTER OF IT TO SPARE (10-15). The null devices
    // are threads, not hardware: an OS that starves one holds its line
    // back, or lets it run up to its whole latency past its last callback —
    // on the macOS runner the two measures of one take stood 56ms apart
    // (run 38724122175; 3ms on Windows). What these pin is WHICH moment a
    // head is of, and a head of the wrong moment is off by the whole
    // interval — so a quarter of it is the line between the two. ↩️A third
    // of a second with 50ms to spare, and a quarter second with 20ms: both
    // sat inside what a starved thread can move. (The measure again stays
    // inside the run's first pass — 0.8s from frame 2 — for a wrap arms the
    // line afresh.)
    test('a roll that starts a second after the microphone puts a second '
        'more on the head', () async {
      final onTime = await takeWithItsRoll();
      final late = await takeWithItsRoll(late: const Duration(seconds: 1));
      // A second or more: how much more, the microphone says, as the roll
      // starts. ↩️A second of the wall, taken as read — a busy machine slept
      // three and a half through it, and the heads stood that far apart,
      // rightly (10-17, a land gate under six runs).
      expect(
        late.head - onTime.head,
        closeTo(late.startedAt - onTime.startedAt, 12000),
        reason: '↩️the head was estimated — the output latency, as if the '
            'roll started the instant the microphone did: these two read the '
            'same',
      );
    }, skip: skip);

    test('the head is of the moment the anchor was heard: measured 0.4s '
        'later, it measures the same', () async {
      final take = await takeWithItsRoll(
        readAgainAfter: const Duration(milliseconds: 400),
      );
      expect(
        take.again,
        closeTo(take.head, 4800),
        reason: 'what was taken in since comes off with the time since',
      );
    }, skip: skip);

    test('an anchor not heard yet is not measured, and a take whose '
        'microphone is not taking in is let go', () async {
      final device = openNullDevice();
      final store = _residentStore();
      store.resultFor('tone.wav');
      await pumpEventQueue();
      final transport = buildTransport(store);
      final recorder = AudioRecorder(device: device);
      Future<void> takeIn() async {
        expect(recorder.start(sampleRate: 48000, useNullBackend: true), 48000);
        expect(
          await waitOnTheDevice(
            device,
            () => device.readCaptureClock().point != null,
          ),
          isTrue,
          reason: 'fixture: the microphone is taking in',
        );
      }

      await takeIn();
      controller.play(scope: PlaybackScope.activeCut, startGlobalFrame: 2);
      transport.clockStatus(); // the clock's first look starts the device
      final heads = <int>[];
      transport.measureTakeHead(recorder, anchorFrame: 9, measured: heads.add);
      transport.clockStatus();
      expect(heads, isEmpty, reason: 'frame 9 is most of a second ahead');

      expect(
        await waitOnTheDevice(
          device,
          () => (transport.clockStatus()?.globalFrame ?? 0) >= 3,
        ),
        isTrue,
        reason: 'fixture: frame 2 has been heard',
      );
      recorder.stop();
      transport.measureTakeHead(recorder, anchorFrame: 2, measured: heads.add);
      transport.clockStatus();
      await takeIn();
      transport.clockStatus();
      expect(
        heads,
        isEmpty,
        reason: 'looked at with nothing recording, the take was let go — '
            'the microphone that starts after is another take',
      );

      recorder.stop();
      controller.stop();
      transport.dispose();
      store.dispose();
    }, skip: skip);
  });

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

  // play-press-first-frame-stall-Q1 (유저 10-15: 「프로젝트를 열면 미리
  // 연다(UI 스레드 밖에서)」): the output opened ahead of a run, and opened
  // again ahead for a changed setting — never at the press, where the open
  // held the UI thread for 63–272 ms.
  group('the output opened ahead', () {
    /// The device, closed, on the null backend from here on — so the
    /// transport's own road opens it there ([QaAudioDevice.open]).
    QaAudioDevice aBenchDevice() {
      final device = QaAudioDevice.instance!;
      expect(device.open(useNullBackend: true), greaterThan(0));
      device.close();
      return device;
    }

    Future<AudioConformStore> resident() async {
      final store = _residentStore()..resultFor('tone.wav');
      addTearDown(store.dispose);
      await pumpEventQueue();
      return store;
    }

    test('🚨opened ahead, the first run rides the output it finds open',
        () async {
      final device = aBenchDevice();
      final transport = buildTransport(await resident());
      addTearDown(transport.dispose);

      transport.openAhead();
      expect(device.isOpening, isTrue);
      await pumpEventQueue();
      expect(device.isOpen, isTrue, reason: 'open before any run');

      controller.play(scope: PlaybackScope.activeCut);
      expect(transport.carryingPlayback, isTrue);
      controller.stop();
    }, skip: skip);

    test('🚨an output a run opens itself is open for the setting it was '
        'opened under — whoever opens it says so', () async {
      final device = aBenchDevice();
      final transport = buildTransport(
        await resident(),
        outputName: () => 'one',
      );
      addTearDown(transport.dispose);

      controller.play(scope: PlaybackScope.activeCut);
      expect(transport.carryingPlayback, isTrue, reason: 'opened at the run');
      expect(device.openedFor, 'one');
      controller.stop();
      await pumpEventQueue();
    }, skip: skip);

    test('🚨a run pressed while its output opens waits for the open, and goes '
        'on on it — ↩️it stood down onto the fallback, and the next run rode '
        'the output', () async {
      final device = aBenchDevice();
      final transport = buildTransport(await resident());
      addTearDown(transport.dispose);
      waitForTheSound(transport);

      transport.openAhead();
      controller.play(scope: PlaybackScope.activeCut);
      expect(device.isOpening, isTrue, reason: 'fixture: pressed mid-open');
      expect(transport.soundIsComing, isTrue);
      expect(controller.isWaiting, isTrue);
      expect(transport.carryingPlayback, isFalse);

      await pumpEventQueue();
      expect(controller.isWaiting, isFalse);
      expect(transport.carryingPlayback, isTrue);
      controller.stop();
    }, skip: skip);

    test('🚨a setting changed under a run is not followed until the run '
        'ends — then the output is opened again for it', () async {
      final device = aBenchDevice();
      String? name;
      final transport = buildTransport(
        await resident(),
        outputName: () => name,
      );
      addTearDown(transport.dispose);
      transport.openAhead();
      await pumpEventQueue();
      controller.play(scope: PlaybackScope.activeCut);
      expect(transport.carryingPlayback, isTrue, reason: 'fixture');

      name = 'another';
      transport.openAhead();
      await pumpEventQueue();
      expect(device.openedFor, isNull, reason: 'never under the run');
      expect(transport.carryingPlayback, isTrue);

      controller.stop();
      await pumpEventQueue();
      expect(device.isOpen, isTrue);
      expect(device.openedFor, 'another');
    }, skip: skip);

    test('🚨a run that finds the output open for another setting opens it '
        'again ahead and waits for it — ↩️it reopened at the press, and then '
        'stood down onto the fallback', () async {
      final device = aBenchDevice();
      var name = 'one';
      final transport = buildTransport(
        await resident(),
        outputName: () => name,
      );
      addTearDown(transport.dispose);
      waitForTheSound(transport);
      transport.openAhead();
      await pumpEventQueue();

      name = 'another';
      controller.play(scope: PlaybackScope.activeCut);
      expect(transport.carryingPlayback, isFalse);
      expect(device.isOpening, isTrue, reason: 'opened again off the press');
      expect(controller.isWaiting, isTrue);

      await pumpEventQueue();
      expect(device.openedFor, 'another');
      expect(controller.isWaiting, isFalse);
      expect(transport.carryingPlayback, isTrue);
      controller.stop();
    }, skip: skip);

    test('🚨a run that finds the output open at another rate than its sound '
        'opens it again ahead at that rate, and waits for it — ↩️it played '
        'every source through a rate conversion, or stood down while one '
        'was made', () async {
      final device = QaAudioDevice.instance!;
      expect(
        device.open(sampleRate: 44100, channels: 2, useNullBackend: true),
        greaterThan(0),
      );
      final transport = buildTransport(await resident());
      addTearDown(transport.dispose);
      waitForTheSound(transport);

      controller.play(scope: PlaybackScope.activeCut);
      expect(device.openedAtRate, 44100, reason: 'fixture');
      expect(transport.soundIsComing, isTrue);
      expect(device.isOpening, isTrue);

      await pumpEventQueue();
      expect(device.openedAtRate, 48000);
      expect(controller.isWaiting, isFalse);
      expect(transport.carryingPlayback, isTrue);
      controller.stop();
    }, skip: skip);

    test('🚨a transport going lets the output go: closed where nobody else '
        'keeps it — ↩️it closed it under every other open project', () async {
      final device = aBenchDevice();
      final transport = buildTransport(await resident());
      transport.openAhead();
      await pumpEventQueue();
      final another = Object();
      device.keep(another);

      transport.dispose();
      expect(device.isOpen, isTrue, reason: 'another keeps it');

      device.letGo(another);
      expect(device.isOpen, isFalse);
    }, skip: skip);

    test('🚨a transport going while its output is being opened ahead closes '
        'it once the open lands — a project closed as it opens leaves no '
        'output open that nobody keeps', () async {
      final device = aBenchDevice();
      final transport = buildTransport(await resident());
      transport.openAhead();
      expect(device.isOpening, isTrue, reason: 'fixture');

      transport.dispose();
      await pumpEventQueue();
      expect(device.isOpen, isFalse);
    }, skip: skip);

    test('🚨a transport going silences the run it carries — the output stays '
        'open where another keeps it', () async {
      final device = aBenchDevice();
      final transport = buildTransport(await resident());
      final another = Object();
      device.keep(another);
      addTearDown(() => device.letGo(another));
      controller.play(scope: PlaybackScope.activeCut);
      transport.clockStatus(); // the clock's first look starts the device
      expect(device.isPlaying, isTrue, reason: 'fixture');

      transport.dispose();
      expect(device.isPlaying, isFalse);
      expect(device.isOpen, isTrue, reason: 'another keeps it');
      controller.stop();
    }, skip: skip);

    test('🚨a transport going leaves alone a sound it does not carry — ↩️it '
        'stopped the output whatever played, and a project closed behind the '
        'one on screen silenced the run there', () async {
      final device = aBenchDevice();
      final transport = buildTransport(await resident());
      final another = Object();
      device.keep(another);
      addTearDown(() => device.letGo(another));
      transport.openAhead();
      await pumpEventQueue();
      expect(device.play(startSample: 0), isNonZero, reason: 'another\'s sound');

      transport.dispose();
      expect(device.isPlaying, isTrue);
    }, skip: skip);

    test('🚨a run ending after another player took the output leaves that '
        'sound alone — its end silences its own run only', () async {
      final device = aBenchDevice();
      final transport = buildTransport(await resident());
      final another = Object();
      device.keep(another);
      addTearDown(() => device.letGo(another));
      controller.play(scope: PlaybackScope.activeCut);
      transport.clockStatus(); // the clock's first look starts the device
      expect(device.isPlaying, isTrue, reason: 'fixture: the run sounds');
      expect(device.play(startSample: 0), isNonZero, reason: 'another\'s');

      controller.stop();
      expect(
        device.isPlaying,
        isTrue,
        reason: '↩️the run\'s end stopped the output whatever played',
      );
    }, skip: skip);
  });
}

/// How late a device's callbacks were asked for, in samples: how far each
/// one's point stands under the line through the highest point of the last
/// half second — the line's own measure (`DeviceClockLine`), kept apart
/// from it here so a pin can tell a callback that came on time.
class _CallbackLateness {
  _CallbackLateness({required this.rate, required this.lap});

  final int rate;
  final int lap;

  /// Each point by its stamp, as where its line stands: its count, kept on
  /// through every lap, less what the device plays by the stamp — in
  /// millionths of a sample, from the first stamp.
  final Map<int, int> _heights = {};
  int? _epoch;
  int _laps = 0;
  int _last = 0;

  int of(({int positionSamples, int atMicros}) point) {
    if (!_heights.containsKey(point.atMicros)) {
      if (point.positionSamples < _last) {
        _laps += 1;
      }
      _last = point.positionSamples;
    }
    final at = point.atMicros - (_epoch ??= point.atMicros);
    final height =
        (point.positionSamples + _laps * lap) * Duration.microsecondsPerSecond -
        rate * at;
    _heights[point.atMicros] = height;
    _heights.removeWhere(
      (stamped, _) =>
          point.atMicros - stamped > 500 * Duration.microsecondsPerMillisecond,
    );
    final highest = _heights.values.reduce((a, b) => a > b ? a : b);
    return (highest - height) ~/ Duration.microsecondsPerSecond;
  }
}

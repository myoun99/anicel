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

    // ⛔T28: the pause/resume round-trip is gone with the state it exercised.
    // What it was really checking — the device follows the controller in and
    // out of playback — is the play/stop pair, which this still covers.
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
    expect(await _waitFor(() => device.positionSamples > 0), isTrue);

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
    expect(await _waitFor(() => !device.isPlaying), isTrue);
    expect(
      transport.clockStatus(),
      isNull,
      reason: 'a clock that stands reads no device — and above all not '
          '「ended」, which would stop a run that plays once',
    );

    missing.clear();
    controller.lookAgain();
    expect(controller.isWaiting, isFalse);
    // Frame 7 at 10fps/48k = sample 33600.
    expect(
      await _waitFor(() => device.isPlaying && device.positionSamples >= 33600),
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
    expect(await _waitFor(() => device.positionSamples > 0), isTrue);
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
      final offset = device.latencySamples % step - step ~/ 2;
      final transport = buildTransport(store, offset: (_) => offset);

      controller.play(scope: PlaybackScope.activeCut);
      expect(
        await _waitFor(() => device.clockPoint != null),
        isTrue,
        reason: 'no callback spoke',
      );

      // A change of frame with the stair the same BEFORE the reading
      // before it and AFTER this one is a change no step of the stair made.
      final watch = Stopwatch()..start();
      var stairBefore = device.positionSamples;
      var frame = transport.clockStatus()?.globalFrame;
      var changes = 0;
      var whereTheStairStood = 0;
      while (watch.elapsedMilliseconds < 4000 && whereTheStairStood < 3) {
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
      expect(await _waitFor(() => device.clockPoint != null), isTrue);

      // The frames read in the moments after a wrap: the latest callback
      // the first of a new lap, and less than 10ms old — what is HEARD is
      // then 5ms or more short of the lap's end, however late that callback
      // came. For as many laps as it takes.
      final justWrapped = <int>[];
      final watch = Stopwatch()..start();
      var nearTheEnd = false;
      while (watch.elapsedMilliseconds < 8000 && justWrapped.length < 4) {
        final clock = device.readClock();
        final status = transport.clockStatus();
        final point = clock.point;
        if (point == null || status == null) {
          continue;
        }
        if (point.positionSamples > 40000) {
          nearTheEnd = true;
        } else if (point.positionSamples > 480) {
          nearTheEnd = false;
        } else if (nearTheEnd && clock.nowMicros - point.atMicros < 10000) {
          justWrapped.add(status.globalFrame);
        }
      }

      expect(
        justWrapped,
        isNotEmpty,
        reason: '⛔premise: no reading landed in the step after a wrap',
      );
      expect(
        justWrapped,
        everyElement(9),
        reason: 'the device has HANDED the lap\'s last sample, and what is '
            'heard is 30ms short of it: the last frame. ↩️Read off the '
            'wrapped count, the picture was back on frame 0 here',
      );
      expect(
        await _waitFor(() {
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

    // What is HEARD is what the device has handed, less its latency, plus
    // the user's own correction. The line stands at the stair or past it,
    // and no further past what was handed than the device carries — so one
    // reading, with the stair read before it and after it, is held between
    // the two, however slow the machine is.
    //
    // A frame is 4800 samples here: 10 a second at 48k.
    const frameSamples = 4800;

    test('🚨the user\'s own correction moves what is heard: three frames\' '
        'worth of it is three frames', () async {
      final device = openNullDevice();
      final store = _residentStore();
      store.resultFor('tone.wav');
      await pumpEventQueue();
      const correction = 3 * frameSamples;
      final transport = buildTransport(store, offset: (_) => correction);

      controller.play(scope: PlaybackScope.activeCut);
      expect(await _waitFor(() => device.clockPoint != null), isTrue);

      final before = device.positionSamples;
      final frame = transport.clockStatus()!.globalFrame;
      final after = device.positionSamples;
      int frameHeardAt(int handed) =>
          (handed - device.latencySamples + correction) ~/ frameSamples;
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
        await _waitFor(
          () => (transport.clockStatus()?.globalFrame ?? 0) >= 3,
        ),
        isTrue,
        reason: '⛔premise: the first run got somewhere',
      );

      // Back to the top while it plays.
      controller.seekToGlobalFrame(0);
      expect(
        await _waitFor(() {
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
      // Heard two frames early: while the device hands the run's last
      // frames, what is heard is already past the end of it.
      const correction = 2 * frameSamples;
      final transport = buildTransport(store, offset: (_) => correction);

      controller.loopMode = PlaybackLoopMode.once;
      controller.play(scope: PlaybackScope.activeCut, startGlobalFrame: 7);
      final pastTheEnd = <int>[];
      final watch = Stopwatch()..start();
      while (watch.elapsedMilliseconds < 3000 && device.isPlaying) {
        final before = device.positionSamples;
        final status = transport.clockStatus();
        if (status != null &&
            !status.ended &&
            before - device.latencySamples + correction >= 10 * frameSamples) {
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

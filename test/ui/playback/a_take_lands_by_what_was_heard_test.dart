import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart' show drawingBlocks;
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/native/qa_audio_device.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/audio_recorder.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';

import '../../helpers/canned_audio_recorder.dart';
import '../../helpers/device_paced.dart';
import '../../helpers/native_engine_path.dart';

/// 🚨★★★**A TAKE LANDS BY WHAT WAS HEARD** (take-head-trims-at-the-
/// playback-start, 10-15) — through the session: the record press, the
/// roll under it, the clock that hears the anchor, the take placed.
///
/// The bench never hears a run the session plays
/// (`audioOutputUnlessTesting`), so this hands the rig's transport a device
/// it opened on miniaudio's null backend (`PlaybackRig.debugTransportOutput`)
/// — a real callback on a real thread, no speaker. The microphone is made:
/// it says what it had taken in at any moment, five eighths of a second
/// ahead of the press, so the head it is placed by can only be the measured
/// one.
void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();
  final skip = libraryPath != null ? false : nativeEngineMissingSkipReason;

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

  /// A session over [project] whose runs ride the null device, at four
  /// frames a second — a frame is 12000 samples — recording through a
  /// microphone five eighths of a second ahead of the press.
  EditorSessionManager session(Project project) {
    final device = QaAudioDevice.instance!;
    expect(
      device.open(sampleRate: 48000, channels: 2, useNullBackend: true),
      greaterThan(0),
    );
    final manager = EditorSessionManager(
      initialProject: project,
      audioConformStore: AudioConformStore(
        resolveConformPath: (_) => null,
        runner: (request) async => const ConformResult(
          outcome: ConformOutcome.undecodable,
          error: 'test stub',
        ),
        log: (_) {},
      ),
    );
    addTearDown(manager.dispose);
    manager.playbackRig.debugTransportOutput = () => device;
    manager.projectSettings.setProjectFps(4);
    // ⚠️THE ANCHOR IS HEARD WHEN THE ROLL'S DEVICE STARTS, AND A RUNNER
    // STRETCHES THAT EITHER WAY (10-15, TestFlight #73). The head is what
    // the microphone held at the press and what it took in until the
    // anchor was heard — ms on a quiet machine, but a loaded one starts the
    // device later (🔬Windows under load: a take of 5), and a starved null
    // device draws its line ahead (the macOS runner, half a second ahead:
    // 7). A frame here is a quarter second, narrower than that spread, so
    // a take is five or six frames: an anchor heard anywhere from an eighth
    // of a second before the press to three eighths after it. The estimate,
    // and no head at all, leave eight.
    final microphone = _AheadMicrophone(
      _takeOfSeconds(2),
      ahead: 30000,
      clock: device,
    );
    manager.voiceRecording.debugVoiceRecorderFactory = () => microphone;
    return manager;
  }

  /// Records over the roll — its clock looking a vsync at a time, until well
  /// past the anchor being heard — and places the take.
  Future<void> takeOver(EditorSessionManager manager) async {
    expect(
      manager.voiceRecording.startVoiceRecording(),
      VoiceRecordStartResult.started,
    );
    final transport = manager.playbackRig.audioDeviceTransport;
    expect(
      transport.carryingPlayback,
      isTrue,
      reason: 'fixture: the roll rides the null device',
    );
    // Until the roll's device has played 0.6s of its own — well past the
    // anchor. ↩️0.6s of the wall, which a starved device can spend short of
    // it.
    final device = QaAudioDevice.instance!;
    final handed = Handed(device);
    expect(
      await waitOnTheDevice(device, () {
        transport.clockStatus();
        return handed.samples >= 28800;
      }),
      isTrue,
      reason: 'the roll\'s device stopped',
    );
    expect(await manager.voiceRecording.stopVoiceRecordingAndPlace(), isNull);
  }

  test('🚨the head is what the microphone had taken in when the anchor was '
      'HEARD — not the output latency the press estimated', () async {
    // ⚠️THE FIRST TAKE OF A RUN OF TESTS PAYS ITS FIRST-TIME WORK between
    // the press and the roll's first look, and its anchor is heard that much
    // later — measured, as it should be (🔬Windows: 153ms, where the take
    // after it took 23; on the Mac runners enough for a take of 3, release
    // 10-22). The take pinned is the second.
    late EditorSessionManager manager;
    for (var take = 0; take < 2; take += 1) {
      manager = session(createDefaultProject());
      manager.selectLayer(manager.activeTrack.seLayers.first.id);
      manager.selectFrameIndex(0);

      await takeOver(manager);
    }

    expect(
      drawingBlocks(manager.activeTrack.seLayers.first.timeline).single.length,
      inInclusiveRange(5, 6),
      reason: 'two seconds taken in, less what the microphone had in hand '
          'when the anchor was heard — five eighths of a second and the '
          'moments to the anchor: five or six frames. ↩️The estimate took '
          'off the output latency alone and left eight',
    );
  }, skip: skip);

  test('🚨a take begun under a cut played alone is measured on the run\'s own '
      'frames — b\'s frame 0 is track frame 18', () async {
    Cut cut(String id) => Cut(
      id: CutId(id),
      name: id,
      duration: 24,
      canvasSize: const CanvasSize(width: 64, height: 36),
      layers: const [],
    );
    final manager = session(
      Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'T',
            cuts: [cut('a'), cut('b')],
            seLayers: [
              Layer(
                id: const LayerId('se'),
                name: 'SE',
                kind: LayerKind.se,
                frames: const [],
              ),
            ],
          ),
        ],
      ),
    );
    // An O.L over 18..29: b's のりしろ is 18..23, so b played alone counts
    // from track frame 18 (a_cut_played_alone_sounds_from_its_material_start).
    manager.transitions.updateTransitionInstructions({
      18: const InstructionEvent(instructionId: 'ol', length: 12),
    });
    manager.selectCut(const CutId('b'));
    manager.selectLayer(const LayerId('se'));
    final playback = manager.playbackRig.playback;
    playback.play(scope: PlaybackScope.activeCut);
    playback.seekToGlobalFrame(3);

    await takeOver(manager);
    playback.stop();

    final take = drawingBlocks(
      manager.activeTrack.seLayers.single.timeline,
    ).single;
    expect(take.startIndex, 21, reason: 'fixture: b\'s frame 3');
    expect(
      take.length,
      inInclusiveRange(5, 6),
      reason: 'the anchor is b\'s frame 3 — on the run\'s frames, not the '
          'track\'s 21, which this run would not reach for four seconds and '
          'more: unmeasured, the estimate would have left eight',
    );
  }, skip: skip);
}

AudioRecording _takeOfSeconds(double seconds) {
  final samples = Float32List((seconds * 48000).round())
    ..fillRange(0, (seconds * 48000).round(), 0.25);
  return AudioRecording(
    samples: samples,
    channels: 1,
    sampleRate: 48000,
    droppedFrames: 0,
  );
}

/// A microphone that had taken in [ahead] samples when it was started, and
/// takes in 48 a millisecond on [clock]'s time from then.
class _AheadMicrophone extends CannedAudioRecorder {
  _AheadMicrophone(super.recording, {required this.ahead, required this.clock});

  final int ahead;
  final QaAudioDevice clock;
  int? _startedAt;

  @override
  int start({
    required int sampleRate,
    bool useNullBackend = false,
    int deviceIndex = -1,
  }) {
    _startedAt = clock.clockNowMicros;
    return super.start(
      sampleRate: sampleRate,
      useNullBackend: useNullBackend,
      deviceIndex: deviceIndex,
    );
  }

  @override
  int get sampleRate => recording.sampleRate;

  @override
  int? capturedAt(int atMicros) {
    final startedAt = _startedAt;
    if (startedAt == null || !isRecording) {
      return null;
    }
    return ahead +
        (atMicros - startedAt) * 48000 ~/ Duration.microsecondsPerSecond;
  }
}

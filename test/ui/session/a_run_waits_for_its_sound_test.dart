import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/playback_mode.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/native/qa_audio_device.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';

import '../../helpers/native_engine_path.dart';

/// playback-waits-for-its-sound (유저 2026-10-16, se-fallback-opens-the-
/// original-path-Q2: 「대체 재생을 안 쓰고, 소리가 준비될 때까지 기다린다」),
/// through the session: the run's clock asks for its sound beside its
/// picture (`PlaybackWait`), and the rig's transport answers.
///
/// The bench never hears what a session plays (`audioDeviceUnlessTesting`),
/// so the rig's transport gets a device opened once on miniaudio's null
/// backend (`PlaybackRig.debugTransportOutput`).
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

  /// The default project with a sound from its first frame, on its first SE
  /// row.
  Project withSound() {
    final project = createDefaultProject();
    final track = project.tracks.single;
    final [first, ...rest] = track.seLayers;
    return project.copyWith(
      tracks: [
        track.copyWith(
          seLayers: [
            first.copyWith(
              frames: [
                Frame(
                  id: const FrameId('tone'),
                  duration: 1,
                  strokes: const [],
                ),
              ],
              timeline: {
                0: const TimelineExposure.drawing(FrameId('tone'), length: 4),
              },
              audioClips: [
                AudioClip(
                  filePath: 'tone.wav',
                  frameId: const FrameId('tone'),
                ),
              ],
            ),
            ...rest,
          ],
        ),
      ],
    );
  }

  test('🚨a run whose sound is on its way stands where it was put — skipping '
      'frames too — and goes on with it once it lands; ↩️it played on the '
      'platform players, on the wall clock', () async {
    final device = QaAudioDevice.instance!;
    expect(device.open(useNullBackend: true), greaterThan(0));
    device.close();
    final conform = Completer<ConformResult>();
    final session = EditorSessionManager(
      initialProject: withSound(),
      audioConformStore: AudioConformStore(
        resolveConformPath: (_) => null,
        runner: (request) => conform.future,
        log: (_) {},
      ),
    );
    addTearDown(session.dispose);
    final rig = session.playbackRig
      ..debugTransportOutput = (() => device)
      // Its picture never holds it: what holds it is its sound alone.
      ..setPlaybackMode(PlaybackMode.skipFrames);
    final playback = rig.playback;

    playback.play(scope: PlaybackScope.activeCut);
    addTearDown(playback.stop);
    expect(
      rig.audioDeviceTransport.soundIsComing,
      isTrue,
      reason: 'fixture: its conform is under way',
    );
    expect(playback.isWaiting, isTrue);

    conform.complete(
      ConformResult(
        outcome: ConformOutcome.built,
        samples: Float32List(48000),
        channels: 1,
        sampleRate: 48000,
        frames: 48000,
      ),
    );
    await pumpEventQueue();
    expect(playback.isWaiting, isFalse);
    expect(rig.audioDeviceTransport.carryingPlayback, isTrue);
  }, skip: skip);
}

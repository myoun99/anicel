import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/native/qa_audio_device.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';

import '../../helpers/native_engine_path.dart';

/// play-press-first-frame-stall-Q1 (유저 10-15: 「프로젝트를 열면 미리 연다(UI
/// 스레드 밖에서)」 — 「소리가 있는 프로젝트가 열리면 백그라운드에서 장치를
/// 엽니다」), through the session: the project's sound warmed, its output
/// opened ahead — and the cues that ring that output.
///
/// The bench never hears what a session plays (`audioOutputUnlessTesting`),
/// so this hands the rig's transport a device it has opened once on
/// miniaudio's null backend (`PlaybackRig.debugTransportOutput`) — and every
/// open after that is on the null backend too.
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

  /// The default project with a sound on its first SE row.
  Project withSound() {
    final project = createDefaultProject();
    final track = project.tracks.single;
    final [first, ...rest] = track.seLayers;
    return project.copyWith(
      tracks: [
        track.copyWith(
          seLayers: [
            first.copyWith(
              audioClips: [
                AudioClip(filePath: 'tone.wav', frameId: const FrameId('tone')),
              ],
            ),
            ...rest,
          ],
        ),
      ],
    );
  }

  /// A session over [project] whose output is the bench's [device] — closed,
  /// and on the null backend from here on. Disposed at the test's end, unless
  /// the test disposes it.
  ({EditorSessionManager session, QaAudioDevice device}) sessionOver(
    Project project, {
    bool disposedAtTheEnd = true,
  }) {
    final device = QaAudioDevice.instance!;
    expect(device.open(useNullBackend: true), greaterThan(0));
    device.close();
    final session = EditorSessionManager(
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
    if (disposedAtTheEnd) {
      addTearDown(session.dispose);
    }
    session.playbackRig.debugTransportOutput = () => device;
    return (session: session, device: device);
  }

  /// [session]'s sound warmed as an open warms it, and the output's open
  /// under way let finish.
  Future<void> warmed(EditorSessionManager session) async {
    session.projectDoor.warmAudioConforms();
    await pumpEventQueue();
  }

  test('🚨a project with sound opens its output ahead as its sound is '
      'warmed — before any run', () async {
    final (:session, :device) = sessionOver(withSound());

    session.projectDoor.warmAudioConforms();
    expect(device.isOpening, isTrue, reason: 'off the UI thread');
    await pumpEventQueue();

    expect(device.isOpen, isTrue);
  }, skip: skip);

  test('a project with no sound opens nothing ahead', () async {
    final (:session, :device) = sessionOver(createDefaultProject());

    session.projectDoor.warmAudioConforms();

    expect(device.isOpening, isFalse);
    await pumpEventQueue();
    expect(device.isOpen, isFalse);
  }, skip: skip);

  group('the cues ring the output a run plays on', () {
    test('🚨the test tone rings on the output opened ahead — ↩️it asked '
        'whether the output was open, so from a first play on it never rang',
        () async {
      final (:session, :device) = sessionOver(withSound());
      await warmed(session);
      expect(device.isOpen, isTrue, reason: 'fixture');

      expect(session.voiceRecording.playOutputTestTone(), isTrue);
    }, skip: skip);

    test('the test tone refuses while a run holds the output', () async {
      final (:session, device: _) = sessionOver(withSound());
      await warmed(session);
      session.playbackRig.playback.play(scope: PlaybackScope.activeCut);
      addTearDown(session.playbackRig.playback.stop);

      expect(session.voiceRecording.playOutputTestTone(), isFalse);
    }, skip: skip);

    test('the test tone refuses while the output is being opened ahead — it '
        'would open it here as well, and wait out the worker', () async {
      final (:session, device: _) = sessionOver(withSound());
      session.projectDoor.warmAudioConforms();

      expect(session.voiceRecording.playOutputTestTone(), isFalse);
      await pumpEventQueue();
    }, skip: skip);

    test('🚨the test tone refuses while anything sounds on the output — a '
        'viewer\'s sound, which the tone\'s schedule would cut', () async {
      final (:session, :device) = sessionOver(withSound());
      await warmed(session);
      expect(device.play(startSample: 0), isTrue, reason: 'fixture');

      expect(session.voiceRecording.playOutputTestTone(), isFalse);
      device.stop();
      expect(session.voiceRecording.playOutputTestTone(), isTrue);
    }, skip: skip);

    test('the test tone refuses an output open for another setting than the '
        'chosen one — it rings the CHOSEN output', () async {
      final (:session, device: _) = sessionOver(withSound());
      await warmed(session);
      session.appSettings.setAudioSyncSettings(
        session.appSettings.audioSyncSettings.value.copyWith(
          outputDeviceName: 'another',
        ),
      );

      expect(session.voiceRecording.playOutputTestTone(), isFalse);
    }, skip: skip);

    // A tone lasts half a second and lets go at 700 ms.
    const pastTheTone = Duration(milliseconds: 900);

    test('🚨a cue lets the output go as it ends, and it stays open where the '
        'project keeps it', () async {
      final (:session, :device) = sessionOver(withSound());
      await warmed(session);
      expect(session.voiceRecording.playOutputTestTone(), isTrue);

      await Future<void>.delayed(pastTheTone);
      expect(device.isOpen, isTrue, reason: 'the transport keeps it');
    }, skip: skip);

    test('a cue that opened the output closes it as it ends, where nothing '
        'else keeps it', () async {
      final (:session, :device) = sessionOver(createDefaultProject());
      expect(session.voiceRecording.playOutputTestTone(), isTrue);
      expect(device.isOpen, isTrue, reason: 'the tone opened it');

      await Future<void>.delayed(pastTheTone);
      expect(device.isOpen, isFalse, reason: 'nobody keeps it');
    }, skip: skip);

    test('🚨a cue ending under a run leaves the run\'s sound alone — never '
        'yank ITS device', () async {
      final (:session, :device) = sessionOver(createDefaultProject());
      expect(session.voiceRecording.playOutputTestTone(), isTrue);
      // A run that holds the output and sounds on it — its transport stood
      // aside here, so that nothing but the cue touches the device.
      session.playbackRig.debugTransportOutput = () => null;
      final playback = session.playbackRig.playback
        ..play(scope: PlaybackScope.activeCut);
      addTearDown(playback.stop);
      device.keep(playback);
      addTearDown(() => device.letGo(playback));
      expect(device.play(startSample: 0), isTrue, reason: 'fixture');

      await Future<void>.delayed(pastTheTone);
      expect(device.isPlaying, isTrue);
    }, skip: skip);

    test('a session going lets its cue go — the output the cue opened '
        'closes', () async {
      final (:session, :device) = sessionOver(
        createDefaultProject(),
        disposedAtTheEnd: false,
      );
      expect(session.voiceRecording.playOutputTestTone(), isTrue);

      session.dispose();
      expect(device.isOpen, isFalse);
    }, skip: skip);
  });
}

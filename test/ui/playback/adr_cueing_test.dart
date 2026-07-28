import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/audio_recorder.dart';
import 'package:anicel/src/ui/playback/audio_sync_settings.dart';
import 'package:anicel/src/ui/playback/recording_streamer_overlay.dart';

/// ADR cueing (REC1-E): the 3-beep countdown into a punch, the streamer
/// window, and the stopped-⏺ count-in that delays the roll but not the
/// microphone.
void main() {
  EditorSessionManager session() => EditorSessionManager(
    initialProject: createDefaultProject(),
    audioConformStore: AudioConformStore(
      resolveConformPath: (_) => null,
      runner: (request) async => const ConformResult(
        outcome: ConformOutcome.undecodable,
        error: 'test stub',
      ),
      log: (_) {},
    ),
  );

  AudioRecording takeOfSeconds(double seconds) {
    final samples = Float32List((seconds * 48000).round());
    for (var index = 0; index < samples.length; index += 1) {
      samples[index] = 0.25;
    }
    return AudioRecording(
      samples: samples,
      channels: 1,
      sampleRate: 48000,
      droppedFrames: 0,
    );
  }

  test('REC1-E: the cueing settings round-trip and clamp', () {
    const settings = AudioSyncSettings(
      countInSeconds: 3,
      cueBeeps: false,
      streamerEnabled: false,
    );
    expect(AudioSyncSettings.fromJson(settings.toJson()), settings);
    expect(
      AudioSyncSettings.fromJson({'countInSeconds': 99}).countInSeconds,
      AudioSyncSettings.maxCountInSeconds,
    );
    expect(AudioSyncSettings.defaults.cueBeeps, isTrue);
    expect(AudioSyncSettings.defaults.streamerEnabled, isTrue);
    expect(AudioSyncSettings.defaults.countInSeconds, 0);
  });

  test('REC1-E: a punch ahead of the roll builds three beeps counting '
      'down INTO it, and the streamer window covers the approach', () {
    final manager = session();
    manager.setProjectFps(4); // 1 s = 4 frames: three beeps fit a run-up.
    final laneId = manager.activeTrack.seLayers.first.id;
    manager.selectLayer(laneId);
    manager.selectFrameIndex(0);
    manager.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: laneId,
      startIndex: 13,
      endIndexExclusive: 16,
    );
    manager.debugVoiceRecorderFactory = () => _FakeRecorder(
      // The take must outlast the 13-frame run-up (3.25 s at 4 fps): the
      // punch head-trim eats that much before anything lands.
      takeOfSeconds(4.0),
    );
    expect(manager.startVoiceRecording(), VoiceRecordStartResult.started);

    final beeps = manager.voiceRecordCueClips;
    expect(beeps, hasLength(3));
    expect(beeps.map((clip) => clip.startFrame), [1, 5, 9],
        reason: 'punch at 13, one second (4 frames) apart, ending 1 s '
            'before it — the imaginary fourth beep IS the punch');
    expect(beeps.first.filePath, endsWith('cue-beep.wav'));
    final window = manager.voiceRecordStreamerWindow;
    expect(window, isNotNull);
    expect(window!.startFrame, 1);
    expect(window.punchFrame, 13);

    final message = manager.stopVoiceRecordingAndPlace();
    expect(message, isNull);
    expect(manager.voiceRecordCueClips, isEmpty);
    expect(manager.voiceRecordStreamerWindow, isNull);
    manager.dispose();
  });

  test('REC1-E: the toggles silence the beeps and hide the streamer', () {
    final manager = session();
    manager.setProjectFps(4);
    manager.setAudioSyncSettings(
      manager.audioSyncSettings.value.copyWith(
        cueBeeps: false,
        streamerEnabled: false,
      ),
    );
    final laneId = manager.activeTrack.seLayers.first.id;
    manager.selectLayer(laneId);
    manager.selectFrameIndex(0);
    manager.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: laneId,
      startIndex: 13,
      endIndexExclusive: 16,
    );
    manager.debugVoiceRecorderFactory = () => _FakeRecorder(
      takeOfSeconds(1.0),
    );
    expect(manager.startVoiceRecording(), VoiceRecordStartResult.started);
    expect(manager.voiceRecordCueClips, isEmpty);
    expect(manager.voiceRecordStreamerWindow, isNull);
    manager.stopVoiceRecordingAndPlace();
    manager.dispose();
  });

  testWidgets('REC1-E: the count-in delays the ROLL, not the microphone — '
      'and rides the head trim', (tester) async {
    final manager = session();
    addTearDown(manager.dispose);
    manager.setAudioSyncSettings(
      manager.audioSyncSettings.value.copyWith(countInSeconds: 2),
    );
    final laneId = manager.activeTrack.seLayers.first.id;
    manager.selectLayer(laneId);
    manager.debugVoiceRecorderFactory = () => _FakeRecorder(
      takeOfSeconds(2.5), // 2 s of count-in ride the head trim.
    );
    expect(manager.startVoiceRecording(), VoiceRecordStartResult.started);
    expect(manager.playback.isActive, isFalse,
        reason: 'the transport waits out the count-in');
    await tester.pump(const Duration(milliseconds: 2100));
    expect(manager.playback.isPlaying, isTrue,
        reason: 'the count-in elapsed: the roll begins');

    expect(manager.stopVoiceRecordingAndPlace(), isNull);
    final lane = manager.activeTrack.seLayers.first;
    // 2.5 s captured - 2 s count-in = 0.5 s of take (12 frames @ 24).
    expect(lane.audioClips, hasLength(1));
    await tester.pumpAndSettle();
  });

  testWidgets('REC1-E: the streamer sweeps only inside the approach',
      (tester) async {
    final manager = session();
    addTearDown(manager.dispose);
    manager.setProjectFps(4);
    final laneId = manager.activeTrack.seLayers.first.id;
    manager.selectLayer(laneId);
    manager.selectFrameIndex(0);
    manager.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: laneId,
      startIndex: 13,
      endIndexExclusive: 16,
    );
    manager.debugVoiceRecorderFactory = () => _FakeRecorder(
      takeOfSeconds(1.0),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 180,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Color(0xFF101010)),
              RecordingStreamerOverlay(session: manager),
            ],
          ),
        ),
      ),
    );
    expect(manager.startVoiceRecording(), VoiceRecordStartResult.started);
    manager.playback.seekToGlobalFrame(5);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('recording-streamer')),
      findsOneWidget,
      reason: 'frame 5 sits inside the 1..13 approach',
    );
    manager.playback.seekToGlobalFrame(14);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('recording-streamer')),
      findsNothing,
      reason: 'past the punch the scribe is gone',
    );
    manager.stopVoiceRecordingAndPlace();
    await tester.pumpAndSettle();
  });
}

/// A microphone stand-in: start always succeeds at the take's rate and
/// stop hands the prepared take back once.
class _FakeRecorder extends AudioRecorder {
  _FakeRecorder(this.recording);

  final AudioRecording recording;
  bool _started = false;

  @override
  bool get isRecording => _started;

  @override
  int start({
    required int sampleRate,
    bool useNullBackend = false,
    int deviceIndex = -1,
  }) {
    _started = true;
    return recording.sampleRate;
  }

  @override
  AudioRecording? stop() {
    if (!_started) {
      return null;
    }
    _started = false;
    return recording;
  }
}

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/audio_recorder.dart';
import 'package:anicel/src/models/audio_sync_settings.dart';
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

  test('REC1-E: the cueing settings round-trip and clamp', () async {
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

  test('🚨REC1-E: NO punch means no cues — a plain record must not count '
      'anybody down into nothing', () async {
    final manager = session();
    manager.setProjectFps(4);
    final laneId = manager.activeTrack.seLayers.first.id;
    manager.selectLayer(laneId);
    manager.selectFrameIndex(0);
    // No range selection at all: the take simply anchors at the roll.
    manager.voiceRecording.debugVoiceRecorderFactory = () => _FakeRecorder(takeOfSeconds(1));
    expect(manager.voiceRecording.startVoiceRecording(), VoiceRecordStartResult.started);

    expect(manager.voiceRecording.voiceRecordCueClips, isEmpty);
    expect(manager.voiceRecording.voiceRecordStreamerWindow, isNull);
    manager.dispose();
  });

  test('🚨REC1-E: a punch the roll is ALREADY PAST is not a punch — the '
      'window is behind, so there is nothing to count into', () async {
    final manager = session();
    manager.setProjectFps(4);
    final laneId = manager.activeTrack.seLayers.first.id;
    manager.selectLayer(laneId);
    // The playhead sits after the range's far edge.
    manager.selectFrameIndex(20);
    manager.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: laneId,
      startIndex: 2,
      endIndexExclusive: 6,
    );
    manager.voiceRecording.debugVoiceRecorderFactory = () => _FakeRecorder(takeOfSeconds(1));
    expect(manager.voiceRecording.startVoiceRecording(), VoiceRecordStartResult.started);

    expect(
      manager.voiceRecording.voiceRecordCueClips,
      isEmpty,
      reason: 'a window entirely behind the roll is not a punch window',
    );
    expect(manager.voiceRecording.voiceRecordStreamerWindow, isNull);
    // 🚨And the take still LANDS: a punch end behind the anchor would
    // trim the capture to nothing, so the sound would simply not appear.
    expect(await manager.voiceRecording.stopVoiceRecordingAndPlace(), isNull);
    expect(manager.activeTrack.seLayers.first.audioClips, hasLength(1));
    manager.dispose();
  });

  test('🚨REC1-E: only the beeps that fall AFTER the roll are kept — a '
      'one-second run-up counts down once, not three times', () async {
    final manager = session();
    manager.setProjectFps(4); // 1 s = 4 frames
    final laneId = manager.activeTrack.seLayers.first.id;
    manager.selectLayer(laneId);
    manager.selectFrameIndex(0);
    // The punch is 4 frames (one second) ahead: only the 1-second beep
    // lands after the roll; the 2- and 3-second ones are before it.
    manager.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: laneId,
      startIndex: 4,
      endIndexExclusive: 8,
    );
    manager.voiceRecording.debugVoiceRecorderFactory = () => _FakeRecorder(takeOfSeconds(4));
    expect(manager.voiceRecording.startVoiceRecording(), VoiceRecordStartResult.started);

    expect(
      manager.voiceRecording.voiceRecordCueClips,
      hasLength(1),
      reason: 'a beep before the roll is a beep nobody hears',
    );
    // 🚨And the streamer covers the RUN-UP, not a fixed three seconds:
    // the wipe has to start where the roll did, not before it.
    final window = manager.voiceRecording.voiceRecordStreamerWindow;
    expect(window, isNotNull);
    expect(window!.punchFrame - window.startFrame, 4);
    manager.dispose();
  });

  test('REC1-E: a punch ahead of the roll builds three beeps counting '
      'down INTO it, and the streamer window covers the approach', () async {
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
    manager.voiceRecording.debugVoiceRecorderFactory = () => _FakeRecorder(
      // The take must outlast the 13-frame run-up (3.25 s at 4 fps): the
      // punch head-trim eats that much before anything lands.
      takeOfSeconds(4.0),
    );
    expect(manager.voiceRecording.startVoiceRecording(), VoiceRecordStartResult.started);

    final beeps = manager.voiceRecording.voiceRecordCueClips;
    expect(beeps, hasLength(3));
    expect(
      beeps.map((clip) => clip.startFrame),
      [1, 5, 9],
      reason:
          'punch at 13, one second (4 frames) apart, ending 1 s '
          'before it — the imaginary fourth beep IS the punch',
    );
    expect(beeps.first.filePath, endsWith('cue-beep.wav'));
    final window = manager.voiceRecording.voiceRecordStreamerWindow;
    expect(window, isNotNull);
    expect(window!.startFrame, 1);
    expect(window.punchFrame, 13);

    final message = await manager.voiceRecording.stopVoiceRecordingAndPlace();
    expect(message, isNull);
    expect(manager.voiceRecording.voiceRecordCueClips, isEmpty);
    expect(manager.voiceRecording.voiceRecordStreamerWindow, isNull);
    manager.dispose();
  });

  test('REC1-E: the toggles silence the beeps and hide the streamer', () async {
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
    manager.voiceRecording.debugVoiceRecorderFactory = () => _FakeRecorder(takeOfSeconds(1.0));
    expect(manager.voiceRecording.startVoiceRecording(), VoiceRecordStartResult.started);
    expect(manager.voiceRecording.voiceRecordCueClips, isEmpty);
    expect(manager.voiceRecording.voiceRecordStreamerWindow, isNull);
    await manager.voiceRecording.stopVoiceRecordingAndPlace();
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
    manager.voiceRecording.debugVoiceRecorderFactory = () => _FakeRecorder(
      takeOfSeconds(2.5), // 2 s of count-in ride the head trim.
    );
    expect(manager.voiceRecording.startVoiceRecording(), VoiceRecordStartResult.started);
    expect(
      manager.playbackRig.playback.isActive,
      isFalse,
      reason: 'the transport waits out the count-in',
    );
    await tester.pump(const Duration(milliseconds: 2100));
    expect(
      manager.playbackRig.playback.isPlaying,
      isTrue,
      reason: 'the count-in elapsed: the roll begins',
    );

    expect(await manager.voiceRecording.stopVoiceRecordingAndPlace(), isNull);
    final lane = manager.activeTrack.seLayers.first;
    // 2.5 s captured - 2 s count-in = 0.5 s of take (12 frames @ 24).
    expect(lane.audioClips, hasLength(1));
    await tester.pumpAndSettle();
  });

  testWidgets('REC1-E: the streamer sweeps only inside the approach', (
    tester,
  ) async {
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
    manager.voiceRecording.debugVoiceRecorderFactory = () => _FakeRecorder(takeOfSeconds(1.0));

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
    expect(manager.voiceRecording.startVoiceRecording(), VoiceRecordStartResult.started);
    manager.playbackRig.playback.seekToGlobalFrame(5);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('recording-streamer')),
      findsOneWidget,
      reason: 'frame 5 sits inside the 1..13 approach',
    );
    manager.playbackRig.playback.seekToGlobalFrame(14);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('recording-streamer')),
      findsNothing,
      reason: 'past the punch the scribe is gone',
    );
    await manager.voiceRecording.stopVoiceRecordingAndPlace();
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

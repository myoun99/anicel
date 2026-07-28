import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show drawingBlocks;
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/audio_recorder.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

/// The live take preview (REC1-C): while a take rolls, the armed lane
/// shows the planner's would-be landing — real block, real waveform lane,
/// recomputed at frame boundaries and NEVER through a session notify.
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

  AudioRecording take() {
    final samples = Float32List(24000);
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

  test('REC1-C: the preview lane lands the in-flight take and grows at '
      'frame boundaries; stop retires it for the real landing', () {
    final manager = session();
    final laneId = manager.activeTrack.seLayers.first.id;
    manager.selectLayer(laneId);
    manager.debugVoiceRecorderFactory = () => _FakeRecorder(take());

    expect(manager.startVoiceRecording(), VoiceRecordStartResult.started);
    // The roll starts at frame 0: the frame being spoken into counts.
    final first = manager.voiceRecordPreviewLane.value;
    expect(first, isNotNull);
    expect(first!.id, laneId);
    var block = drawingBlocks(first.timeline).single;
    expect(block.startIndex, 0);
    expect(block.length, 1);

    manager.playback.seekToGlobalFrame(3);
    final grown = manager.voiceRecordPreviewLane.value!;
    block = drawingBlocks(grown.timeline).single;
    expect(block.length, 4);
    // The display clones serve the preview instance for the armed lane.
    expect(
      manager.trackSeDisplayLayers.first.audioClips.single.filePath,
      EditorSessionManager.voiceRecordPreviewPath,
    );

    expect(manager.stopVoiceRecordingAndPlace(), isNull);
    expect(manager.voiceRecordPreviewLane.value, isNull);
    expect(
      manager.audioPeaksForDisplay(
        EditorSessionManager.voiceRecordPreviewPath,
      ),
      isNull,
    );
    // The committed lane carries the REAL take now, not the sentinel.
    final landed = manager.activeTrack.seLayers.first;
    expect(landed.audioClips.single.filePath, endsWith('.wav'));
    manager.dispose();
  });

  test('REC1-C: recorder chunks fold into the live envelope the sentinel '
      'path resolves to', () {
    final manager = session();
    final laneId = manager.activeTrack.seLayers.first.id;
    manager.selectLayer(laneId);
    manager.debugVoiceRecorderFactory = () => _FakeRecorder(take());
    expect(manager.startVoiceRecording(), VoiceRecordStartResult.started);

    // 48 kHz at 40 buckets/s = 1200 samples per bucket: two full buckets.
    final chunk = Float32List(2400);
    for (var index = 0; index < chunk.length; index += 1) {
      chunk[index] = index < 1200 ? 0.5 : -0.75;
    }
    manager.debugIngestVoiceRecordChunk(chunk, 1);
    manager.playback.seekToGlobalFrame(1); // A boundary publishes peaks.

    final peaks = manager.audioPeaksForDisplay(
      EditorSessionManager.voiceRecordPreviewPath,
    );
    expect(peaks, isNotNull);
    expect(peaks!.bucketsPerSecond, 40);
    expect(peaks.peaks, hasLength(2));
    expect(peaks.peaks[0], closeTo(0.5, 1e-6));
    expect(peaks.peaks[1], closeTo(0.75, 1e-6));

    manager.stopVoiceRecordingAndPlace();
    manager.dispose();
  });

  testWidgets('REC1-C: the timeline shows the growing take WITHOUT a '
      'session notify — the preview channel alone rebuilds the row',
      (tester) async {
    final manager = session();
    addTearDown(manager.dispose);
    final lane = manager.activeTrack.seLayers.first;
    manager.selectLayer(lane.id);
    manager.debugVoiceRecorderFactory = () => _FakeRecorder(take());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: manager,
            builder: (context, _) => TimelineTabHost(
              session: manager,
              orientation: TimelineOrientation.horizontal,
              onOrientationChanged: (_) {},
              pixelsPerFrame: 48,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(manager.startVoiceRecording(), VoiceRecordStartResult.started);
    await tester.pump();

    // The take's carrier block mounts its own SE drop target — proof the
    // REAL row pipeline (not an overlay) is drawing the preview.
    final dropKey = ValueKey<String>(
      'timeline-se-asset-drop-${lane.id.value}-0',
    );
    expect(find.byKey(dropKey), findsOneWidget);

    manager.stopVoiceRecordingAndPlace();
    await tester.pumpAndSettle();
    // The real landing keeps the block (same spot, real file now).
    expect(find.byKey(dropKey), findsOneWidget);
  });

  testWidgets('REC1-C follow-up: the STORYBOARD strip shows the growing '
      'take WITHOUT a session notify — the preview channel rebuilds the '
      'panel', (tester) async {
    final manager = session();
    addTearDown(manager.dispose);
    final lane = manager.activeTrack.seLayers.first;
    manager.selectLayer(lane.id);
    manager.debugVoiceRecorderFactory = () => _FakeRecorder(take());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: manager,
            builder: (context, _) => StoryboardTabHost(
              session: manager,
              pixelsPerFrame: 4,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
              thumbnailFor: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The armed lane's strip row carries no paper span yet.
    final paperKey = ValueKey<String>('storyboard-se-paper-${lane.id}-0');
    expect(find.byKey(paperKey), findsNothing);

    expect(manager.startVoiceRecording(), VoiceRecordStartResult.started);
    await tester.pump();
    // The in-flight take paints through the REAL strip-row pipeline.
    expect(find.byKey(paperKey), findsOneWidget);

    manager.stopVoiceRecordingAndPlace();
    await tester.pumpAndSettle();
    // The real landing keeps the block (same spot, real file now).
    expect(find.byKey(paperKey), findsOneWidget);
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

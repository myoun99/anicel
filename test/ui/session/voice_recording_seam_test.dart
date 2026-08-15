import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/timeline_coverage.dart' show drawingBlocks;
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/audio_recorder.dart';

/// The seam the voice-recording section reaches the session through.
///
/// `EditorVoiceRecording` takes nineteen collaborators as closures, and
/// several of them share a type — two are `int Function()`. Handing the
/// constructor the wrong one of a matching pair compiles, so the compiler
/// cannot guard this; only a test that tells the two numbers apart can.
///
/// 🚩The reason no existing test did: they all build `createDefaultProject()`,
/// where the only cut starts at global frame 0, so the active cut's start and
/// the editing playhead are BOTH 0. Swapping them is invisible in that
/// fixture — verified, the swap passed all 22 voice tests. The second cut
/// below is not decoration; it is the entire point, and each test asserts the
/// two numbers differ before it asserts anything else.
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

  test('a stopped roll anchors on the EDITING playhead, which is not the '
      "active cut's start once a project has two cuts", () {
    final manager = session();
    addTearDown(manager.dispose);
    manager.createCut();

    final laneId = manager.activeTrack.seLayers.first.id;
    manager.selectLayer(laneId);
    manager.selectFrameIndex(3);

    final cutStart = manager.activeCutGlobalStartFrame;
    final playhead = manager.editingGlobalFrame;
    expect(
      cutStart,
      greaterThan(0),
      reason: 'fixture: a cut starting at 0 makes this test vacuous',
    );
    expect(
      playhead,
      isNot(cutStart),
      reason: 'fixture: the two numbers must differ or a swap is invisible',
    );

    manager.debugVoiceRecorderFactory = () => _FakeRecorder(takeOfSeconds(1.0));
    expect(manager.startVoiceRecording(), VoiceRecordStartResult.started);
    manager.stopVoiceRecordingAndPlace();

    final lane = manager.activeTrack.seLayers.first;
    expect(drawingBlocks(lane.timeline).single.startIndex, playhead);
  });

  test("a punch window maps through the active cut's start, which is not "
      'the editing playhead', () {
    final manager = session();
    addTearDown(manager.dispose);
    manager.createCut();

    final laneId = manager.activeTrack.seLayers.first.id;
    manager.selectLayer(laneId);
    // The roll starts BEFORE the window, so the anchor is the punch and not
    // the playhead — which is what puts the cut-start offset on trial.
    manager.selectFrameIndex(2);
    manager.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: laneId,
      startIndex: 6,
      endIndexExclusive: 10,
    );

    final cutStart = manager.activeCutGlobalStartFrame;
    expect(
      cutStart,
      greaterThan(0),
      reason: 'fixture: a cut starting at 0 makes this test vacuous',
    );
    expect(
      manager.editingGlobalFrame,
      isNot(cutStart),
      reason: 'fixture: the two numbers must differ or a swap is invisible',
    );

    manager.debugVoiceRecorderFactory = () => _FakeRecorder(takeOfSeconds(2.0));
    expect(manager.startVoiceRecording(), VoiceRecordStartResult.started);
    manager.stopVoiceRecordingAndPlace();

    final lane = manager.activeTrack.seLayers.first;
    expect(drawingBlocks(lane.timeline).single.startIndex, cutStart + 6);
  });
}

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

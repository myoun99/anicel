import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show drawingBlocks;
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/conform_wav_codec.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/audio_recorder.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';

/// The landing half of recording (AUDIO-PRO R5 → REC1-B rolling record):
/// a finished take becomes a WAV named `<lane>_T<n>`, a pool entry and a
/// tape-style landing on the ARMED track SE lane — pool + lane swap in
/// ONE undo. Driven with made recordings; the microphone half is the
/// real-DLL suite's job.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('qa-voice-rec-test');
  });

  tearDown(() => directory.delete(recursive: true));

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

  AudioRecording takeOfSeconds(
    double seconds, {
    int channels = 1,
    int sampleRate = 48000,
    int droppedFrames = 0,
  }) {
    final length = (seconds * sampleRate).round();
    final samples = Float32List(length * channels);
    for (var index = 0; index < samples.length; index += 1) {
      samples[index] = 0.25;
    }
    return AudioRecording(
      samples: samples,
      channels: channels,
      sampleRate: sampleRate,
      droppedFrames: droppedFrames,
    );
  }

  test('REC1-B: a take lands on the given lane — <lane>_T01 WAV, pool '
      'entry, block at the anchor, ONE undo strips it all', () async {
    final manager = session();
    await manager.saveProjectToFile('${directory.path}/scene.anicel');
    final lane = manager.activeTrack.seLayers.first;

    final placed = manager.placeVoiceRecording(
      takeOfSeconds(1.0),
      laneId: lane.id,
      anchorFrame: 0,
    );
    expect(placed, isTrue);

    final landed = manager.activeTrack.seLayers.first;
    final clip = landed.audioClips.single;
    expect(clip.filePath, contains('.assets/Media/'));
    expect(clip.filePath, endsWith('${lane.name}_T01.wav'));
    expect(File(clip.filePath).existsSync(), isTrue);
    expect(
      manager.mediaAssets.map((asset) => asset.path),
      contains(clip.filePath),
    );
    // 1 s @ 24 fps = a 24-frame block at the anchor carrying the clip.
    final block = drawingBlocks(landed.timeline).single;
    expect(block.startIndex, 0);
    expect(block.length, 24);
    expect(block.frameId, clip.frameId);
    // The WAV round-trips exactly as long as the recording.
    final decoded = decodeConformWav(File(clip.filePath).readAsBytesSync());
    expect(decoded.sampleRate, 48000);
    expect(decoded.length, 48000);

    // ONE undo: pool and lane both back to the clean slate.
    manager.undo();
    final reverted = manager.activeTrack.seLayers.first;
    expect(reverted.audioClips, isEmpty);
    expect(drawingBlocks(reverted.timeline), isEmpty);
    expect(manager.mediaAssets, isEmpty);
    manager.dispose();
  });

  test('REC1-B: recording along trims the monitoring latency off the head',
      () async {
    final manager = session();
    await manager.saveProjectToFile('${directory.path}/scene.anicel');
    final lane = manager.activeTrack.seLayers.first;

    final placed = manager.placeVoiceRecording(
      takeOfSeconds(1.0),
      laneId: lane.id,
      anchorFrame: 0,
      headTrimSamples: 12000, // 250 ms of monitoring delay
    );
    expect(placed, isTrue);
    final clip = manager.activeTrack.seLayers.first.audioClips.single;
    final decoded = decodeConformWav(File(clip.filePath).readAsBytesSync());
    expect(decoded.length, 48000 - 12000,
        reason: 'the performer spoke against delayed monitoring; the take '
            'shifts earlier by exactly that delay');
    manager.dispose();
  });

  test('REC1-B: a take shorter than the latency it rode on places nothing',
      () async {
    final manager = session();
    await manager.saveProjectToFile('${directory.path}/scene.anicel');
    expect(
      manager.placeVoiceRecording(
        takeOfSeconds(0.1),
        laneId: manager.activeTrack.seLayers.first.id,
        anchorFrame: 0,
        headTrimSamples: 48000,
      ),
      isFalse,
    );
    manager.dispose();
  });

  test('REC1-B: a second take over the first TRIMS it, tape-style — same '
      'lane, no new row, both files kept', () async {
    final manager = session();
    await manager.saveProjectToFile('${directory.path}/scene.anicel');
    final laneId = manager.activeTrack.seLayers.first.id;
    final rowsBefore = manager.activeTrack.seLayers.length;

    expect(
      manager.placeVoiceRecording(
        takeOfSeconds(1.0), // 24 frames
        laneId: laneId,
        anchorFrame: 0,
      ),
      isTrue,
    );
    expect(
      manager.placeVoiceRecording(
        takeOfSeconds(0.5), // 12 frames over the first take's tail
        laneId: laneId,
        anchorFrame: 12,
      ),
      isTrue,
    );

    expect(manager.activeTrack.seLayers.length, rowsBefore);
    final lane = manager.activeTrack.seLayers.first;
    final blocks = drawingBlocks(lane.timeline);
    expect(blocks, hasLength(2));
    expect(blocks[0].startIndex, 0);
    expect(blocks[0].length, 12, reason: 'the first take lost its tail');
    expect(blocks[1].startIndex, 12);
    expect(blocks[1].length, 12);
    // Take numbering advanced; the first WAV stays in the pool.
    expect(
      manager.mediaAssets.map((asset) => asset.path).join(' '),
      allOf(contains('_T01.wav'), contains('_T02.wav')),
    );
    manager.dispose();
  });

  test('REC1-B: the punch window clamps the take — block AND file', () async {
    final manager = session();
    await manager.saveProjectToFile('${directory.path}/scene.anicel');
    final laneId = manager.activeTrack.seLayers.first.id;

    expect(
      manager.placeVoiceRecording(
        takeOfSeconds(1.0), // would cover 24 frames
        laneId: laneId,
        anchorFrame: 0,
        punchEndFrame: 6,
      ),
      isTrue,
    );
    final lane = manager.activeTrack.seLayers.first;
    expect(drawingBlocks(lane.timeline).single.length, 6);
    final clip = lane.audioClips.single;
    final decoded = decodeConformWav(File(clip.filePath).readAsBytesSync());
    // 6 frames @ 24 fps @ 48 kHz = 12000 samples: capture past the
    // punch-out was context, not take.
    expect(decoded.length, 12000);
    manager.dispose();
  });

  test('REC1-B: an unsaved project still records — the WAV degrades to '
      'temp, like an import', () {
    final manager = session();
    final placed = manager.placeVoiceRecording(
      takeOfSeconds(0.5),
      laneId: manager.activeTrack.seLayers.first.id,
      anchorFrame: 0,
    );
    expect(placed, isTrue);
    final clip = manager.activeTrack.seLayers.first.audioClips.single;
    expect(File(clip.filePath).existsSync(), isTrue);
    expect(clip.filePath, isNot(contains('.assets/Media/')));
    manager.dispose();
  });

  test('REC1-B: a null lane refuses the take rather than landing it '
      'anywhere', () async {
    final manager = session();
    await manager.saveProjectToFile('${directory.path}/scene.anicel');
    expect(
      manager.placeVoiceRecording(
        takeOfSeconds(0.5),
        laneId: null,
        anchorFrame: 0,
      ),
      isFalse,
    );
    manager.dispose();
  });

  test('REC1-B: start refuses without an armed SE lane; an armed start '
      'ROLLS the transport, mutes the lane, and stop lands the take', () {
    final manager = session();
    // The default active row is a drawing layer: no armed destination.
    expect(
      manager.startVoiceRecording(),
      VoiceRecordStartResult.needsSeLane,
    );

    final laneId = manager.activeTrack.seLayers.first.id;
    manager.selectLayer(laneId);
    manager.debugVoiceRecorderFactory = () => _FakeRecorder(
      takeOfSeconds(0.5),
    );
    expect(manager.startVoiceRecording(), VoiceRecordStartResult.started);
    // Record = play + capture: the transport rolls the whole track.
    expect(manager.playback.isPlaying, isTrue);
    expect(manager.playback.scope, PlaybackScope.allCuts);
    // The armed lane yields to the microphone (DAW armed-track rule).
    expect(manager.recordingMutedLayerIds, {laneId});

    final message = manager.stopVoiceRecordingAndPlace();
    expect(message, isNull);
    expect(manager.playback.isActive, isFalse,
        reason: 'the roll this take started stops with it');
    expect(manager.recordingMutedLayerIds, isEmpty);
    final lane = manager.activeTrack.seLayers.first;
    expect(lane.audioClips, hasLength(1));
    expect(drawingBlocks(lane.timeline).single.length, 12);
    manager.dispose();
  });

  test('REC1-B: transport stop mid-take finishes the take through the '
      'notice channel', () {
    final manager = session();
    final laneId = manager.activeTrack.seLayers.first.id;
    manager.selectLayer(laneId);
    manager.debugVoiceRecorderFactory = () => _FakeRecorder(
      takeOfSeconds(0.5),
    );
    expect(manager.startVoiceRecording(), VoiceRecordStartResult.started);

    manager.playback.stop();
    expect(manager.isVoiceRecording.value, isFalse);
    expect(
      manager.activeTrack.seLayers.first.audioClips,
      hasLength(1),
      reason: 'the stop path places the take, not just abandons it',
    );
    manager.dispose();
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

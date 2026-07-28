import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/conform_wav_codec.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/audio_recorder.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_span_layout.dart';
import 'package:anicel/src/ui/timeline/timeline_se_row_visual.dart';

/// The capture chain wired through the session (REC1-D): baked gain in
/// the landed WAV, the clip flag on the AudioClip, the clip light, the
/// notice-gated toast, and the block marker overlays.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('qa-capture-chain');
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

  AudioRecording takeOf(double amplitude, {double seconds = 0.5}) {
    final samples = Float32List((seconds * 48000).round());
    for (var index = 0; index < samples.length; index += 1) {
      samples[index] = amplitude;
    }
    return AudioRecording(
      samples: samples,
      channels: 1,
      sampleRate: 48000,
      droppedFrames: 0,
    );
  }

  test('REC1-D: the landed WAV carries the baked gain', () async {
    final manager = session();
    await manager.saveProjectToFile('${directory.path}/scene.qap');
    final laneId = manager.activeTrack.seLayers.first.id;

    expect(
      manager.placeVoiceRecording(
        takeOf(0.25),
        laneId: laneId,
        anchorFrame: 0,
        gainDb: 6,
      ),
      isTrue,
    );
    final clip = manager.activeTrack.seLayers.first.audioClips.single;
    expect(clip.clipped, isFalse);
    final decoded = decodeConformWav(File(clip.filePath).readAsBytesSync());
    expect(decoded.samples[100], closeTo(0.4988, 0.002),
        reason: '+6 dB lands IN the file, not on playback');
    manager.dispose();
  });

  test('REC1-D: an over-hot take flags the clip on the landed AudioClip '
      'and the toast obeys the notice toggle', () async {
    final manager = session();
    await manager.saveProjectToFile('${directory.path}/scene.qap');
    final laneId = manager.activeTrack.seLayers.first.id;
    manager.selectLayer(laneId);

    // Notice OFF (default): the take clips silently — flag only.
    manager.debugVoiceRecorderFactory = () => _FakeRecorder(takeOf(0.6));
    expect(manager.startVoiceRecording(), VoiceRecordStartResult.started);
    // The armed snapshot reads settings at start: raise gain BEFORE.
    var message = manager.stopVoiceRecordingAndPlace();
    expect(message, isNull, reason: 'gain 0: nothing clipped');

    manager.setAudioSyncSettings(
      manager.audioSyncSettings.value.copyWith(micGainDb: 12),
    );
    manager.debugVoiceRecorderFactory = () => _FakeRecorder(takeOf(0.6));
    expect(manager.startVoiceRecording(), VoiceRecordStartResult.started);
    message = manager.stopVoiceRecordingAndPlace();
    expect(message, isNull,
        reason: 'clipped, but the notice toggle is off — quiet');
    final lane = manager.activeTrack.seLayers.first;
    expect(lane.audioClips.last.clipped, isTrue);

    // Notice ON: the same clipping take reports through the toast.
    manager.setAudioSyncSettings(
      manager.audioSyncSettings.value.copyWith(clippingNotice: true),
    );
    manager.debugVoiceRecorderFactory = () => _FakeRecorder(takeOf(0.6));
    expect(manager.startVoiceRecording(), VoiceRecordStartResult.started);
    message = manager.stopVoiceRecordingAndPlace();
    expect(message, manager.uiStrings.recordTakeClipped);
    manager.dispose();
  });

  test('REC1-D: the clip light latches from the live tap and re-arms per '
      'take', () {
    final manager = session();
    final laneId = manager.activeTrack.seLayers.first.id;
    manager.selectLayer(laneId);
    manager.setAudioSyncSettings(
      manager.audioSyncSettings.value.copyWith(micGainDb: 12),
    );
    manager.debugVoiceRecorderFactory = () => _FakeRecorder(takeOf(0.6));
    expect(manager.startVoiceRecording(), VoiceRecordStartResult.started);
    expect(manager.voiceRecordClipLit.value, isFalse);

    final chunk = Float32List(1200);
    for (var index = 0; index < chunk.length; index += 1) {
      chunk[index] = 0.6; // 0.6 * +12 dB ≈ 2.4: over the ceiling.
    }
    manager.debugIngestVoiceRecordChunk(chunk, 1);
    expect(manager.voiceRecordClipLit.value, isTrue);

    manager.stopVoiceRecordingAndPlace();
    expect(manager.voiceRecordClipLit.value, isFalse);
    manager.dispose();
  });

  testWidgets('REC1-D: clip markers mount only for clipped clips and '
      'carry the tooltip', (tester) async {
    final layer = Layer(
      id: const LayerId('se-marks'),
      name: 'S1',
      kind: LayerKind.se,
      frames: [
        Frame(id: const FrameId('f1'), duration: 1, strokes: const []),
        Frame(id: const FrameId('f2'), duration: 1, strokes: const []),
      ],
      timeline: const {
        0: TimelineExposure.drawing(FrameId('f1'), length: 4),
        6: TimelineExposure.drawing(FrameId('f2'), length: 4),
      },
      audioClips: const [
        AudioClip(filePath: 'a.wav', frameId: FrameId('f1'), clipped: true),
        AudioClip(filePath: 'b.wav', frameId: FrameId('f2')),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 600,
          height: 40,
          child: TimelineFixedFrameSpanLayer(
            geometry: const TimelineFrameGeometry(
              frameCellExtent: 20,
              frameStartIndex: 0,
              frameEndIndexExclusive: 24,
            ),
            crossAxisExtent: 28,
            axis: Axis.horizontal,
            children: timelineRowClipMarkerOverlays(
              layer: layer,
              frameStartIndex: 0,
              frameEndIndexExclusive: 24,
              crossAxisExtent: 28,
              axis: Axis.horizontal,
              tooltip: 'clipped take',
              color: const Color(0xFFE24B4A),
            ),
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-clip-marker-se-marks-b0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-clip-marker-se-marks-b6')),
      findsNothing,
      reason: 'the clean take shows no red corner',
    );
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, 'clipped take');
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

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/conform_wav_codec.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/audio_recorder.dart';
import 'package:anicel/src/ui/playback/audio_sync_settings.dart';

/// The RNNoise round, Dart half: the toggle's settings plumbing, the
/// 48 kHz capture request, the armed-time snapshot, and the suppression
/// step's place in the capture chain (trim → denoise → fold/gain). The
/// native pass itself is the real-DLL suite's job
/// (qa_audio_denoise_test.dart) — here a seam stands in.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('qa-denoise-test');
  });

  tearDown(() => directory.delete(recursive: true));

  EditorSessionManager session({int projectSampleRate = 48000}) =>
      EditorSessionManager(
        initialProject: createDefaultProject(),
        audioConformStore: AudioConformStore(
          resolveConformPath: (_) => null,
          projectSampleRate: projectSampleRate,
          runner: (request) async => const ConformResult(
            outcome: ConformOutcome.undecodable,
            error: 'test stub',
          ),
          log: (_) {},
        ),
      );

  AudioRecording takeOfSeconds(double seconds, {int sampleRate = 48000}) {
    final samples = Float32List((seconds * sampleRate).round());
    for (var index = 0; index < samples.length; index += 1) {
      samples[index] = 0.25;
    }
    return AudioRecording(
      samples: samples,
      channels: 1,
      sampleRate: sampleRate,
      droppedFrames: 0,
    );
  }

  test('denoiseVoice round-trips and defaults OFF (pristine capture is '
      'the safer default)', () {
    expect(AudioSyncSettings.defaults.denoiseVoice, isFalse);
    const settings = AudioSyncSettings(denoiseVoice: true);
    expect(AudioSyncSettings.fromJson(settings.toJson()), settings);
    expect(
      AudioSyncSettings.fromJson(const AudioSyncSettings().toJson())
          .denoiseVoice,
      isFalse,
    );
  });

  test('arming with suppression ON asks the device for 48 kHz; OFF asks '
      'for the project rate', () {
    final manager = session(projectSampleRate: 44100);
    final lane = manager.activeTrack.seLayers.first;
    manager.selectLayer(lane.id);

    final recorder = _RateProbeRecorder(takeOfSeconds(0.5));
    manager.debugVoiceRecorderFactory = () => recorder;

    expect(manager.startVoiceRecording(), VoiceRecordStartResult.started);
    expect(recorder.requestedSampleRate, 44100);
    manager.stopVoiceRecordingAndPlace();

    manager.setAudioSyncSettings(
      manager.audioSyncSettings.value.copyWith(denoiseVoice: true),
    );
    expect(manager.startVoiceRecording(), VoiceRecordStartResult.started);
    expect(
      recorder.requestedSampleRate,
      EditorSessionManager.voiceDenoiseCaptureRate,
    );
    manager.stopVoiceRecordingAndPlace();
    manager.dispose();
  });

  test('the suppression step runs between trim and fold/gain, and its '
      'output is what the file bakes', () async {
    final manager = session();
    await manager.saveProjectToFile('${directory.path}/scene.anicel');
    final lane = manager.activeTrack.seLayers.first;

    Float32List? seenSamples;
    var seenChannels = 0;
    var seenRate = 0;
    manager.debugVoiceDenoiser = (samples, channels, sampleRate) {
      seenSamples = samples;
      seenChannels = channels;
      seenRate = sampleRate;
      final out = Float32List(samples.length);
      for (var index = 0; index < out.length; index += 1) {
        out[index] = 0.5;
      }
      return out;
    };

    expect(
      manager.placeVoiceRecording(
        takeOfSeconds(1.0),
        laneId: lane.id,
        anchorFrame: 0,
        headTrimSamples: 12000,
        denoise: true,
      ),
      isTrue,
    );
    // The seam saw the TRIMMED raw capture...
    expect(seenSamples, isNotNull);
    expect(seenSamples!.length, 48000 - 12000);
    expect(seenSamples!.first, 0.25);
    expect(seenChannels, 1);
    expect(seenRate, 48000);
    // ...and the file carries the suppressed samples (0.5, not 0.25).
    final clip = manager.activeTrack.seLayers.first.audioClips.single;
    final decoded = decodeConformWav(File(clip.filePath).readAsBytesSync());
    expect(decoded.samples.first, closeTo(0.5, 1e-3));
    manager.dispose();
  });

  test('a DECLINED pass keeps the raw take, and denoise:false never '
      'calls the seam', () async {
    final manager = session();
    await manager.saveProjectToFile('${directory.path}/scene.anicel');
    final lane = manager.activeTrack.seLayers.first;

    var calls = 0;
    manager.debugVoiceDenoiser = (samples, channels, sampleRate) {
      calls += 1;
      return null; // The native engine's "declined" contract.
    };

    expect(
      manager.placeVoiceRecording(
        takeOfSeconds(0.5),
        laneId: lane.id,
        anchorFrame: 0,
        denoise: true,
      ),
      isTrue,
    );
    expect(calls, 1);
    var clip = manager.activeTrack.seLayers.first.audioClips.single;
    var decoded = decodeConformWav(File(clip.filePath).readAsBytesSync());
    expect(decoded.samples.first, closeTo(0.25, 1e-3));

    expect(
      manager.placeVoiceRecording(
        takeOfSeconds(0.5),
        laneId: lane.id,
        anchorFrame: 30,
      ),
      isTrue,
    );
    expect(calls, 1, reason: 'denoise:false must not touch the seam');
    manager.dispose();
  });

  test('a device that refuses 48 kHz records CLEAN — the armed snapshot '
      'drops suppression rather than run the model off-rate', () {
    final manager = session();
    manager.setAudioSyncSettings(
      manager.audioSyncSettings.value.copyWith(denoiseVoice: true),
    );
    final lane = manager.activeTrack.seLayers.first;
    manager.selectLayer(lane.id);

    var calls = 0;
    manager.debugVoiceDenoiser = (samples, channels, sampleRate) {
      calls += 1;
      return null;
    };
    manager.debugVoiceRecorderFactory = () => _RateProbeRecorder(
      takeOfSeconds(0.5, sampleRate: 44100),
      grantedRate: 44100,
    );

    expect(manager.startVoiceRecording(), VoiceRecordStartResult.started);
    manager.stopVoiceRecordingAndPlace();
    expect(calls, 0);
    manager.dispose();
  });
}

/// A microphone stand-in that remembers the REQUESTED rate and answers
/// with its own (a device refusing 48 kHz answers 44100).
class _RateProbeRecorder extends AudioRecorder {
  _RateProbeRecorder(this.recording, {this.grantedRate});

  final AudioRecording recording;
  final int? grantedRate;
  int? requestedSampleRate;
  bool _started = false;

  @override
  bool get isRecording => _started;

  @override
  int start({
    required int sampleRate,
    bool useNullBackend = false,
    int deviceIndex = -1,
  }) {
    requestedSampleRate = sampleRate;
    _started = true;
    return grantedRate ?? sampleRate;
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

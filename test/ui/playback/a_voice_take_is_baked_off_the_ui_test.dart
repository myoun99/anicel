import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/on_a_worker.dart';
import 'package:anicel/src/models/audio_sync_settings.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/native/qa_audio_filter.dart';
import 'package:anicel/src/ui/playback/voice_take_bake.dart';

/// 🚨A TAKE IS BAKED OFF THE THREAD THAT DRAWS (board
/// a-voice-take-is-denoised-on-the-ui-isolate): when recording stops, the
/// take's whole length runs through RNNoise, the capture chain and the
/// 16-bit write. On the thread that draws, the screen stood through it.
///
/// Every other test runs workers here ([debugWorkersRunHere]); this one
/// takes the road production takes, a real isolate, with the engine's own
/// denoiser on it.
void main() {
  tearDown(() => debugWorkersRunHere = true);

  test('🎯a take is baked on a worker — the thread that draws takes its '
      'turns meanwhile — into the file baked here', () async {
    var turned = false;
    void turnBeforeTheBake() => Timer.run(() => turned = true);

    turnBeforeTheBake();
    final here = await bakeVoiceTakeOnAWorker(_take());
    expect(
      turned,
      isFalse,
      reason: 'the probe cannot tell: a take baked here took no turn, '
          'and this one says it did',
    );
    await pumpEventQueue();

    debugWorkersRunHere = false;
    turned = false;
    turnBeforeTheBake();
    final worker = await bakeVoiceTakeOnAWorker(_take());

    expect(
      turned,
      isTrue,
      reason: 'the take held the thread that draws until it was baked',
    );
    expect(
      worker.wav,
      here.wav,
      reason: 'where the take is baked is a matter of turns, not of what '
          'it writes',
    );
    expect(worker.lengthFrames, here.lengthFrames);
    expect(worker.clipped, here.clipped);
  });
}

/// Two seconds of a noisy stereo take at the rate RNNoise runs at, cut by
/// a punch window of thirty frames, suppressed by the engine and raised
/// 6 dB — every step of the bake doing something.
VoiceTakeToBake _take() => (
  samples: _noise(2 * 48000 * 2),
  channels: 2,
  sampleRate: 48000,
  gainDb: 6,
  channelMode: VoiceInputChannelMode.device,
  denoiser: _suppressed,
  windowFrames: 30,
  rate: ProjectFrameRate.fps24,
);

Float32List _noise(int floats) {
  final random = math.Random(7);
  return Float32List.fromList([
    for (var index = 0; index < floats; index += 1)
      (random.nextDouble() * 2 - 1) * 0.3,
  ]);
}

Float32List? _suppressed(Float32List samples, int channels, int sampleRate) =>
    denoiseVoiceTake(
      samples: samples,
      channels: channels,
      sampleRate: sampleRate,
    );

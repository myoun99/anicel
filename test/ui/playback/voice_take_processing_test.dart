import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/playback/audio_sync_settings.dart';
import 'package:anicel/src/ui/playback/voice_take_processing.dart';

/// The capture chain's arithmetic (REC1-D): channel folds, baked gain,
/// and the clip flag — plus the settings round-trip that carries them.
void main() {
  Float32List stereo(List<double> leftRight) {
    return Float32List.fromList(leftRight);
  }

  test('REC1-D: +6 dB roughly doubles, no clip below the ceiling', () {
    final out = processVoiceTake(
      samples: Float32List.fromList([0.25, -0.25]),
      channels: 1,
      gainDb: 6,
      channelMode: VoiceInputChannelMode.device,
    );
    expect(out.channels, 1);
    expect(out.clipped, isFalse);
    expect(out.samples[0], closeTo(0.4988, 0.001));
    expect(out.samples[1], closeTo(-0.4988, 0.001));
  });

  test('REC1-D: gain past the ceiling clamps and flags the clip', () {
    final out = processVoiceTake(
      samples: Float32List.fromList([0.5]),
      channels: 1,
      gainDb: 12,
      channelMode: VoiceInputChannelMode.device,
    );
    expect(out.clipped, isTrue);
    expect(out.samples[0], 1.0);
  });

  test('REC1-D: an already-hot capture flags without any gain (analog '
      'overload shows the same way)', () {
    final samples = Float32List.fromList([0.9995]);
    final out = processVoiceTake(
      samples: samples,
      channels: 1,
      gainDb: 0,
      channelMode: VoiceInputChannelMode.device,
    );
    expect(out.clipped, isTrue);
    expect(identical(out.samples, samples), isTrue,
        reason: 'the identity path never copies');
  });

  test('REC1-D: mono mix averages the pair into one channel', () {
    final out = processVoiceTake(
      samples: stereo([0.4, 0.2, -0.4, -0.2]),
      channels: 2,
      gainDb: 0,
      channelMode: VoiceInputChannelMode.monoMix,
    );
    expect(out.channels, 1);
    expect(out.samples, hasLength(2));
    expect(out.samples[0], closeTo(0.3, 1e-6));
    expect(out.samples[1], closeTo(-0.3, 1e-6));
  });

  test('REC1-D: left/right keep a single side', () {
    final left = processVoiceTake(
      samples: stereo([0.4, 0.1]),
      channels: 2,
      gainDb: 0,
      channelMode: VoiceInputChannelMode.left,
    );
    expect(left.channels, 1);
    expect(left.samples[0], closeTo(0.4, 1e-6));
    final right = processVoiceTake(
      samples: stereo([0.4, 0.1]),
      channels: 2,
      gainDb: 0,
      channelMode: VoiceInputChannelMode.right,
    );
    expect(right.samples[0], closeTo(0.1, 1e-6));
  });

  test('REC1-D: a mono capture ignores the fold modes (nothing to fold)',
      () {
    final out = processVoiceTake(
      samples: Float32List.fromList([0.3]),
      channels: 1,
      gainDb: 0,
      channelMode: VoiceInputChannelMode.right,
    );
    expect(out.channels, 1);
    expect(out.samples[0], closeTo(0.3, 1e-6));
  });

  test(
    'REC1-D: the no-op chain clamps too — a hot float capture cannot '
    'reach the 16-bit bake out of range',
    () {
      // device fold + 0 dB is the DEFAULT path and the only one that used
      // to hand its input straight back. A float capture can overshoot
      // +/-1.0, and the take is baked to 16-bit next.
      final out = processVoiceTake(
        samples: Float32List.fromList([1.4, -1.4, 0.5, -0.5]),
        channels: 1,
        gainDb: 0,
        channelMode: VoiceInputChannelMode.device,
      );
      expect(out.samples[0], 1.0);
      expect(out.samples[1], -1.0);
      expect(out.clipped, isTrue);
      // In-range samples pass through untouched — the clamp only fires
      // where it must.
      expect(out.samples[2], closeTo(0.5, 1e-6));
      expect(out.samples[3], closeTo(-0.5, 1e-6));

      final quiet = processVoiceTake(
        samples: Float32List.fromList([0.5, -0.5]),
        channels: 1,
        gainDb: 0,
        channelMode: VoiceInputChannelMode.device,
      );
      expect(quiet.clipped, isFalse);
      expect(quiet.samples, [0.5, -0.5]);
    },
  );

  test('REC1-D: the capture-chain settings round-trip and clamp', () {
    const settings = AudioSyncSettings(
      micGainDb: 12,
      inputChannelMode: VoiceInputChannelMode.monoMix,
      clippingNotice: true,
    );
    final restored = AudioSyncSettings.fromJson(settings.toJson());
    expect(restored, settings);
    expect(
      AudioSyncSettings.fromJson({'micGainDb': 99}).micGainDb,
      AudioSyncSettings.maxMicGainDb,
    );
    // Defaults stay quiet: nothing serialized, nothing surprising back.
    expect(AudioSyncSettings.defaults.toJson().containsKey('micGainDb'),
        isFalse);
    expect(
      AudioSyncSettings.fromJson(const {}).inputChannelMode,
      VoiceInputChannelMode.device,
    );
    expect(AudioSyncSettings.fromJson(const {}).clippingNotice, isFalse);
  });
}

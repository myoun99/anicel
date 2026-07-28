import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/audio/audio_mixer_reference.dart';

/// AUDIO-PRO R1: the mix-control primitives — pan law, fade curves, the
/// volume envelope — pinned on the Dart reference (the parity suite then
/// carries the numbers to the C verbatim).
void main() {
  group('equalPowerPanGains (compensated: center is UNITY)', () {
    test('center passes through at unity — the fallback path cannot pan, '
        'so center-panned sound must not change level between paths', () {
      final center = equalPowerPanGains(0);
      expect(center.left, closeTo(1.0, 1e-12));
      expect(center.right, closeTo(1.0, 1e-12));

      final hardLeft = equalPowerPanGains(-1);
      expect(hardLeft.left, closeTo(math.sqrt2, 1e-12));
      expect(hardLeft.right, closeTo(0, 1e-12));

      final hardRight = equalPowerPanGains(1);
      expect(hardRight.left, closeTo(0, 1e-12));
      expect(hardRight.right, closeTo(math.sqrt2, 1e-12));
    });

    test('the sum of squares stays constant across the whole sweep — that '
        'is what equal-power MEANS', () {
      for (var pan = -1.0; pan <= 1.0; pan += 0.125) {
        final gains = equalPowerPanGains(pan);
        expect(
          gains.left * gains.left + gains.right * gains.right,
          closeTo(2.0, 1e-12),
          reason: 'pan $pan',
        );
      }
    });
  });

  test('audioFadeRamp: linear passes through, equal-power takes sqrt '
      '(IEEE-exact — the parity-safe curve)', () {
    expect(audioFadeRamp(0.25, 0), 0.25);
    expect(audioFadeRamp(0.25, 1), 0.5);
    expect(audioFadeRamp(-0.5, 0), 0);
    expect(audioFadeRamp(-0.5, 1), 0);
  });

  test('audioEnvelopeAt: holds past the ends, interpolates between keys', () {
    const points = [
      AudioEnvelopePoint(sample: 100, gain: 1.0),
      AudioEnvelopePoint(sample: 200, gain: 0.0),
      AudioEnvelopePoint(sample: 300, gain: 0.5),
    ];
    expect(audioEnvelopeAt(points, -50), 1.0, reason: 'held before');
    expect(audioEnvelopeAt(points, 150), 0.5, reason: 'mid ramp');
    expect(audioEnvelopeAt(points, 250), 0.25, reason: 'second segment');
    expect(audioEnvelopeAt(points, 999), 0.5, reason: 'held after');
    expect(audioEnvelopeAt(const [], 10), 1.0, reason: 'empty = unity');
  });

  test('pan factors apply on a STEREO bus and leave other geometries '
      'untouched', () {
    final source = AudioMixSource(
      samples: Float32List.fromList([0.5, 0.5, 0.5, 0.5]),
      channels: 1,
    );
    final clip = AudioMixClip(
      sourceIndex: 0,
      startSample: 0,
      endSample: 4,
      panLeft: 1.0,
      panRight: 0.0, // hard left
    );

    final stereo = mixAudioReference(
      clips: [clip],
      sources: [source],
      startSample: 0,
      sampleCount: 4,
      outChannels: 2,
    );
    expect(stereo[0], 0.5, reason: 'left carries');
    expect(stereo[1], 0.0, reason: 'right silent — hard left');

    final mono = mixAudioReference(
      clips: [clip],
      sources: [source],
      startSample: 0,
      sampleCount: 4,
      outChannels: 1,
    );
    expect(mono[0], 0.5, reason: 'a mono bus ignores pan');
  });

  test('the envelope multiplies with gain and fades in the clip volume', () {
    final clip = AudioMixClip(
      sourceIndex: 0,
      startSample: 0,
      endSample: 100,
      gain: 2.0,
      envelope: const [
        AudioEnvelopePoint(sample: 0, gain: 1.0),
        AudioEnvelopePoint(sample: 100, gain: 0.0),
      ],
    );
    // At sample 50 the envelope reads 0.5; times gain 2.0 = 1.0.
    expect(audioClipVolumeAt(clip, 50), closeTo(1.0, 1e-12));
  });

  test('the SE layer model carries fader/pan and the clip carries curve/'
      'envelope through JSON', () {
    final layer = Layer(
      id: const LayerId('se'),
      name: 'S1',
      kind: LayerKind.se,
      frames: [
        Frame(id: const FrameId('f'), duration: 1, strokes: const []),
      ],
      timeline: {0: TimelineExposure.drawing(const FrameId('f'), length: 4)},
      audioClips: const [
        AudioClip(
          filePath: 'a.wav',
          frameId: FrameId('f'),
          fadeCurve: AudioFadeCurve.equalPower,
          volumeKeys: [
            AudioVolumeKey(frame: 0, gain: 1),
            AudioVolumeKey(frame: 4, gain: 0.5),
          ],
        ),
      ],
      audioGain: 0.8,
      audioPan: -0.5,
    );
    final reopened = Layer.fromJson(layer.toJson());
    expect(reopened.audioGain, 0.8);
    expect(reopened.audioPan, -0.5);
    final clip = reopened.audioClips.single;
    expect(clip.fadeCurve, AudioFadeCurve.equalPower);
    expect(clip.volumeKeys, const [
      AudioVolumeKey(frame: 0, gain: 1),
      AudioVolumeKey(frame: 4, gain: 0.5),
    ]);
    // Defaults stay OUT of the JSON — legacy files keep their bytes.
    final plain = Layer(
      id: const LayerId('p'),
      name: 'P',
      frames: const [],
    ).toJson();
    expect(plain.containsKey('audioGain'), isFalse);
    expect(plain.containsKey('audioPan'), isFalse);
  });
}

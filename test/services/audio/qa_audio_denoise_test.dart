import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_audio_denoiser.dart';

/// The RNNoise round, through the app's door to the engine's denoiser
/// ([_denoise]): the model must actually SUPPRESS through the
/// FFI surface, and the export must honor its own refusal contract (48 kHz
/// only, null = untouched).
///
/// No byte-parity here — there is no Dart reference for a neural model.
/// The exact floats are the engine crate's ledger rows (`audio_denoise/*`
/// in `test/fixtures/fingerprints.json`, held by its own tests); what is
/// pinned here is BEHAVIOR: non-speech noise loses most of its energy, and
/// the declined paths decline loudly. The engine always loads, so nothing
/// here skips (connection-round-checklist H).
void main() {
  Float32List noise(int frames, {double amplitude = 0.1, int seed = 7}) {
    final random = math.Random(seed);
    final out = Float32List(frames);
    for (var index = 0; index < frames; index += 1) {
      out[index] = (random.nextDouble() * 2 - 1) * amplitude;
    }
    return out;
  }

  double rms(Float32List samples, {int stride = 1, int offset = 0}) {
    var sum = 0.0;
    var count = 0;
    for (var index = offset; index < samples.length; index += stride) {
      sum += samples[index] * samples[index];
      count += 1;
    }
    return count == 0 ? 0 : math.sqrt(sum / count);
  }

  test('white noise at 48 kHz loses most of its energy', () {
    final input = noise(48000 * 2);
    final output = denoiseVoiceTake(
      samples: input,
      channels: 1,
      sampleRate: 48000,
    );
    expect(output, isNotNull);
    expect(output!.length, input.length);
    // Judge the SECOND half: the model adapts over its first frames.
    // The bar is deliberately loose (white noise is the model's HARDEST
    // stationary case — it spans every band): measured ≈0.53× here; the
    // pin catches "does nothing" and "garbage", not exact gain.
    final half = input.length ~/ 2;
    final inputRms = rms(Float32List.sublistView(input, half));
    final outputRms = rms(Float32List.sublistView(output, half));
    expect(
      outputRms,
      lessThan(inputRms * 0.7),
      reason:
          'steady non-speech noise should be attenuated by $_denoise '
          '(in $inputRms → out $outputRms)',
    );
  });

  test('stereo processes each channel independently — each equals the '
      'SAME data run alone as mono, bit for bit', () {
    const frames = 48000;
    final input = Float32List(frames * 2);
    final left = noise(frames, seed: 11);
    final right = noise(frames, seed: 12);
    for (var index = 0; index < frames; index += 1) {
      input[index * 2] = left[index];
      input[index * 2 + 1] = right[index];
    }
    final stereo = denoiseVoiceTake(
      samples: input,
      channels: 2,
      sampleRate: 48000,
    );
    final leftAlone = denoiseVoiceTake(
      samples: left,
      channels: 1,
      sampleRate: 48000,
    );
    final rightAlone = denoiseVoiceTake(
      samples: right,
      channels: 1,
      sampleRate: 48000,
    );
    expect(stereo, isNotNull);
    expect(leftAlone, isNotNull);
    expect(rightAlone, isNotNull);
    // One fresh DenoiseState per channel means the interleaved run and
    // the solo runs execute the exact same float sequence — any drift
    // here is a state leak between channels.
    for (var index = 0; index < frames; index += 1) {
      expect(stereo![index * 2], leftAlone![index], reason: 'L@$index');
      expect(stereo[index * 2 + 1], rightAlone![index], reason: 'R@$index');
    }
  });

  test('the refusal contract: wrong rate and empty input return null, '
      'input stays untouched', () {
    final input = noise(44100);
    final before = Float32List.fromList(input);
    expect(
      denoiseVoiceTake(samples: input, channels: 1, sampleRate: 44100),
      isNull,
    );
    expect(input, before, reason: 'a refusal must not half-process');
    expect(
      denoiseVoiceTake(
        samples: Float32List(0),
        channels: 1,
        sampleRate: 48000,
      ),
      isNull,
    );
  });
}

/// The denoiser these ask — named as a path, so a lane that changed only the
/// engine's denoiser runs this file (`affected_tests` picks a test by the
/// paths it writes out, 보드/인프라 2026-11-08 05:35).
const _denoise = 'packages/gpu_engine/rust/native/audio_denoise';

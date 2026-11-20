import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_audio_filter.dart';

/// A voice take's RNNoise round, through the app's door to the engine — a
/// sound row's noise removal at its whole amount ([_denoise], [_door]):
/// the model must actually SUPPRESS, the take must come out where it was
/// said at every rate, and the door must honor its refusal contract
/// (nothing to clean = null, the take untouched).
///
/// No byte-parity here — there is no Dart reference for a neural model.
/// The exact floats are the engine crate's ledger rows (`audio_denoise/*`
/// in `test/fixtures/fingerprints.json`, held by its own tests); what is
/// pinned here is BEHAVIOR: non-speech noise loses most of its energy, a
/// voice lines up with itself, and the declined paths decline loudly. The
/// engine always loads, so nothing here skips (connection-round-checklist
/// H).
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

  // 🎯A TAKE LANDS WHERE IT WAS SAID (board voice-take-denoise-lands-late):
  // RNNoise hands a frame back a frame late, and a take was placed that
  // late — 10 ms. Read on past the take and dropped at its front, a voice
  // lines up with itself where it went in, at RNNoise's rate and through
  // the conversions at another; the sample before is the high-pass RNNoise
  // hears through, a phase lead on the voice's lowest harmonics, not a
  // lateness (the engine's a_voice_comes_back_a_frame_late measures 479 of
  // RNNoise's 480).
  test('🎯a voice comes out where it went in — not a frame late, at every '
      'rate', () {
    final found = <int, int>{};
    for (final rate in [48000, 44100, 96000]) {
      final voice = _voice(rate);
      final cleaned = denoiseVoiceTake(
        samples: voice,
        channels: 1,
        sampleRate: rate,
      )!;
      final reach = rate ~/ 100;
      double along(int lag) {
        var sum = 0.0;
        for (var t = reach; t < voice.length - reach; t += 1) {
          sum += voice[t] * cleaned[t + lag];
        }
        return sum;
      }

      var best = (lag: 0, sum: double.negativeInfinity);
      for (var lag = -reach; lag <= reach; lag += 1) {
        final sum = along(lag);
        if (sum > best.sum) {
          best = (lag: lag, sum: sum);
        }
      }
      found[rate] = best.lag;
    }
    expect(found, {48000: -1, 44100: -1, 96000: -1}, reason: 'via $_door');
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

  // 🗣️audio-fx-second-effect-and-presets-Q2 = 1 (유저 2026-11-18 21:59):
  // at another rate the take is heard at RNNoise's own and brought back,
  // as a row's noise removal is.
  test('the refusal contract: empty input returns null; at another rate '
      'the take is cleaned, as a row is — the input untouched either way', () {
    final input = noise(44100);
    final before = Float32List.fromList(input);
    final cleaned = denoiseVoiceTake(
      samples: input,
      channels: 1,
      sampleRate: 44100,
    );
    expect(cleaned, hasLength(input.length));
    expect(cleaned, isNot(input), reason: 'LIVENESS: cleaned at 44.1 kHz');
    expect(input, before, reason: 'the take handed in is not written');
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

/// A second of a voice-like take at [rate]: harmonics over a pitch gliding
/// 110 → 260 Hz in syllables, with gaps of silence — the voice of the
/// engine's ledger takes, without its noise.
Float32List _voice(int rate) {
  final out = Float32List(rate);
  var phase = 0.0;
  for (var n = 0; n < rate; n += 1) {
    final t = n / rate;
    final pitch = 110 + 150 * (0.5 + 0.5 * math.sin(t * 0.7));
    phase += 2 * math.pi * pitch / rate;
    final syllable = (t * 3.1) % 1;
    if (syllable >= 0.8 && syllable < 0.9) {
      continue;
    }
    final envelope = math.max(0.0, math.sin(syllable * math.pi));
    var voiced = 0.0;
    for (var harmonic = 1; harmonic <= 12; harmonic += 1) {
      voiced += math.sin(phase * harmonic) / harmonic;
    }
    out[n] = 0.3 * envelope * voiced;
  }
  return out;
}

/// The denoiser and the door these ask — named as paths, so a lane that
/// changed only the engine's denoiser or its door runs this file
/// (`affected_tests` picks a test by the paths it writes out, 보드/인프라
/// 2026-11-08 05:35).
const _denoise = 'packages/gpu_engine/rust/native/audio_denoise';
const _door = 'packages/gpu_engine/rust/native/audio_mix/src/denoiser.rs';

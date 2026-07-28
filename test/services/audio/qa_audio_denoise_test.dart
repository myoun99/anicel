import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_audio_native.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';

import '../../helpers/native_engine_path.dart';

/// The RNNoise round, C half: the vendored model must actually SUPPRESS
/// through the FFI surface, and the wrapper must honor its own refusal
/// contract (48 kHz only, null = untouched).
///
/// No byte-parity here — there is no Dart reference for a neural model,
/// and pinning exact floats would pin the compiler's math, which the
/// -ffp-contract story says differs per target. What is pinned instead
/// is BEHAVIOR: non-speech noise loses most of its energy, and the
/// declined paths decline loudly.
void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();
  final available = libraryPath != null;
  final skip = available ? false : nativeEngineMissingSkipReason;

  setUp(() {
    QaAudioNative.debugResetForTests();
    debugQaEngineLibraryPathOverride = libraryPath;
    QaAudioNative.debugForceDartFallback = false;
  });

  tearDown(() {
    QaAudioNative.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaAudioNative.debugForceDartFallback = false;
  });

  QaAudioNative requireNative() {
    final native = QaAudioNative.instance;
    expect(
      native,
      isNotNull,
      reason:
          'the binary at $libraryPath loaded but the denoise entry point '
          'did not bind — an ABI mismatch, which is what this suite '
          'exists to catch',
    );
    return native!;
  }

  test('native engine required on CI builders', () {
    if (nativeEngineRequired) {
      expect(
        available,
        isTrue,
        reason:
            'QA_REQUIRE_NATIVE=1 but no engine binary was found — the '
            'build stopped producing one',
      );
    }
  });

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
    final native = requireNative();
    final input = noise(48000 * 2);
    final output = native.denoiseVoice(
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
          'steady non-speech noise should be attenuated '
          '(in $inputRms → out $outputRms)',
    );
  }, skip: skip);

  test('stereo processes each channel independently — each equals the '
      'SAME data run alone as mono, bit for bit', () {
    final native = requireNative();
    const frames = 48000;
    final input = Float32List(frames * 2);
    final left = noise(frames, seed: 11);
    final right = noise(frames, seed: 12);
    for (var index = 0; index < frames; index += 1) {
      input[index * 2] = left[index];
      input[index * 2 + 1] = right[index];
    }
    final stereo = native.denoiseVoice(
      samples: input,
      channels: 2,
      sampleRate: 48000,
    );
    final leftAlone = native.denoiseVoice(
      samples: left,
      channels: 1,
      sampleRate: 48000,
    );
    final rightAlone = native.denoiseVoice(
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
  }, skip: skip);

  test('the refusal contract: wrong rate and empty input return null, '
      'input stays untouched', () {
    final native = requireNative();
    final input = noise(44100);
    final before = Float32List.fromList(input);
    expect(
      native.denoiseVoice(samples: input, channels: 1, sampleRate: 44100),
      isNull,
    );
    expect(input, before, reason: 'a refusal must not half-process');
    expect(
      native.denoiseVoice(
        samples: Float32List(0),
        channels: 1,
        sampleRate: 48000,
      ),
      isNull,
    );
  }, skip: skip);
}

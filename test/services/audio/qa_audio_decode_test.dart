import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_audio_decoder.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/services/audio/conform_wav_codec.dart';

import '../../helpers/native_engine_path.dart';

/// The vendored dr_libs, exercised end to end.
///
/// The WAV cases form a closed loop: this project's own Dart encoder writes
/// the bytes, dr_wav reads them back, and the samples must match. That
/// checks both halves at once — if a dr_libs update changes behaviour, it
/// shows up here rather than in someone's project.
void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();
  final available = libraryPath != null;
  final skip = available ? false : nativeEngineMissingSkipReason;

  setUp(() {
    QaAudioDecoder.debugResetForTests();
    debugQaEngineLibraryPathOverride = libraryPath;
  });

  tearDown(() {
    QaAudioDecoder.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
  });

  QaAudioDecoder requireDecoder() {
    final decoder = QaAudioDecoder.instance;
    expect(
      decoder,
      isNotNull,
      reason:
          'the binary at $libraryPath loaded but the decoder entry points '
          'did not bind — qa_audio_decode.c may not be in the build',
    );
    return decoder!;
  }

  Float32List ramp(int count) {
    final data = Float32List(count);
    for (var index = 0; index < count; index += 1) {
      data[index] = (index / count) * 2.0 - 1.0;
    }
    return data;
  }

  group('WAV round trip through our own encoder', () {
    test('mono samples survive the loop', () {
      final decoder = requireDecoder();
      final samples = ramp(480);
      final decoded = decoder.decode(
        encodeConformWav(samples: samples, channels: 1, sampleRate: 48000),
      );

      expect(decoded, isNotNull);
      expect(decoded!.format, QaAudioFormat.wav);
      expect(decoded.channels, 1);
      expect(decoded.sampleRate, 48000);
      expect(decoded.length, 480);
      // Half an LSB: our encoder and dr_wav now agree on the 32768 scale,
      // so quantization is the ONLY error left. A looser bound here would
      // have hidden the convention mismatch this test originally caught.
      for (var index = 0; index < samples.length; index += 1) {
        expect(
          decoded.samples[index],
          closeTo(samples[index], 0.5 / 32768.0),
          reason: 'sample $index',
        );
      }
    });

    test('stereo interleaving is preserved, not swapped', () {
      final decoder = requireDecoder();
      // L ramps up, R ramps down — a swap or a stride bug is unmissable.
      final samples = Float32List(200);
      for (var index = 0; index < 100; index += 1) {
        samples[index * 2] = index / 100.0;
        samples[index * 2 + 1] = -(index / 100.0);
      }
      final decoded = decoder.decode(
        encodeConformWav(samples: samples, channels: 2, sampleRate: 44100),
      )!;

      expect(decoded.channels, 2);
      expect(decoded.sampleRate, 44100);
      expect(decoded.length, 100);
      for (var index = 0; index < 100; index += 1) {
        expect(decoded.samples[index * 2], closeTo(index / 100.0, 1e-4));
        expect(decoded.samples[index * 2 + 1], closeTo(-index / 100.0, 1e-4));
      }
    });

    test('a conform carrying our provenance chunk still decodes', () {
      // dr_wav must step over the custom `qacf` chunk the same way our own
      // reader steps over foreign ones.
      final decoder = requireDecoder();
      final decoded = decoder.decode(
        encodeConformWav(
          samples: ramp(64),
          channels: 1,
          sampleRate: 48000,
          fingerprint: const ConformSourceFingerprint(
            sourceLength: 4242,
            sourceCrc32: 0x1784ABCD,
          ),
        ),
      )!;
      expect(decoded.length, 64);
      expect(decoded.format, QaAudioFormat.wav);
    });

    test('sample rates pass through untouched — no hidden resampling', () {
      // Resampling to the project rate is a separate, visible step. If a
      // decode ever started doing it silently, this fails.
      final decoder = requireDecoder();
      for (final rate in const [8000, 22050, 44100, 48000, 96000]) {
        final decoded = decoder.decode(
          encodeConformWav(samples: ramp(96), channels: 1, sampleRate: rate),
        )!;
        expect(decoded.sampleRate, rate, reason: 'rate $rate');
        expect(decoded.length, 96);
      }
    });
  }, skip: skip);

  group('refusing what it cannot read', () {
    test('random bytes decode to null rather than noise', () {
      final decoder = requireDecoder();
      final junk = Uint8List(512);
      for (var index = 0; index < junk.length; index += 1) {
        junk[index] = (index * 37) & 0xFF;
      }
      expect(decoder.decode(junk), isNull);
    });

    test('empty input is null, not a crash', () {
      expect(requireDecoder().decode(Uint8List(0)), isNull);
    });

    test('a truncated WAV header does not take the process down', () {
      final decoder = requireDecoder();
      final good = encodeConformWav(
        samples: ramp(64),
        channels: 1,
        sampleRate: 48000,
      );
      // Every prefix: whatever dr_wav makes of it, it must return rather
      // than read past the buffer.
      for (final cut in const [4, 12, 20, 40, 44]) {
        expect(
          () => decoder.decode(good.sublist(0, cut)),
          returnsNormally,
          reason: 'prefix of $cut bytes',
        );
      }
    });
  }, skip: skip);
}

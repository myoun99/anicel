import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_audio_decoder.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/services/audio/wav16_header.dart';
import 'package:anicel/src/services/persistence/media_blob_codec.dart';

import '../../helpers/decode_audio_file.dart';
import '../../helpers/native_engine_path.dart';
import '../../helpers/temp_dir.dart';

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
      requireDecoder();
      final samples = ramp(480);
      final decoded = decodeAudioBytes(
        wav16(samples, channels: 1, rate: 48000),
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
      requireDecoder();
      // L ramps up, R ramps down — a swap or a stride bug is unmissable.
      final samples = Float32List(200);
      for (var index = 0; index < 100; index += 1) {
        samples[index * 2] = index / 100.0;
        samples[index * 2 + 1] = -(index / 100.0);
      }
      final decoded = decodeAudioBytes(
        wav16(samples, channels: 2, rate: 44100),
      )!;

      expect(decoded.channels, 2);
      expect(decoded.sampleRate, 44100);
      expect(decoded.length, 100);
      for (var index = 0; index < 100; index += 1) {
        expect(decoded.samples[index * 2], closeTo(index / 100.0, 1e-4));
        expect(decoded.samples[index * 2 + 1], closeTo(-index / 100.0, 1e-4));
      }
    });

    test('🚨a FRAMED wav — the shape a carried sound is kept in — decodes to '
        'the same samples as the plain one, fed to the decoder a block at a '
        'time', () {
      final decoder = requireDecoder();
      // Three blocks' worth, so the decoder's reads cross block boundaries.
      final wav = wav16(ramp(600000), channels: 1, rate: 48000);
      final directory = Directory.systemTemp.createTempSync('anicel-framed');
      addTearDown(() => deleteTempQuietly(directory));
      final written = writeMediaBlob(
        basePath: '${directory.path}/take.wav',
        length: wav.length,
        readInto: mediaBytesReader(wav),
      );
      expect(written.framed, isTrue, reason: 'fixture: PCM compresses');

      final framed = decoder.decodeSpan(
        written.path,
        length: File(written.path).lengthSync(),
        framed: true,
      );
      final plain = decodeAudioBytes(wav)!;

      expect(framed, isNotNull);
      expect(framed!.format, QaAudioFormat.wav);
      expect(framed.samples, orderedEquals(plain.samples));
    });

    test('sample rates pass through untouched — no hidden resampling', () {
      // Resampling to the project rate is a separate, visible step. If a
      // decode ever started doing it silently, this fails.
      requireDecoder();
      for (final rate in const [8000, 22050, 44100, 48000, 96000]) {
        final decoded = decodeAudioBytes(
          wav16(ramp(96), channels: 1, rate: rate),
        )!;
        expect(decoded.sampleRate, rate, reason: 'rate $rate');
        expect(decoded.length, 96);
      }
    });
  }, skip: skip);

  group('refusing what it cannot read', () {
    test('random bytes decode to null rather than noise', () {
      requireDecoder();
      final junk = Uint8List(512);
      for (var index = 0; index < junk.length; index += 1) {
        junk[index] = (index * 37) & 0xFF;
      }
      expect(decodeAudioBytes(junk), isNull);
    });

    test('empty input is null, not a crash', () {
      requireDecoder();
      expect(decodeAudioBytes(Uint8List(0)), isNull);
    });

    test('a truncated WAV header does not take the process down', () {
      requireDecoder();
      final good = wav16(ramp(64), channels: 1, rate: 48000);
      // Every prefix: whatever dr_wav makes of it, it must return rather
      // than read past the buffer.
      for (final cut in const [4, 12, 20, 40, 44]) {
        expect(
          () => decodeAudioBytes(good.sublist(0, cut)),
          returnsNormally,
          reason: 'prefix of $cut bytes',
        );
      }
    });
  }, skip: skip);
}

/// A real 16-bit PCM WAV — a FOREIGN format to this app now.
///
/// ⚠️This used to be `encodeConformWav`, which worked only while a conform
/// happened to be a WAV. It stopped being one on 2026-08-30, so the fixture
/// says what it means: build the thing the decoder is supposed to read.
Uint8List wav16(Float32List samples, {int channels = 1, int rate = 48000}) {
  final pcm = Uint8List(samples.length * 2);
  final view = ByteData.sublistView(pcm);
  for (var i = 0; i < samples.length; i += 1) {
    var v = samples[i];
    if (v > 1.0) v = 1.0;
    if (v < -1.0) v = -1.0;
    var s = (v * 32768.0).round();
    if (s > 32767) s = 32767;
    view.setInt16(i * 2, s, Endian.little);
  }
  return Uint8List.fromList([
    ...wav16HeaderBytes(
      dataBytes: pcm.length,
      sampleRate: rate,
      channels: channels,
    ),
    ...pcm,
  ]);
}

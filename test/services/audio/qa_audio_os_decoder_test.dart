import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_audio_decoder.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/audio_conform_runner.dart';
import 'package:anicel/src/services/audio/conform_wav_codec.dart';

import '../../helpers/native_engine_path.dart';

/// The OS decoder (AAC/m4a), driven for real against the platform codec
/// stack: Media Foundation here on Windows, AudioToolbox when this suite
/// runs on the macOS CI runner. The fixture is a generated 440 Hz sine at
/// -6 dB, 0.5 s, 44.1k stereo — so the assertions are physics, not
/// hand-waving: the rate and channel count must come back exactly, the
/// length within AAC's priming/padding slack, the mid-file peak near the
/// encoded amplitude.
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

  Uint8List fixtureBytes() =>
      File('test/fixtures/tone.m4a').readAsBytesSync();

  test('m4a decodes through the OS codec stack where one exists — and is '
      'honestly undecodable where none does', () {
    final decoder = QaAudioDecoder.instance;
    expect(decoder, isNotNull, reason: 'the binary did not bind');
    final decoded = decoder!.decode(fixtureBytes());

    if (Platform.isLinux) {
      // Not a shipping platform and no OS codec to lean on: undecodable,
      // which is exactly what routes the file to the ffmpeg fallback.
      expect(decoded, isNull);
      return;
    }

    expect(decoded, isNotNull,
        reason: 'the OS decoder should have carried this m4a');
    expect(decoded!.format, QaAudioFormat.os);
    expect(decoded.sampleRate, 44100);
    expect(decoded.channels, 2);
    // 0.5 s at 44.1k = 22050 frames; AAC priming/padding moves the edges
    // by up to ~2 frames of 1024 samples either way.
    expect(decoded.length, inInclusiveRange(19000, 25000));

    // The signal itself: a -6 dB sine's peak, measured away from the
    // fade-prone edges. A wrong channel de-interleave or a wrong scale
    // convention fails this immediately.
    var peak = 0.0;
    final start = (decoded.length ~/ 4) * decoded.channels;
    final end = (3 * decoded.length ~/ 4) * decoded.channels;
    for (var index = start; index < end; index += 1) {
      peak = math.max(peak, decoded.samples[index].abs());
    }
    expect(peak, inInclusiveRange(0.35, 0.65),
        reason: 'expected roughly the encoded -6 dB amplitude, got $peak');
  }, skip: skip);

  test('an m4a conforms END-TO-END: OS decode, resample to the project '
      'rate, peaks — the whole import chain in one call', () {
    final result = runConformHere(
      ConformRequest(
        sourcePath: 'test/fixtures/tone.m4a',
        conformPath: null, // memory-only, like an unsaved project
        libraryPathOverride: libraryPath,
      ),
    );

    if (Platform.isLinux) {
      expect(result.outcome, ConformOutcome.undecodable,
          reason: 'no OS codec stack on the Linux runner — the definitive '
              'answer that routes m4a to the fallback there');
      return;
    }

    expect(result.outcome, ConformOutcome.built);
    expect(result.sampleRate, 48000,
        reason: '44.1k source must land at the project rate');
    expect(result.channels, 2);
    // 0.5 s at 48k = 24000 frames, with AAC priming/padding slack.
    expect(result.frames, inInclusiveRange(21000, 27500));
    expect(result.samples, isNotNull);
    expect(result.peaks!.peaks, isNotEmpty);
    // The resampler must carry the -6 dB sine through unchanged.
    var peak = 0.0;
    for (final value in result.peaks!.peaks) {
      peak = math.max(peak, value);
    }
    expect(peak, inInclusiveRange(0.35, 0.65));
  }, skip: skip);

  test('ogg decodes through the BUNDLED stb_vorbis on every platform — '
      'the last format that used to lean on ffmpeg', () {
    final decoder = QaAudioDecoder.instance;
    expect(decoder, isNotNull);
    final decoded = decoder!.decode(
      File('test/fixtures/tone.ogg').readAsBytesSync(),
    );
    expect(decoded, isNotNull,
        reason: 'stb_vorbis is vendored — no platform stack involved');
    expect(decoded!.format, QaAudioFormat.vorbis);
    expect(decoded.sampleRate, 44100);
    expect(decoded.channels, 2);
    expect(decoded.length, inInclusiveRange(20000, 24500));
    var peak = 0.0;
    final start = (decoded.length ~/ 4) * decoded.channels;
    final end = (3 * decoded.length ~/ 4) * decoded.channels;
    for (var index = start; index < end; index += 1) {
      peak = math.max(peak, decoded.samples[index].abs());
    }
    expect(peak, inInclusiveRange(0.35, 0.65));
  }, skip: skip);

  test('dr_libs formats never route to the OS path (wav stays byte-pinned '
      'on its single decoder)', () {
    final decoder = QaAudioDecoder.instance;
    expect(decoder, isNotNull);
    // A tiny valid WAV through the conform codec's encoder.
    final wav = encodeConformWav(
      samples: Float32List.fromList(List.filled(4410 * 2, 0.25)),
      channels: 2,
      sampleRate: 44100,
      fingerprint: const ConformSourceFingerprint(
        sourceLength: 1,
        sourceCrc32: 1,
      ),
    );
    final decoded = decoder!.decode(wav);
    expect(decoded, isNotNull);
    expect(decoded!.format, QaAudioFormat.wav,
        reason: 'WAV must stay on dr_wav on every platform');
  }, skip: skip);
}

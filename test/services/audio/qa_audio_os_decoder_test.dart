import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_audio_decoder.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/audio_conform_runner.dart';
import 'package:anicel/src/services/audio/wav16_header.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';

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

  Uint8List fixtureBytes() => File('test/fixtures/tone.m4a').readAsBytesSync();

  test('m4a decodes through the OS codec stack where one exists — and is '
      'honestly undecodable where none does', () {
    final decoder = QaAudioDecoder.instance;
    expect(decoder, isNotNull, reason: 'the binary did not bind');
    final decoded = decoder!.decode(fixtureBytes());

    if (Platform.isLinux) {
      // Not a shipping platform and no OS codec to lean on: undecodable,
      // which is the definitive answer that leaves the waveform blank.
      expect(decoded, isNull);
      return;
    }

    expect(
      decoded,
      isNotNull,
      reason: 'the OS decoder should have carried this m4a',
    );
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
    expect(
      peak,
      inInclusiveRange(0.35, 0.65),
      reason: 'expected roughly the encoded -6 dB amplitude, got $peak',
    );
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
      expect(
        result.outcome,
        ConformOutcome.undecodable,
        reason:
            'no OS codec stack on the Linux runner — the definitive '
            'answer that routes m4a to the fallback there',
      );
      return;
    }

    expect(result.outcome, ConformOutcome.built);
    expect(
      result.sampleRate,
      48000,
      reason: '44.1k source must land at the project rate',
    );
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
    expect(
      decoded,
      isNotNull,
      reason: 'stb_vorbis is vendored — no platform stack involved',
    );
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
    // A tiny valid WAV — a FOREIGN format now, built by the writer the
    // export uses.
    final wav = wav16(
      Float32List.fromList(List.filled(4410 * 2, 0.25)),
      channels: 2,
      rate: 44100,
    );
    final decoded = decoder!.decode(wav);
    expect(decoded, isNotNull);
    expect(
      decoded!.format,
      QaAudioFormat.wav,
      reason: 'WAV must stay on dr_wav on every platform',
    );
  }, skip: skip);

  // -------------------------------------------------------------------------
  // A container that is a RANGE of a file.
  //
  // 🚨★★★What the C test next door CANNOT reach: it builds a WAV, so it never
  // gets past dr_wav and the OS stack's own range plumbing — an
  // `IMFByteStream` on Windows, resource-loader callbacks on Apple — is never
  // asked anything. These fixtures are real encoded files, so they are.

  /// Writes [bytes] into a file with junk on both sides, and says where they
  /// landed. The junk is the point: an offset that is ignored reads it.
  ({String path, int offset, int length}) buried(
    Uint8List bytes,
    String name,
  ) {
    const prefix = 4096;
    final directory = Directory.systemTemp.createTempSync('qa_range');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}$name';
    final sink = File(path).openSync(mode: FileMode.write);
    sink.writeFromSync(
      Uint8List.fromList(List.generate(prefix, (i) => (i * 13 + 7) & 0xFF)),
    );
    sink.writeFromSync(bytes);
    sink.writeFromSync(
      Uint8List.fromList(List.generate(512, (i) => (i * 29 + 3) & 0xFF)),
    );
    sink.closeSync();
    return (path: path, offset: prefix, length: bytes.length);
  }

  test('an ogg inside a bigger file decodes from its RANGE, identically to '
      'the same bytes in memory', () {
    final decoder = QaAudioDecoder.instance;
    expect(decoder, isNotNull);
    final bytes = File('test/fixtures/tone.ogg').readAsBytesSync();
    final at = buried(bytes, 'carried.ogg');

    final ranged = decoder!.decodeRange(
      at.path,
      offset: at.offset,
      length: at.length,
    );
    expect(
      ranged,
      isNotNull,
      reason: 'stb_vorbis reads a FILE section — no platform stack involved, '
          'so this must hold on every runner including Linux',
    );
    expect(ranged!.format, QaAudioFormat.vorbis);

    // Byte-for-byte the same answer as the memory door. ⛔If these ever
    // differ, the range path has quietly become a second decoder.
    final assembled = decoder.decode(bytes)!;
    expect(ranged.channels, assembled.channels);
    expect(ranged.sampleRate, assembled.sampleRate);
    expect(ranged.samples.length, assembled.samples.length);
    expect(ranged.samples, orderedEquals(assembled.samples));
  }, skip: skip);

  test('an m4a inside a bigger file decodes from its RANGE through the OS '
      'codec stack', () {
    final decoder = QaAudioDecoder.instance;
    expect(decoder, isNotNull);
    final at = buried(fixtureBytes(), 'carried.m4a');
    final ranged = decoder!.decodeRange(
      at.path,
      offset: at.offset,
      length: at.length,
    );

    if (Platform.isLinux) {
      // No OS codec to lean on — undecodable, the same honest answer the
      // memory door gives there.
      expect(ranged, isNull);
      return;
    }

    expect(
      ranged,
      isNotNull,
      reason: 'the OS decoder must reach a container that starts at an '
          'offset — this is the whole carried-media case',
    );
    expect(ranged!.format, QaAudioFormat.os);
    expect(ranged.sampleRate, 44100);
    expect(ranged.channels, 2);
    expect(ranged.length, inInclusiveRange(19000, 25000));
    var peak = 0.0;
    final start = (ranged.length ~/ 4) * ranged.channels;
    final end = (3 * ranged.length ~/ 4) * ranged.channels;
    for (var index = start; index < end; index += 1) {
      peak = math.max(peak, ranged.samples[index].abs());
    }
    expect(
      peak,
      inInclusiveRange(0.35, 0.65),
      reason: 'the range must carry the same sine, not the junk around it',
    );
  }, skip: skip);

  test('a sound INSIDE the project file conforms end to end — source range, '
      'streamed fingerprint, decode in place', () {
    // 🚨★★★THE WHOLE CHAIN THIS ROUND EXISTS FOR, in one call: the source
    // says where its bytes are, the identity check streams them, and the
    // decoder is pointed at the span rather than handed a copy. A movie's
    // soundtrack is this same case with a bigger container.
    final at = buried(fixtureBytes(), 'carried.m4a');
    final result = runConformHere(
      ConformRequest(
        sourcePath: 'carried.m4a',
        conformPath: null, // memory-only, like an unsaved project
        source: MediaArchiveBytes(
          archivePath: at.path,
          dataOffset: at.offset,
          length: at.length,
        ),
        libraryPathOverride: libraryPath,
      ),
    );

    if (Platform.isLinux) {
      expect(result.outcome, ConformOutcome.undecodable);
      return;
    }

    expect(
      result.outcome,
      ConformOutcome.built,
      reason: 'reason: ${result.error}',
    );
    expect(result.sampleRate, 48000, reason: 'lands at the project rate');
    expect(result.channels, 2);
    expect(result.frames, inInclusiveRange(21000, 27500));
    var peak = 0.0;
    for (final value in result.peaks!.peaks) {
      peak = math.max(peak, value);
    }
    expect(
      peak,
      inInclusiveRange(0.35, 0.65),
      reason: 'the -6 dB sine has to survive being read out of the middle '
          'of a bigger file',
    );
  }, skip: skip);

  test('a range that is not inside the file is refused, and the junk around '
      'a container is not audio', () {
    final decoder = QaAudioDecoder.instance;
    expect(decoder, isNotNull);
    final bytes = File('test/fixtures/tone.ogg').readAsBytesSync();
    final at = buried(bytes, 'carried.ogg');

    expect(
      decoder!.decodeRange(at.path, offset: at.offset, length: at.length + 4096),
      isNull,
      reason: 'a container cut short decodes as corrupt — refusing says what '
          'actually went wrong',
    );
    // ⛔The assertion the offset dies on: reading from the start of the file
    // finds the junk, not the ogg.
    expect(
      decoder.decodeRange(at.path, offset: 0, length: at.length),
      isNull,
    );
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

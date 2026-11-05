import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_audio_decoder.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/services/audio/wav16_header.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';

import '../../helpers/decode_audio_file.dart';
import '../../helpers/native_engine_path.dart';

/// 🧭관제 (audio-same-across-devices ③, 2026-11-05): a conform rebuilt on
/// another device holds the same samples (user, gpu-same-formula-Q2) — so
/// each bundled decoder's output is pinned in the one fingerprint ledger,
/// and the release builds' parity step runs this file on ARM64 (TestFlight,
/// the Mac build, windows-11-arm) where the CI shards run it on x64.
///
/// The MP3 and FLAC were made once on Windows 11 by its own encoders
/// (MediaTranscoder, `CreateMp3` · `CreateFlac` at Medium) from a one-second
/// stereo source: a sweep on the left, a chord on the right, a 220 Hz tone
/// on both, four clicks. That gives the MP3 mid/side frames and every block
/// type, and the FLAC LPC subframes. The WAV is written here from whole
/// numbers by the app's own writer.
///
/// ⏳Not here yet: the Ogg Vorbis tables take libm cos/sin, which wait for the
/// one deterministic set the canvas side brings (관제 12:10, the card's ②).
/// AAC is the OS's decoder and may differ by device (관제 12:01).
void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();
  final skip = libraryPath == null ? nativeEngineMissingSkipReason : false;

  setUp(() {
    QaAudioDecoder.debugResetForTests();
    debugQaEngineLibraryPathOverride = libraryPath;
  });

  tearDown(() {
    QaAudioDecoder.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
  });

  void expectPinned(
    QaDecodedAudio? decoded, {
    required QaAudioFormat format,
    required int channels,
    required int sampleRate,
    required int frames,
    required String ledgerId,
  }) {
    expect(decoded, isNotNull, reason: 'nothing decoded it');
    expect(
      (decoded!.format, decoded.channels, decoded.sampleRate, decoded.length),
      (format, channels, sampleRate, frames),
    );
    final samples = decoded.samples;
    final crc = anicelCrc32(
      samples.buffer.asUint8List(samples.offsetInBytes, samples.lengthInBytes),
    );
    expect(crc.toRadixString(16).padLeft(8, '0'), pinnedFingerprint(ledgerId));
  }

  test('the MP3 decodes to the pinned samples', () {
    expectPinned(
      decodeAudioFile('test/fixtures/tone.mp3'),
      format: QaAudioFormat.mp3,
      channels: 2,
      sampleRate: 44100,
      frames: 44975,
      ledgerId: 'audio/tone.mp3-samples',
    );
  }, skip: skip);

  test('the FLAC decodes to the pinned samples', () {
    expectPinned(
      decodeAudioFile('test/fixtures/tone.flac'),
      format: QaAudioFormat.flac,
      channels: 2,
      sampleRate: 44100,
      frames: 44100,
      ledgerId: 'audio/tone.flac-samples',
    );
  }, skip: skip);

  test('the WAV decodes to the pinned samples', () {
    expectPinned(
      decodeAudioBytes(wholeNumberWav()),
      format: QaAudioFormat.wav,
      channels: 2,
      sampleRate: 48000,
      frames: 4800,
      ledgerId: 'audio/whole-number.wav-samples',
    );
  }, skip: skip);
}

/// Two channels of whole numbers at 48 kHz: a full-scale sawtooth on the
/// left, a linear congruential stream on the right.
Uint8List wholeNumberWav() {
  const frames = 4800;
  final pcm = Int16List(frames * 2);
  var seed = 0x2545F491;
  for (var index = 0; index < frames; index += 1) {
    pcm[index * 2] = ((index * 1031) & 0xFFFF) - 0x8000;
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
    pcm[index * 2 + 1] = (seed >> 15) - 0x8000;
  }
  return wav16Bytes(pcm, sampleRate: 48000, channels: 2);
}

String? pinnedFingerprint(String id) {
  final ledger = File('test/fixtures/fingerprints.json');
  if (!ledger.existsSync()) return null;
  final rows = (jsonDecode(ledger.readAsStringSync()) as Map)['rows'] as List;
  for (final row in rows.cast<Map>()) {
    if (row['id'] == id) return row['hash'] as String;
  }
  return null;
}

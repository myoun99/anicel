import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/framed_media_fixture.dart';
import 'package:anicel/src/native/qa_cel_compressor.dart';
import 'package:anicel/src/services/audio/conform_pcm_codec.dart';
import 'package:anicel/src/services/audio/conform_pcm_stream.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/persistence/media_blob_codec.dart';

/// 🚨★★★**COMPRESSING THE CONFORM MUST NOT MOVE ONE SAMPLE.**
///
/// 유저 2026-08-30 accepted compression on one condition, stated twice in
/// the same sentence: 「재생시 압축해제때문에 오디오가 싱크 안맞으면 절대
/// 안되니 그부분만 철저히」. A window that comes back one sample early is
/// not a glitch you hear — it is lip-sync that drifts, and it would look
/// like a timeline bug for weeks.
///
/// ⛔So「it round-trips」is not the assertion. These compare the framed
/// read against the PLAIN read of the same audio, sample by sample, at
/// offsets chosen to land inside a block, across a block boundary, and at
/// the very end — because the boundary is the only place the two designs
/// can disagree.
void main() {
  bool engineHere() {
    final compressor = QaCelCompressor.instance;
    return compressor != null && compressor.isSupported;
  }

  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('qa-conform-framed');
  });

  tearDown(() => directory.delete(recursive: true));

  /// Stereo audio whose VALUE encodes its position, so a window read from
  /// the wrong offset cannot accidentally look right.
  ///
  /// A slow ramp rather than noise: a conform IS compressible audio, and
  /// data zstd cannot shrink would be stored plain and never reach the
  /// path under test.
  Uint8List rampWav(int lengthSamples) {
    final samples = Float32List(lengthSamples * 2);
    for (var index = 0; index < lengthSamples; index += 1) {
      samples[index * 2] = ((index % 4096) / 4096.0) - 0.5;
      samples[index * 2 + 1] = 0.5 - ((index % 4096) / 4096.0);
    }
    return encodeConform(
      samples: samples,
      channels: 2,
      sampleRate: 48000,
      fingerprint: const ConformSourceFingerprint(
        sourceLength: 7,
        sourceCrc32: 11,
      ),
    );
  }

  /// One block holds this many stereo int16 samples — the boundary the
  /// framed reader has to cross correctly.
  int samplesPerBlock(int blockBytes) => blockBytes ~/ 4;

  test('🚨a framed conform returns the SAME samples as the plain one', () {
    if (!engineHere()) {
      markTestSkipped('no engine on this run');
      return;
    }
    final perBlock = samplesPerBlock(mediaBlockBytes);
    // Two blocks and a bit, so there is a real boundary to cross.
    final wav = rampWav(perBlock * 2 + 5000);
    final framedBytes = framedEntryBytes(wav);
    expect(
      framedBytes,
      isNotNull,
      reason: 'fixture: a conform is PCM, which compresses',
    );

    final plainPath = '${directory.path}/take.1234abcd.wav';
    final framedPath = '$plainPath$mediaFramedEntrySuffix';
    File(plainPath).writeAsBytesSync(wav);
    File(framedPath).writeAsBytesSync(framedBytes!);

    final plain = ConformPcmStreamReader.open(plainPath)!;
    final framed = ConformPcmStreamReader.open(framedPath)!;

    expect(framed.channels, plain.channels);
    expect(framed.sampleRate, plain.sampleRate);
    expect(
      framed.length,
      plain.length,
      reason: 'the header is read through the frames, not around them',
    );

    for (final at in <int>[
      0,
      1234,
      perBlock - 100, // ends exactly on the boundary
      perBlock - 50, // straddles it
      perBlock, // starts on it
      perBlock * 2 - 1, // straddles the second one
      plain.length - 700, // the tail
    ]) {
      final want = plain.readWindow(at, 900);
      final got = framed.readWindow(at, 900);
      expect(got.startSample, want.startSample, reason: 'window start at $at');
      expect(
        got.samples.length,
        want.samples.length,
        reason: 'window length at $at',
      );
      for (var index = 0; index < want.samples.length; index += 1) {
        // ⛔Exact, not closeTo. Both sides read the same int16 and apply
        // the same scale; anything but equality means one of them moved.
        expect(
          got.samples[index],
          want.samples[index],
          reason: 'sample $index of the window at $at diverged',
        );
      }
    }
  });

  test('a window still reads only the blocks it lands in', () {
    if (!engineHere()) {
      markTestSkipped('no engine on this run');
      return;
    }
    final perBlock = samplesPerBlock(mediaBlockBytes);
    final entry = framedEntryBytes(rampWav(perBlock * 3))!;
    var bytesRead = 0;
    // 🚨[MediaByteSource] is sealed, so counting has to go through the
    // read FUNCTION — which is exactly why `MediaFramedBytes.reading`
    // takes one. Without an instrument here every assertion above would
    // also pass on a reader that pulls the whole entry each time.
    final reader = ConformPcmStreamReader.over(
      MediaFramedBytes.reading(
        readStored: (buffer, position, size) {
          if (position < 0 || position >= entry.length || size <= 0) {
            return 0;
          }
          final available = entry.length - position;
          final take = size < available ? size : available;
          buffer.setRange(0, take, entry, position);
          bytesRead += take;
          return take;
        },
        storedExists: () => true,
        label: 'conform',
      ),
    )!;
    bytesRead = 0;

    reader.readWindow(perBlock + 10, 200);
    expect(
      bytesRead,
      lessThan(entry.length ~/ 2),
      reason:
          '⛔a reader that pulled the whole conform would return the right '
          'samples and have thrown the window away, which is what keeps '
          "an hour of dialogue off a tablet's heap",
    );
  });

  test('the NAME decides how it is read, and open follows it', () {
    if (!engineHere()) {
      markTestSkipped('no engine on this run');
      return;
    }
    final wav = rampWav(20000);
    // Framed bytes under the PLAIN name: nothing says to decompress them,
    // so this must not be mistaken for a WAV.
    final wrong = '${directory.path}/mislabelled.aaaabbbb.wav';
    File(wrong).writeAsBytesSync(framedEntryBytes(wav)!);
    expect(
      ConformPcmStreamReader.open(wrong),
      isNull,
      reason: 'a block index is not a RIFF header, and open says so',
    );

    // Plain bytes under the framed name: the same rule, the other way.
    final alsoWrong =
        '${directory.path}/plain.aaaabbbb.wav'
        '$mediaFramedEntrySuffix';
    File(alsoWrong).writeAsBytesSync(wav);
    expect(ConformPcmStreamReader.open(alsoWrong), isNull);
  });
}

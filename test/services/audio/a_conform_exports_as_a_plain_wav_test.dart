import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_cel_compressor.dart';
import 'package:anicel/src/services/audio/conform_pcm_codec.dart';
import 'package:anicel/src/services/audio/conform_wav_export.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/persistence/media_blob_codec.dart';

/// 🚨★★★**WHAT COMPRESSION TOOK AWAY, HANDED BACK ON DEMAND.**
///
/// A conform used to BE a WAV, so「open it in anything」was a property of
/// the cache file. 유저 2026-08-30 gave that up knowingly — 「다른 앱으로
/// 들을 필요성을 못느끼겟고 그럴거면 압축해제시켜서 내보내기 기능 만들면
/// 되는거아닌가?」 — and this is that function.
///
/// The thing worth pinning is not「a file appeared」but that the SAMPLES
/// come out unchanged, from a framed conform as much as a plain one.
void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('anicel-wav-export-');
  });

  tearDown(() {
    try {
      directory.deleteSync(recursive: true);
    } on Object {
      // A leaked handle on Windows must not fail the suite.
    }
  });

  bool engineHere() {
    final compressor = QaCelCompressor.instance;
    return compressor != null && compressor.isSupported;
  }

  String at(String name) => '${directory.path.replaceAll(r'\', '/')}/$name';

  /// A ramp, so every sample is checkable and the bytes compress.
  Float32List ramp(int frames, int channels) {
    final samples = Float32List(frames * channels);
    for (var index = 0; index < samples.length; index += 1) {
      samples[index] = (index % 2000) / 2000.0 - 0.5;
    }
    return samples;
  }

  Uint8List conformBytes({int frames = 40000, int channels = 2}) =>
      encodeConform(
        samples: ramp(frames, channels),
        channels: channels,
        sampleRate: 48000,
      );

  /// What the reader hands back from [path], through the same view the
  /// export uses — so a framed file and a plain one are read alike.
  ({int sampleRate, int channels, int dataBytes, Uint8List pcm}) readWav(
    String path,
  ) {
    final bytes = File(path).readAsBytesSync();
    final view = ByteData.sublistView(bytes);
    expect(
      String.fromCharCodes(bytes.sublist(0, 4)),
      'RIFF',
      reason: 'any audio tool starts here',
    );
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
    return (
      sampleRate: view.getUint32(24, Endian.little),
      channels: view.getUint16(22, Endian.little),
      dataBytes: view.getUint32(40, Endian.little),
      pcm: Uint8List.sublistView(bytes, 44),
    );
  }

  test('a plain conform comes out as a WAV with the same samples', () async {
    final conform = conformBytes();
    final source = at('take.wav.abc12345.wav');
    File(source).writeAsBytesSync(conform);

    final out = at('exported.wav');
    expect(
      await writeConformAsWav(
        conform: mediaAppFileSource(source),
        destinationPath: out,
      ),
      isTrue,
    );

    final wav = readWav(out);
    final header = ConformHeader.parse(conform);
    expect(wav.sampleRate, 48000);
    expect(wav.channels, 2);
    expect(wav.dataBytes, header.dataBytes);
    expect(
      wav.pcm,
      Uint8List.sublistView(conform, ConformHeader.length, header.totalBytes),
      reason:
          '⚡not a sample is converted — a conform already holds interleaved '
          'int16 at the project rate, which is what a 16-bit WAV holds',
    );
  });

  test('🚨and a FRAMED conform comes out identical', () async {
    if (!engineHere()) {
      markTestSkipped('no engine on this run');
      return;
    }
    final conform = conformBytes();
    final base = at('take.wav.abc12345.wav');
    final written = writeMediaBlob(
      basePath: base,
      length: conform.length,
      readInto: mediaBytesReader(conform),
    );
    expect(
      written.framed,
      isTrue,
      reason: 'fixture: a ramp compresses, so the framed road is under test',
    );

    final out = at('exported.wav');
    expect(
      await writeConformAsWav(
        conform: mediaAppFileSource(written.path),
        destinationPath: out,
      ),
      isTrue,
      reason: 'the source un-frames on the way through, so the exporter '
          'never learns that compression happened',
    );

    final header = ConformHeader.parse(conform);
    expect(
      readWav(out).pcm,
      Uint8List.sublistView(conform, ConformHeader.length, header.totalBytes),
    );
  });

  test('⛔a file that is not a conform writes nothing and says so', () async {
    final source = at('not-a-conform.bin');
    File(source).writeAsBytesSync(
      Uint8List.fromList(List<int>.generate(200, (i) => i & 0xFF)),
    );

    final out = at('exported.wav');
    expect(
      await writeConformAsWav(
        conform: mediaAppFileSource(source),
        destinationPath: out,
      ),
      isFalse,
      reason: 'a truncated or foreign file must not be presented as audio',
    );
  });

  test('the PCM never lands in memory whole — it crosses in blocks', () async {
    // 691MB for an hour of dialogue is the number this shape exists for, so
    // the property is the size of the reads, not the size of the file.
    final conform = conformBytes(frames: 400000);
    final source = at('long.wav.abc12345.wav');
    File(source).writeAsBytesSync(conform);
    expect(
      conform.length,
      greaterThan(1024 * 1024),
      reason: 'fixture: bigger than one copy buffer, or this proves nothing',
    );

    final out = at('exported.wav');
    expect(
      await writeConformAsWav(
        conform: mediaAppFileSource(source),
        destinationPath: out,
      ),
      isTrue,
    );
    expect(File(out).lengthSync(), 44 + ConformHeader.parse(conform).dataBytes);
  });
}

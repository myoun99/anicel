import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart'
    show anicelCrc32;

/// 🚨★★★**「WHERE ARE YOUR BYTES」 IS ONE QUESTION WITH ONE ANSWERER.**
///
/// The native decoders take a path plus an offset and a length, so anything
/// that can name itself that way never becomes a `Uint8List` first — which is
/// the whole difference between a movie's soundtrack being conformable and a
/// three-gigabyte allocation. Before [MediaByteSource.range] existed, the
/// viewer rebuilt that triple by hand out of `MediaArchiveBytes` fields: a
/// type test plus three reads, in one place, waiting for a second.
///
/// ⛔The null answers matter as much as the spans. A framed entry is stored
/// in compressed blocks, so the bytes at its span are NOT the container —
/// decoding them in place would produce noise, confidently.
void main() {
  late Directory scratch;

  setUp(() => scratch = Directory.systemTemp.createTempSync('qa_range_src'));
  tearDown(() => scratch.deleteSync(recursive: true));

  String write(String name, List<int> bytes) {
    final path = '${scratch.path}${Platform.pathSeparator}$name';
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  test('a loose file is a range: itself, from zero', () {
    final path = write('sound.wav', List.filled(2048, 7));

    expect(
      MediaFileBytes(path).range,
      (path: path, offset: 0, length: 2048),
      reason: 'the ordinary case has to go through the same door, or every '
          'caller carries a second path for it',
    );
  });

  test('a file that is not there answers null instead of throwing', () {
    // 🚨The viewer asks this getter PRECISELY when the import original is
    // gone — that is what carrying exists to survive. A `lengthSync` thrown
    // out of a getter turned 「no, not this way」 into an exception.
    expect(MediaFileBytes('${scratch.path}/gone.wav').range, isNull);
  });

  test('an archive entry is a range INSIDE the project file', () {
    expect(
      const MediaArchiveBytes(
        archivePath: '/p/film.anicel',
        dataOffset: 91234,
        length: 5000,
      ).range,
      (path: '/p/film.anicel', offset: 91234, length: 5000),
    );
  });

  test('a FRAMED entry answers null — its span is compressed blocks, not a '
      'container', () {
    expect(
      const MediaArchiveBytes(
        archivePath: '/p/film.anicel',
        dataOffset: 91234,
        length: 5000,
        framed: true,
      ).range,
      isNull,
    );
    final path = write('framed.bin', List.filled(64, 1));
    expect(MediaAppFileBytes(path: path, framed: true).range, isNull);
    expect(
      MediaAppFileBytes(path: path, framed: false).range,
      (path: path, offset: 0, length: 64),
    );
  });

  group('the fingerprint streams what it cannot hold', () {
    test('a range fingerprint equals the one taken from the bytes', () {
      // Bigger than the 64KB window on purpose: a chunked CRC that folds
      // only the first block, or folds a partial last block wrong, passes
      // every small fixture.
      final bytes = Uint8List.fromList(
        List.generate(300 * 1024, (i) => (i * 31 + (i >> 9)) & 0xFF),
      );
      final path = write('long.wav', bytes);

      final streamed = AudioConformPipeline.fingerprintOfSource(
        MediaFileBytes(path),
      );

      expect(streamed.sourceLength, bytes.length);
      expect(streamed.sourceCrc32, anicelCrc32(bytes));
      expect(streamed, AudioConformPipeline.fingerprintOf(bytes));
    });

    test('a fingerprint of a range inside a file sees only that range', () {
      final inner = Uint8List.fromList(
        List.generate(70 * 1024, (i) => (i * 17) & 0xFF),
      );
      final path = write('archive.bin', [
        ...List.filled(1000, 0xAA),
        ...inner,
        ...List.filled(999, 0xBB),
      ]);

      final streamed = AudioConformPipeline.fingerprintOfSource(
        MediaArchiveBytes(
          archivePath: path,
          dataOffset: 1000,
          length: inner.length,
        ),
      );

      expect(streamed.sourceLength, inner.length);
      expect(
        streamed.sourceCrc32,
        anicelCrc32(inner),
        reason: 'the padding on either side must not reach the checksum — '
            'this is the assertion a dropped offset dies on',
      );
    });

    test('a framed source falls back to its assembled bytes', () {
      // ⚠️Not a shortcut: the stored blocks are compressed, so the only way
      // to see this source's content is to have it put together.
      final bytes = Uint8List.fromList(List.generate(4096, (i) => i & 0xFF));
      final path = write('plain.bin', bytes);

      expect(
        AudioConformPipeline.fingerprintOfSource(
          MediaAppFileBytes(path: path, framed: false),
        ).sourceCrc32,
        anicelCrc32(bytes),
      );
    });
  });
}

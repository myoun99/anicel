import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_cel_compressor.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart'
    show anicelCrc32;
import '../../helpers/framed_media_fixture.dart';
import '../../helpers/temp_dir.dart';

/// 🚨★★★**「WHERE ARE YOUR BYTES」 IS ONE QUESTION WITH ONE ANSWERER.**
///
/// Every native reader takes a path, an offset, a length and whether the
/// bytes there are FRAMED, so anything that can name itself that way never
/// becomes a `Uint8List` first — which is the whole difference between a
/// movie's soundtrack being conformable and a three-gigabyte allocation.
/// Before [MediaByteSource.span] existed, the viewer rebuilt that answer by
/// hand out of `MediaArchiveBytes` fields: a type test plus three reads, in
/// one place, waiting for a second.
///
/// 🪦A framed entry used to answer NULL here — 「its span is compressed
/// blocks, not a container」 — because nothing native could read one. The
/// engine's span reader can (2026-09-24), so framed is now part of the
/// answer, and the danger the null guarded against moved into the field: a
/// span that FAILED to say framed would be decoded as noise, confidently.
void main() {
  late Directory scratch;

  setUp(() => scratch = Directory.systemTemp.createTempSync('qa_span_src'));
  tearDown(() => deleteTempQuietly(scratch));

  String write(String name, List<int> bytes) {
    final path = '${scratch.path}${Platform.pathSeparator}$name';
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  test('a loose file is a span: itself, from zero, as it is', () {
    final path = write('sound.wav', List.filled(2048, 7));

    expect(
      MediaFileBytes(path).span,
      (path: path, offset: 0, length: 2048, framed: false),
      reason: 'the ordinary case has to go through the same door, or every '
          'caller carries a second path for it',
    );
  });

  test('a file that is not there answers null instead of throwing', () {
    // 🚨The viewer asks this getter PRECISELY when the import original is
    // gone — that is what carrying exists to survive. A `lengthSync` thrown
    // out of a getter turned 「no, not this way」 into an exception.
    expect(MediaFileBytes('${scratch.path}/gone.wav').span, isNull);
  });

  test('an archive entry is a span INSIDE the project file', () {
    expect(
      const MediaArchiveBytes(
        archivePath: '/p/film.anicel',
        dataOffset: 91234,
        length: 5000,
      ).span,
      (path: '/p/film.anicel', offset: 91234, length: 5000, framed: false),
    );
  });

  test('🚨a FRAMED entry is the same span, and SAYS it is framed', () {
    const stored = MediaArchiveBytes(
      archivePath: '/p/film.anicel',
      dataOffset: 91234,
      length: 5000,
      framed: true,
    );
    expect(
      stored.span,
      (path: '/p/film.anicel', offset: 91234, length: 5000, framed: true),
    );
    expect(
      MediaFramedBytes(stored).span,
      stored.span,
      reason: 'the wrapper that decodes it names the same medium',
    );

    final path = write('framed.bin', List.filled(64, 1));
    expect(
      MediaAppFileBytes(path: path, framed: true).span,
      (path: path, offset: 0, length: 64, framed: true),
    );
    expect(
      MediaAppFileBytes(path: path, framed: false).span,
      (path: path, offset: 0, length: 64, framed: false),
    );
    expect(
      MediaFramedBytes(MediaFileBytes(path)).span?.framed,
      isTrue,
      reason: 'being handed to the framed reader is what says the bytes are '
          'a framed blob — whatever the source under it thought',
    );
  });

  group('the fingerprint streams what it cannot hold', () {
    test('a streamed fingerprint is the CRC of the bytes', () {
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
    });

    test('a fingerprint of a span inside a file sees only that span', () {
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

    test('a FRAMED source is fingerprinted as the medium it holds', () {
      final compressor = QaCelCompressor.instance;
      if (compressor == null || !compressor.isSupported) {
        markTestSkipped('no engine on this run');
        return;
      }
      // Several blocks and a tail, so the window crosses block boundaries.
      final bytes = Uint8List.fromList(
        List.generate(1300 * 1024, (i) => (i ~/ 7 + (i % 5)) & 0xFF),
      );
      final entry = framedEntryBytes(bytes);
      expect(entry, isNotNull, reason: 'fixture: this data compresses');
      final path = write('take.wav.z', entry!);

      final streamed = AudioConformPipeline.fingerprintOfSource(
        mediaAppFileSource(path),
      );

      expect(
        streamed.sourceLength,
        bytes.length,
        reason: 'the MEDIUM\'s length, not the compressed entry\'s',
      );
      expect(
        streamed.sourceCrc32,
        anicelCrc32(bytes),
        reason: 'the identity is the medium\'s whichever way it is stored — '
            'otherwise re-compressing a file would orphan its conform',
      );
    });
  });
}

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/framed_media_fixture.dart';
import 'package:anicel/src/native/qa_cel_compressor.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/persistence/media_blob_codec.dart';
import '../../helpers/temp_dir.dart';

/// 🚨★★★**THE POINT IS THE WINDOW.** Compressing media whole would buy
/// 38% on audio and take away `MediaArchiveBytes`'s ability to hand out a
/// byte RANGE — which is how a hundred-page conte is read a page at a time
/// rather than landing in memory (유저 2026-08-27: 「3기가 영상파일도
/// 볼거라서 결국 그게 그대로 메모리에 올라가면 문제되는데」).
///
/// So these check what a whole-frame format could not do: that the header
/// can be found from a fixed-size prefix. That a range maps to the blocks it
/// actually touches and no others is the READER's, and is pinned where the
/// one reader is — `qa_media_span_test.c`, and against this writer's files
/// in `framed_media_reads_only_the_blocks_it_needs_test.dart`.
void main() {
  bool engineHere() {
    final compressor = QaCelCompressor.instance;
    return compressor != null && compressor.isSupported;
  }

  /// Compressible bytes — a repeating pattern with enough variety that
  /// zstd cannot fold it to nothing, so the ratios stay realistic.
  Uint8List compressible(int length) {
    final random = Random(7);
    final out = Uint8List(length);
    for (var i = 0; i < length; i += 1) {
      out[i] = (i ~/ 64 + random.nextInt(3)) & 0xFF;
    }
    return out;
  }

  group('the header is laid out where the reader looks', () {
    test('the block count sits at a FIXED offset, so sixteen bytes say how '
        'long the header is', () {
      const header = MediaBlobHeader(
        blockBytes: mediaBlockBytes,
        totalLength: 9 * 1024 * 1024 + 5,
        blockLengths: [11, 22, 33],
      );
      final bytes = header.toBytes();
      final view = ByteData.sublistView(bytes);

      // ⛔The layout `qa_media_span.h` reads, field by field: a reader
      // holding a 3GB movie's entry must never have to read it to find the
      // index, and the engine's reader — the only one there is — trusts
      // exactly these offsets.
      expect(bytes.length, MediaBlobHeader.prefixLength + 4 * 3);
      expect(bytes.length, header.length);
      expect(view.getUint32(0, Endian.little), mediaBlockBytes);
      expect(view.getUint64(4, Endian.little), 9 * 1024 * 1024 + 5);
      expect(view.getUint32(12, Endian.little), 3);
      expect([
        for (var i = 0; i < 3; i += 1)
          view.getUint32(16 + 4 * i, Endian.little),
      ], [11, 22, 33]);
    });
  });

  group('compressing', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('anicel-codec-');
    });

    tearDown(() => deleteTempQuietly(directory));

    /// [source] through the writer that ships, and read back through the
    /// reader that ships — the engine's, which is the only one there is.
    ({bool framed, Uint8List entry, Uint8List back}) roundTrip(
      Uint8List source,
    ) {
      final written = writeMediaBlob(
        basePath: '${directory.path.replaceAll(r'\', '/')}/entry',
        length: source.length,
        readInto: mediaBytesReader(source),
      );
      return (
        framed: written.framed,
        entry: File(written.path).readAsBytesSync(),
        back: mediaAppFileSource(written.path).readSync(),
      );
    }

    test('bytes that will not shrink are stored, not framed', () {
      if (!engineHere()) {
        markTestSkipped('no engine on this run');
        return;
      }
      // 🚨Random bytes, and the comment used to call them「a JPEG or an
      // MP4」. Measured, a JPEG saves 15–21% and an MP4 6.7% — they are
      // FRAMED. What is genuinely incompressible is noise (and PNG, at
      // 0.0%), so that is what this stands for.
      final random = Random(11);
      final noise = Uint8List.fromList(
        List<int>.generate(256 * 1024, (_) => random.nextInt(256)),
      );
      expect(
        framedEntryBytes(noise),
        isNull,
        reason:
            'null means「store the file as it is」— paying a decompression '
            'on every read to save nothing is the trade this refuses',
      );
    });

    test('compressible bytes round-trip through the framed form', () {
      if (!engineHere()) {
        markTestSkipped('no engine on this run');
        return;
      }
      final source = compressible(300 * 1024);
      final (:framed, :entry, :back) = roundTrip(source);
      expect(framed, isTrue, reason: 'fixture: this data does compress');
      expect(
        entry.length,
        lessThan(source.length),
        reason: 'and the whole entry, index included, is smaller',
      );
      expect(back, source);
    });

    test('a file longer than one block gets one index entry per block', () {
      if (!engineHere()) {
        markTestSkipped('no engine on this run');
        return;
      }
      // Two blocks and a bit, at a block size a test can afford.
      final source = compressible(mediaBlockBytes * 2 + 1024);
      final (:framed, :entry, :back) = roundTrip(source);
      expect(framed, isTrue);
      final view = ByteData.sublistView(entry);
      expect(view.getUint32(12, Endian.little), 3, reason: 'the block count');
      expect(view.getUint64(4, Endian.little), source.length);
      expect(back, source);
    });

    test('an empty file is stored', () {
      expect(framedEntryBytes(Uint8List(0)), isNull);
    });

    test('without an engine, everything is stored — no deflate floor here', () {
      QaCelCompressor.debugInstanceOverride = () => null;
      addTearDown(() {
        QaCelCompressor.debugInstanceOverride = null;
        QaCelCompressor.debugResetForTests();
      });
      expect(
        framedEntryBytes(compressible(64 * 1024)),
        isNull,
        reason:
            '⛔a cel MUST be readable by any build, but media has a free '
            'alternative — so no .anicel ever needs a library to give its '
            'media back',
      );
    });
  });

  group('the entry name is what says it is framed', () {
    test('a suffix, the way project.json.z already does it', () {
      expect(
        mediaEntryIsFramed('media/0a1b2c3d-take.wav$mediaFramedEntrySuffix'),
        isTrue,
      );
      expect(mediaEntryIsFramed('media/0a1b2c3d-clip.mp4'), isFalse);
    });

    test('⛔a stored entry is the FILE, with nothing in front of it', () {
      if (!engineHere()) {
        markTestSkipped('no engine on this run');
        return;
      }
      final random = Random(3);
      final noise = Uint8List.fromList(
        List<int>.generate(8 * 1024, (_) => random.nextInt(256)),
      );
      // The contract a plain seek and an unzip tool both depend on: when
      // this answers null the caller writes the source bytes untouched, so
      // there is no header to skip and no byte to strip.
      expect(framedEntryBytes(noise), isNull);
    });

    /// 🚨**THE WRITE IS STREAMED, AND THIS IS WHAT SAYS SO.**
    ///
    /// The writer this replaced took the asset as one `Uint8List` and built
    /// every compressed block beside it before judging the total — so a 4GB
    /// movie was the file twice over, resident at once, at the moment 품기
    /// is pressed. Nothing about the OUTPUT changed, which is why no
    /// existing test moved: the property that changed is how much is held
    /// at once, and the only handle a test has on it is the size of the
    /// reads the writer asks for.
    test('🚨 a write\'s neighbour is its own — a `.part` another writer holds '
        'at the same name is not touched (I-7)', () {
      final directory = Directory.systemTemp.createTempSync('anicel-part-');
      try {
        final base = '${directory.path}/take.wav';
        // What a second open project's build of the same conform is
        // writing while this one runs.
        final theirs = File('$base.part')..writeAsBytesSync([1, 2, 3]);
        final bytes = Uint8List.fromList(
          List<int>.generate(1000, (i) => i & 0xFF),
        );

        final written = writeMediaBlob(
          basePath: base,
          length: bytes.length,
          readInto: mediaBytesReader(bytes),
        );

        expect(
          theirs.readAsBytesSync(),
          [1, 2, 3],
          reason: 'a shared neighbour is truncated by whichever write opens '
              'it second',
        );
        expect(File(written.path).existsSync(), isTrue);
        expect(
          [
            for (final entity in directory.listSync())
              if (entity.path.endsWith('.part')) entity.path,
          ],
          hasLength(1),
          reason: 'and this write left no neighbour of its own behind',
        );
      } finally {
        deleteTempQuietly(directory);
      }
    });

    test('🚨 no read is larger than one block, whatever the asset weighs', () {
      if (!engineHere()) {
        markTestSkipped('no engine on this run');
        return;
      }
      const block = 64 * 1024;
      final random = Random(11);
      final noise = Uint8List.fromList(
        List<int>.generate(block * 8, (_) => random.nextInt(256)),
      );
      var biggest = 0;
      final directory = Directory.systemTemp.createTempSync('anicel-stream-');
      try {
        final read = mediaBytesReader(noise);
        final written = writeMediaBlob(
          basePath: '${directory.path.replaceAll(r'\', '/')}/entry',
          length: noise.length,
          blockBytes: block,
          readInto: (buffer, position, size) {
            biggest = size > biggest ? size : biggest;
            return read(buffer, position, size);
          },
        );
        expect(
          written.framed,
          isFalse,
          reason: 'fixture: noise does not shrink',
        );
        expect(
          File(written.path).readAsBytesSync(),
          noise,
          reason: 'a stored entry IS the asset, byte for byte',
        );
      } finally {
        deleteTempQuietly(directory);
      }
      expect(
        biggest,
        lessThanOrEqualTo(block),
        reason:
            'a read bigger than a block means the whole asset landed in '
            'memory — the shape this write was rebuilt to lose',
      );
    });
  });
}

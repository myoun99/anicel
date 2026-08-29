import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_cel_compressor.dart';
import 'package:anicel/src/services/persistence/media_blob_codec.dart';

/// 🚨★★★**THE POINT IS THE WINDOW.** Compressing media whole would buy
/// 38% on audio and take away `MediaArchiveBytes`'s ability to hand out a
/// byte RANGE — which is how a hundred-page conte is read a page at a time
/// rather than landing in memory (유저 2026-08-27: 「3기가 영상파일도
/// 볼거라서 결국 그게 그대로 메모리에 올라가면 문제되는데」).
///
/// So these check two things a whole-frame format could not do: that the
/// header can be found from a fixed-size prefix, and that a range maps to
/// the blocks it actually touches and no others.
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

  group('the header finds its own way', () {
    test('a prefix says how long the header is, before the blocks', () {
      const header = MediaBlobHeader(
        blockBytes: mediaBlockBytes,
        totalLength: 9 * 1024 * 1024,
        blockLengths: [11, 22, 33],
      );
      final bytes = header.toBytes();
      expect(bytes.length, header.length);
      // ⛔The prefix alone, not the whole entry: a reader holding a 3GB
      // movie's entry must never have to read it to find the index.
      expect(
        MediaBlobHeader.headerLengthOf(
          Uint8List.sublistView(bytes, 0, MediaBlobHeader.prefixLength),
        ),
        header.length,
      );
    });

    test('round-trips through its own bytes', () {
      const header = MediaBlobHeader(
        blockBytes: 4096,
        totalLength: 10000,
        blockLengths: [100, 200, 300],
      );
      final back = MediaBlobHeader.parse(header.toBytes());
      expect(back.blockBytes, 4096);
      expect(back.totalLength, 10000);
      expect(back.blockLengths, [100, 200, 300]);
      expect(back.offsetOf(0), header.length);
      expect(back.offsetOf(1), header.length + 100);
      expect(back.offsetOf(2), header.length + 300);
    });

    test('a short or malformed header is a FormatException, not a guess', () {
      expect(
        () => MediaBlobHeader.parse(Uint8List(4)),
        throwsA(isA<FormatException>()),
      );
      final header = const MediaBlobHeader(
        blockBytes: 4096,
        totalLength: 10,
        blockLengths: [1, 2, 3],
      ).toBytes();
      expect(
        () => MediaBlobHeader.parse(Uint8List.sublistView(header, 0, 18)),
        throwsA(isA<FormatException>()),
        reason: 'the index is cut short — say so rather than read garbage',
      );
    });
  });

  group('a range touches only the blocks it covers', () {
    const header = MediaBlobHeader(
      blockBytes: 100,
      totalLength: 350,
      blockLengths: [10, 10, 10, 10],
    );

    test('inside one block', () {
      expect(header.blocksFor(10, 20), (first: 0, last: 0));
      expect(header.blocksFor(150, 20), (first: 1, last: 1));
    });

    test('across a boundary takes both, and no more', () {
      expect(header.blocksFor(90, 20), (first: 0, last: 1));
      expect(header.blocksFor(0, 350), (
        first: 0,
        last: 3,
      ), reason: 'the whole file is every block');
    });

    test('a read that runs past the end is clamped, not extended', () {
      expect(
        header.blocksFor(340, 1000),
        (first: 3, last: 3),
        reason: '350 bytes exist; asking for more must not name a 5th block',
      );
    });

    test('an empty or past-the-end read touches nothing', () {
      expect(header.blocksFor(0, 0), isNull);
      expect(header.blocksFor(350, 10), isNull);
    });

    test('the last byte belongs to the last block, not the one after', () {
      // 🚨The off-by-one this format is most likely to get wrong: an end
      // that lands exactly on a boundary must not name the next block.
      expect(header.blocksFor(0, 100), (first: 0, last: 0));
      expect(header.blocksFor(0, 101), (first: 0, last: 1));
    });
  });

  group('compressing', () {
    test('already-compressed bytes are stored, not framed', () {
      if (!engineHere()) {
        markTestSkipped('no engine on this run');
        return;
      }
      // Random bytes stand in for a JPEG or an MP4: nothing to find.
      final random = Random(11);
      final noise = Uint8List.fromList(
        List<int>.generate(256 * 1024, (_) => random.nextInt(256)),
      );
      expect(
        compressMediaBlob(noise),
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
      final packed = compressMediaBlob(source);
      expect(packed, isNotNull, reason: 'fixture: this data does compress');
      expect(
        packed!.length,
        lessThan(source.length),
        reason: 'and the whole entry, index included, is smaller',
      );
      expect(decompressMediaBlob(packed), source);
    });

    test('a file longer than one block gets one index entry per block', () {
      if (!engineHere()) {
        markTestSkipped('no engine on this run');
        return;
      }
      // Two blocks and a bit, at a block size a test can afford.
      final source = compressible(mediaBlockBytes * 2 + 1024);
      final packed = compressMediaBlob(source);
      expect(packed, isNotNull);
      final header = MediaBlobHeader.parse(packed!);
      expect(header.blockCount, 3);
      expect(header.totalLength, source.length);
      expect(decompressMediaBlob(packed), source);
    });

    test('an empty file is stored', () {
      expect(compressMediaBlob(Uint8List(0)), isNull);
    });

    test('without an engine, everything is stored — no deflate floor here', () {
      QaCelCompressor.debugInstanceOverride = () => null;
      addTearDown(() {
        QaCelCompressor.debugInstanceOverride = null;
        QaCelCompressor.debugResetForTests();
      });
      expect(
        compressMediaBlob(compressible(64 * 1024)),
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
      expect(compressMediaBlob(noise), isNull);
    });
  });
}

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/framed_media_fixture.dart';
import '../../helpers/temp_dir.dart';
import 'package:anicel/src/native/qa_cel_compressor.dart';
import 'package:anicel/src/native/qa_media_span.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/persistence/media_blob_codec.dart';

/// 🚨★★★**A WINDOW MUST STAY A WINDOW.**
///
/// Compressing media whole would buy 38% on audio and cost the ability to
/// read a range — the thing that keeps a hundred-page conte and a
/// three-gigabyte movie off the heap (유저 2026-08-27: 「3기가 영상파일도
/// 볼거라서 결국 그게 그대로 메모리에 올라가면 문제되는데」).
///
/// ⛔So「it round-trips」is not the assertion. These COUNT what the engine's
/// reader decoded and read ([QaMediaSpan.debugOnClose]), because a framed
/// reader that quietly pulled the whole entry would round-trip perfectly and
/// have thrown the entire point away.
///
/// 🚨★★★**AND THE FILES ARE WRITTEN BY THE DART WRITER AND READ BY THE C
/// READER** — the one pairing that ships. `qa_media_span_test.c` pins the
/// reader against a fixture of its own; this is where the two sides of the
/// format meet, so a writer and a reader that drifted apart go red here.
void main() {
  bool engineHere() {
    final compressor = QaCelCompressor.instance;
    return compressor != null && compressor.isSupported;
  }

  late Directory directory;
  late List<({int blocksDecoded, int storedBytesRead})> costs;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('anicel-framed-reads');
    costs = [];
    QaMediaSpan.debugOnClose = costs.add;
  });

  tearDown(() {
    QaMediaSpan.debugOnClose = null;
    deleteTempQuietly(directory);
  });

  /// Compressible bytes whose every position is checkable: byte i is
  /// derived from i, so a window can be compared against what it must be
  /// without holding the whole file.
  Uint8List sourceOf(int length) {
    final out = Uint8List(length);
    for (var i = 0; i < length; i += 1) {
      out[i] = (i ~/ 7 + (i % 5)) & 0xFF;
    }
    return out;
  }

  /// [source] framed by the writer that ships, as the file a staged copy is
  /// — and what the entry's own header says about it, read here from the
  /// layout rather than through anything the app has.
  ({MediaByteSource framed, Uint8List entry, List<int> blocks, int index})
  written(Uint8List source, {int blockBytes = mediaBlockBytes}) {
    final entry = framedEntryBytes(source, blockBytes: blockBytes);
    expect(entry, isNotNull, reason: 'fixture: this data compresses');
    final path = '${directory.path}/take.wav$mediaFramedEntrySuffix';
    File(path).writeAsBytesSync(entry!);
    final view = ByteData.sublistView(entry);
    final count = view.getUint32(12, Endian.little);
    return (
      framed: mediaAppFileSource(path),
      entry: entry,
      blocks: [
        for (var i = 0; i < count; i += 1)
          view.getUint32(16 + 4 * i, Endian.little),
      ],
      index: 16 + 4 * count,
    );
  }

  test('a window reads only the block it lands in', () {
    if (!engineHere()) {
      markTestSkipped('no engine on this run');
      return;
    }
    final source = sourceOf(mediaBlockBytes * 3 + 1000);
    final (:framed, :entry, :blocks, :index) = written(source);

    // A 100-byte window in the MIDDLE block.
    const at = mediaBlockBytes + 12345;
    final window = Uint8List(100);
    expect(framed.readIntoSync(window, at, window.length), 100);
    expect(window, Uint8List.sublistView(source, at, at + 100));

    expect(costs, [
      (blocksDecoded: 1, storedBytesRead: index + blocks[1]),
    ], reason:
        '⛔one span, one block — and the SECOND one, read after the index: a '
        'reader that pulled the entry would still have returned the right '
        '100 bytes');
    expect(costs.single.storedBytesRead, lessThan(entry.length ~/ 2));
  });

  test('a window straddling a boundary reads both blocks and no third', () {
    if (!engineHere()) {
      markTestSkipped('no engine on this run');
      return;
    }
    final source = sourceOf(mediaBlockBytes * 3 + 1000);
    final (:framed, entry: _, :blocks, :index) = written(source);

    const at = mediaBlockBytes - 50;
    final window = Uint8List(100);
    expect(framed.readIntoSync(window, at, window.length), 100);
    expect(window, Uint8List.sublistView(source, at, at + 100));
    expect(costs, [
      (blocksDecoded: 2, storedBytesRead: index + blocks[0] + blocks[1]),
    ], reason: 'the two it crosses, and not the two it does not');
  });

  test('the whole file comes back byte for byte', () {
    if (!engineHere()) {
      markTestSkipped('no engine on this run');
      return;
    }
    final source = sourceOf(mediaBlockBytes * 2 + 77);
    final (:framed, entry: _, blocks: _, index: _) = written(source);
    expect(framed.lengthSync(), source.length);
    expect(framed.readSync(), source);
  });

  test('a read past the end is short, not a throw and not garbage', () {
    if (!engineHere()) {
      markTestSkipped('no engine on this run');
      return;
    }
    final source = sourceOf(200 * 1024);
    final (:framed, entry: _, blocks: _, index: _) = written(source);
    final window = Uint8List(500);
    expect(framed.readIntoSync(window, source.length - 100, 500), 100);
    expect(
      Uint8List.sublistView(window, 0, 100),
      Uint8List.sublistView(source, source.length - 100),
    );
    expect(framed.readIntoSync(window, source.length, 10), 0);
  });

  test('🚨many small windows through ONE reader decode their block ONCE — '
      'PDFium reads a few hundred bytes at a time', () {
    if (!engineHere()) {
      markTestSkipped('no engine on this run');
      return;
    }
    final source = sourceOf(mediaBlockBytes * 3 + 1000);
    final (:framed, entry: _, :blocks, :index) = written(source);

    final reader = framed.openWindowReader();
    final window = Uint8List(300);
    const first = mediaBlockBytes + 10;
    for (var at = first; at < first + 6000; at += 400) {
      expect(reader.readIntoSync(window, at, window.length), window.length);
      expect(window, Uint8List.sublistView(source, at, at + window.length));
    }
    reader.close();

    expect(costs, [
      (blocksDecoded: 1, storedBytesRead: index + blocks[1]),
    ], reason: 'fifteen windows, one block read and decoded — not fifteen');
  });

  test('a reader reads across the file, and back', () {
    if (!engineHere()) {
      markTestSkipped('no engine on this run');
      return;
    }
    final source = sourceOf(mediaBlockBytes * 2 + 77);
    final (:framed, entry: _, blocks: _, index: _) = written(source);
    final reader = framed.openWindowReader();
    try {
      final window = Uint8List(1000);
      for (final at in [0, mediaBlockBytes - 500, mediaBlockBytes * 2, 0]) {
        final got = reader.readIntoSync(window, at, window.length);
        final expected = Uint8List.sublistView(
          source,
          at,
          (at + window.length).clamp(0, source.length),
        );
        expect(got, expected.length);
        expect(Uint8List.sublistView(window, 0, got), expected);
      }
    } finally {
      reader.close();
    }
  });

  test('⛔the CRC is not offered, because it describes bytes nobody sees', () {
    final framed = MediaFramedBytes(
      const MediaArchiveBytes(
        archivePath: 'C:/work/project.anicel',
        dataOffset: 0,
        length: 64,
        entryCrc32: 0x1234,
        framed: true,
      ),
    );
    expect(
      framed.knownCrc32,
      isNull,
      reason:
          "ZIP's CRC is of the COMPRESSED entry; answering with it would "
          'hand the conform pipeline a checksum of something it never '
          'reads, and that pipeline treats a mismatch as a torn read',
    );
  });

  test('a truncated entry says so rather than returning short data', () {
    if (!engineHere()) {
      markTestSkipped('no engine on this run');
      return;
    }
    final (framed: _, :entry, blocks: _, index: _) = written(
      sourceOf(300 * 1024),
    );
    final cut = '${directory.path}/cut.wav$mediaFramedEntrySuffix';
    File(
      cut,
    ).writeAsBytesSync(Uint8List.sublistView(entry, 0, entry.length - 100));
    expect(
      mediaAppFileSource(cut).readSync,
      throwsA(isA<FormatException>()),
      reason: 'a short block is a broken file, not an empty one',
    );
  });

  test('🚨an entry written at ANOTHER block size still windows correctly', () {
    if (!engineHere()) {
      markTestSkipped('no engine on this run');
      return;
    }
    // 4MB is what this app wrote until the decompression measurement moved
    // [mediaBlockBytes] to 512KB, and those entries live in .anicel files
    // that are already on people's disks. The reader's authority is the
    // ENTRY's header, so this pins that the constant is a writer's default
    // and nothing more.
    const wasBlockBytes = 4 * 1024 * 1024;
    expect(
      wasBlockBytes,
      isNot(mediaBlockBytes),
      reason: 'fixture: the point is that the two disagree',
    );
    final source = sourceOf(wasBlockBytes * 2 + 500);
    final (:framed, entry: _, :blocks, :index) = written(
      source,
      blockBytes: wasBlockBytes,
    );
    expect(blocks, hasLength(3));

    // Deep inside the SECOND block — the offset the current constant would
    // place in block 8.
    const at = wasBlockBytes + 4096;
    final window = Uint8List(256);
    expect(framed.readIntoSync(window, at, window.length), window.length);
    expect(window, Uint8List.sublistView(source, at, at + window.length));
    expect(costs, [
      (blocksDecoded: 1, storedBytesRead: index + blocks[1]),
    ], reason: 'one block, chosen by the size the ENTRY records');
  });

  test('incompressible bytes are stored, so a window into them never comes '
      'here at all', () {
    if (!engineHere()) {
      markTestSkipped('no engine on this run');
      return;
    }
    final random = Random(4);
    final noise = Uint8List.fromList(
      List<int>.generate(128 * 1024, (_) => random.nextInt(256)),
    );
    expect(
      framedEntryBytes(noise),
      isNull,
      reason:
          'a file zstd cannot improve keeps a plain seek — the framed '
          'path is only for entries that actually got smaller',
    );
  });
}

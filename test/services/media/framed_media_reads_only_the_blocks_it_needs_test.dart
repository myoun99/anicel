import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/framed_media_fixture.dart';
import 'package:anicel/src/native/qa_cel_compressor.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/persistence/media_blob_codec.dart';

/// 🚨★★★**A WINDOW MUST STAY A WINDOW.**
///
/// Compressing media whole would buy 38% on audio and cost the ability to
/// read a range — the thing that keeps a hundred-page conte and a
/// three-gigabyte movie off the heap (유저 2026-08-27: 「3기가 영상파일도
/// 볼거라서 결국 그게 그대로 메모리에 올라가면 문제되는데」).
///
/// ⛔So「it round-trips」is not the assertion. These COUNT the bytes the
/// underlying entry was asked for, because a framed reader that quietly
/// pulled the whole entry would round-trip perfectly and have thrown the
/// entire point away.
void main() {
  bool engineHere() {
    final compressor = QaCelCompressor.instance;
    return compressor != null && compressor.isSupported;
  }

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

  test('a window reads only the blocks it lands in', () {
    if (!engineHere()) {
      markTestSkipped('no engine on this run');
      return;
    }
    // Three blocks and a tail.
    final source = sourceOf(mediaBlockBytes * 3 + 1000);
    final entry = framedEntryBytes(source);
    expect(entry, isNotNull, reason: 'fixture: this data compresses');

    final stored = _CountingBytes(entry!);
    final framed = _framed(stored);
    expect(framed.lengthSync(), source.length);

    // The header read is the price of admission; measure from after it.
    framed.header;
    stored.reset();

    // A 100-byte window in the MIDDLE block.
    final at = mediaBlockBytes + 12345;
    final window = Uint8List(100);
    expect(framed.readIntoSync(window, at, window.length), 100);
    expect(window, Uint8List.sublistView(source, at, at + 100));

    final index = framed.header;
    expect(
      stored.bytesRead,
      index.blockLengths[1],
      reason:
          '⛔exactly one block, and the SECOND one — a reader that pulled '
          'the entry would still have returned the right 100 bytes',
    );
    expect(
      stored.bytesRead,
      lessThan(entry.length ~/ 2),
      reason: 'and it is a small fraction of the whole entry',
    );
  });

  test('a window straddling a boundary reads both blocks and no third', () {
    if (!engineHere()) {
      markTestSkipped('no engine on this run');
      return;
    }
    final source = sourceOf(mediaBlockBytes * 3 + 1000);
    final entry = framedEntryBytes(source)!;
    final stored = _CountingBytes(entry);
    final framed = _framed(stored);
    final index = framed.header;
    stored.reset();

    final at = mediaBlockBytes - 50;
    final window = Uint8List(100);
    expect(framed.readIntoSync(window, at, window.length), 100);
    expect(window, Uint8List.sublistView(source, at, at + 100));
    expect(
      stored.bytesRead,
      index.blockLengths[0] + index.blockLengths[1],
      reason: 'the two it crosses, and not the two it does not',
    );
  });

  test('the whole file comes back byte for byte', () {
    if (!engineHere()) {
      markTestSkipped('no engine on this run');
      return;
    }
    final source = sourceOf(mediaBlockBytes * 2 + 77);
    final framed = _framed(_CountingBytes(framedEntryBytes(source)!));
    expect(framed.readSync(), source);
  });

  test('a read past the end is short, not a throw and not garbage', () {
    if (!engineHere()) {
      markTestSkipped('no engine on this run');
      return;
    }
    final source = sourceOf(200 * 1024);
    final framed = _framed(_CountingBytes(framedEntryBytes(source)!));
    final window = Uint8List(500);
    final read = framed.readIntoSync(window, source.length - 100, 500);
    expect(read, 100);
    expect(
      Uint8List.sublistView(window, 0, 100),
      Uint8List.sublistView(source, source.length - 100),
    );
  });

  test('the index is read once, not per window', () {
    if (!engineHere()) {
      markTestSkipped('no engine on this run');
      return;
    }
    final source = sourceOf(mediaBlockBytes * 2 + 10);
    final stored = _CountingBytes(framedEntryBytes(source)!);
    final framed = _framed(stored);
    framed.header;
    final afterFirst = stored.reads;
    framed.header;
    framed.header;
    expect(
      stored.reads,
      afterFirst,
      reason: 'a seek in front of every window is what this class avoids',
    );
  });

  test('⛔the CRC is not offered, because it describes bytes nobody sees', () {
    if (!engineHere()) {
      markTestSkipped('no engine on this run');
      return;
    }
    final framed = _framed(
      _CountingBytes(framedEntryBytes(sourceOf(64 * 1024))!),
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
    final entry = framedEntryBytes(sourceOf(300 * 1024))!;
    final cut = Uint8List.sublistView(entry, 0, entry.length - 100);
    final framed = _framed(_CountingBytes(cut));
    expect(
      () => framed.readSync(),
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
    // and nothing more — mutate [MediaFramedBytes] to divide by
    // `mediaBlockBytes` instead of `index.blockBytes` and only this goes
    // red.
    const wasBlockBytes = 4 * 1024 * 1024;
    expect(
      wasBlockBytes,
      isNot(mediaBlockBytes),
      reason: 'fixture: the point is that the two disagree',
    );
    final source = sourceOf(wasBlockBytes * 2 + 500);
    final entry = framedEntryBytes(source, blockBytes: wasBlockBytes)!;
    expect(MediaBlobHeader.parse(entry).blockBytes, wasBlockBytes);
    expect(MediaBlobHeader.parse(entry).blockCount, 3);

    final stored = _CountingBytes(entry);
    final framed = _framed(stored);
    final index = framed.header;
    stored.reset();

    // Deep inside the LAST full block — the offset the current constant
    // would place in block 16.
    final at = wasBlockBytes + 4096;
    final window = Uint8List(256);
    expect(framed.readIntoSync(window, at, window.length), window.length);
    expect(window, Uint8List.sublistView(source, at, at + window.length));
    expect(
      stored.bytesRead,
      index.blockLengths[1],
      reason: 'one block, chosen by the size the ENTRY records',
    );
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

/// A [MediaByteSource] over bytes in hand that COUNTS what it is asked
/// for.
///
/// 🚨The instrument is the test. Without it every assertion here passes on
/// a reader that pulls the whole entry every time.
class _CountingBytes {
  _CountingBytes(this.bytes);

  final Uint8List bytes;
  int bytesRead = 0;
  int reads = 0;

  void reset() {
    bytesRead = 0;
    reads = 0;
  }

  Uint8List readSync() {
    bytesRead += bytes.length;
    reads += 1;
    return bytes;
  }

  int lengthSync() => bytes.length;

  int readIntoSync(Uint8List buffer, int position, int size) {
    reads += 1;
    if (position >= bytes.length) {
      return 0;
    }
    final end = position + size > bytes.length ? bytes.length : position + size;
    final take = end - position;
    buffer.setRange(0, take, bytes, position);
    bytesRead += take;
    return take;
  }

  bool existsSync() => true;
}

/// The framed reader over a counting stand-in.
MediaFramedBytes _framed(_CountingBytes stored) => MediaFramedBytes.reading(
  readStored: stored.readIntoSync,
  storedExists: stored.existsSync,
);

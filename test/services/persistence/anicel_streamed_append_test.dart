import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

/// Appending media without holding it.
///
/// The incremental writer takes a `Uint8List` per entry, which is right for
/// a cel — small, already deflated, in hand — and wrong for an import that
/// can weigh hundreds of megabytes. That allocation is the one this round
/// already took out of the full-save path; it must not walk back in here.
void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('qa_stream_'));
  tearDown(() {
    try {
      temp.deleteSync(recursive: true);
    } on Object {
      // A locked file on Windows must not fail the suite.
    }
  });

  /// A minimal .anicel with one entry, to append onto.
  String seedArchive() {
    final path = '${temp.path}/scene.anicel';
    writeAnicelArchiveFile(
      path: path,
      entries: [
        (name: 'project.json', bytes: Uint8List.fromList(const [123, 125])),
      ],
    );
    return path;
  }

  String writeSource(String name, int length) {
    final path = '${temp.path}/$name';
    File(path).writeAsBytesSync(
      Uint8List.fromList(List<int>.generate(length, (i) => i % 251)),
    );
    return path;
  }

  test('a streamed entry lands byte-for-byte, and a standard tool reads it',
      () {
    // The whole point of STORE'd entries: what goes in is what comes out,
    // and an unzip tool can get at it without knowing anything about us.
    final archive = seedArchive();
    final source = writeSource('bgm.wav', 700 * 1024);
    final expected = File(source).readAsBytesSync();
    final entryName = anicelMediaEntryName(source);

    appendAnicelEntries(
      path: archive,
      newEntries: const {},
      streamedEntries: [
        AnicelStreamedEntry(
          name: entryName,
          length: expected.length,
          readInto: MediaFileBytes(source).readIntoSync,
        ),
      ],
    );

    final decoded = ZipDecoder().decodeBytes(File(archive).readAsBytesSync());
    final found = decoded.files.firstWhere((f) => f.name == entryName);
    expect(found.content, expected);
  });

  test('the layout it reports points at the real bytes', () {
    // What an archive-backed source is built from. Wrong by one and the
    // project plays a window of whatever sits next to its audio.
    final archive = seedArchive();
    final source = writeSource('voice.wav', 300 * 1024);
    final expected = File(source).readAsBytesSync();
    final entryName = anicelMediaEntryName(source);

    final layout = appendAnicelEntries(
      path: archive,
      newEntries: const {},
      streamedEntries: [
        AnicelStreamedEntry(
          name: entryName,
          length: expected.length,
          readInto: MediaFileBytes(source).readIntoSync,
        ),
      ],
    );

    final entry = layout.entryNamed(entryName)!;
    final read = MediaArchiveBytes(
      archivePath: archive,
      dataOffset: entry.dataOffset,
      length: entry.length,
      entryCrc32: entry.crc32,
    ).readSync();
    expect(read, expected);
    expect(entry.crc32, anicelCrc32(expected));
  });

  test('it never holds more than a chunk, whatever the asset weighs', () {
    // The reason this exists. The reads are counted: a writer that pulled
    // the file in one go would ask once for everything.
    final archive = seedArchive();
    const length = 4 * 1024 * 1024;
    final source = writeSource('big.wav', length);
    var largestRequest = 0;
    final reader = MediaFileBytes(source);

    appendAnicelEntries(
      path: archive,
      newEntries: const {},
      streamedEntries: [
        AnicelStreamedEntry(
          name: 'media/big',
          length: length,
          readInto: (buffer, position, size) {
            largestRequest = size > largestRequest ? size : largestRequest;
            return reader.readIntoSync(buffer, position, size);
          },
        ),
      ],
    );

    expect(largestRequest, lessThanOrEqualTo(256 * 1024));
    expect(largestRequest, lessThan(length));
  });

  test('cel entries and media entries append together', () {
    // A save carries both, and the offsets have to agree afterwards.
    final archive = seedArchive();
    final source = writeSource('a.wav', 1024);
    final expected = File(source).readAsBytesSync();

    final layout = appendAnicelEntries(
      path: archive,
      newEntries: {'cels/x.celz': Uint8List.fromList(const [1, 2, 3, 4, 5])},
      streamedEntries: [
        AnicelStreamedEntry(
          name: 'media/a',
          length: expected.length,
          readInto: MediaFileBytes(source).readIntoSync,
        ),
      ],
    );

    final cel = layout.entryNamed('cels/x.celz')!;
    final media = layout.entryNamed('media/a')!;
    expect(cel.length, 5);
    expect(media.length, expected.length);
    final decoded = ZipDecoder().decodeBytes(File(archive).readAsBytesSync());
    expect(
      decoded.files.firstWhere((f) => f.name == 'cels/x.celz').content,
      [1, 2, 3, 4, 5],
    );
    expect(decoded.files.firstWhere((f) => f.name == 'media/a').content,
        expected);
  });

  test('a source that ends early throws BEFORE the archive is touched', () {
    // A truncated or vanished source must not cost the project its file:
    // the append truncates at the old central directory to begin writing,
    // so discovering the problem afterwards would leave a torn archive.
    final archive = seedArchive();
    final before = File(archive).readAsBytesSync();

    expect(
      () => appendAnicelEntries(
        path: archive,
        newEntries: const {},
        streamedEntries: [
          AnicelStreamedEntry(
            name: 'media/liar',
            length: 4096,
            readInto: (buffer, position, size) => position == 0 ? 10 : 0,
          ),
        ],
      ),
      throwsStateError,
    );
    expect(File(archive).readAsBytesSync(), before,
        reason: 'the archive is exactly as it was');
  });

  group('a full rewrite', () {
    test('streams media through and a standard tool still reads it', () {
      // The full path writes into a temp nobody has yet, so it can afford
      // to patch the header's CRC after the bytes go by rather than pay a
      // second pass over every asset. Get that seek wrong and the archive
      // is quietly rejected by anything but us.
      final path = '${temp.path}/full.anicel';
      final source = writeSource('score.wav', 900 * 1024);
      final expected = File(source).readAsBytesSync();

      final layout = writeAnicelArchiveFile(
        path: path,
        entries: [
          (name: 'project.json', bytes: Uint8List.fromList(const [123, 125])),
          (name: 'cels/a.celz', bytes: Uint8List.fromList(const [7, 7, 7])),
        ],
        streamedEntries: [
          AnicelStreamedEntry(
            name: 'media/score',
            length: expected.length,
            readInto: MediaFileBytes(source).readIntoSync,
          ),
        ],
      );

      final decoded = ZipDecoder().decodeBytes(File(path).readAsBytesSync());
      expect(
        decoded.files.firstWhere((f) => f.name == 'media/score').content,
        expected,
      );
      expect(
        decoded.files.firstWhere((f) => f.name == 'cels/a.celz').content,
        [7, 7, 7],
      );

      // The CRC that landed in the header is the real one, in both places
      // ZIP records it.
      final entry = layout.entryNamed('media/score')!;
      expect(entry.crc32, anicelCrc32(expected));
      final bytes = File(path).readAsBytesSync();
      final header = ByteData.sublistView(bytes);
      expect(
        header.getUint32(entry.localHeaderOffset + 14, Endian.little),
        anicelCrc32(expected),
        reason: 'the patched local header, not just the central directory',
      );
      // And our own reader agrees about where the bytes are.
      expect(
        MediaArchiveBytes(
          archivePath: path,
          dataOffset: entry.dataOffset,
          length: entry.length,
        ).readSync(),
        expected,
      );
    });

    test('several media entries keep their own offsets', () {
      final path = '${temp.path}/many.anicel';
      final a = writeSource('a.wav', 5000);
      final b = writeSource('b.wav', 9000);

      final layout = writeAnicelArchiveFile(
        path: path,
        entries: [
          (name: 'project.json', bytes: Uint8List.fromList(const [123, 125])),
        ],
        streamedEntries: [
          AnicelStreamedEntry(
            name: 'media/a',
            length: 5000,
            readInto: MediaFileBytes(a).readIntoSync,
          ),
          AnicelStreamedEntry(
            name: 'media/b',
            length: 9000,
            readInto: MediaFileBytes(b).readIntoSync,
          ),
        ],
      );

      expect(
        MediaArchiveBytes(
          archivePath: path,
          dataOffset: layout.entryNamed('media/a')!.dataOffset,
          length: 5000,
        ).readSync(),
        File(a).readAsBytesSync(),
      );
      expect(
        MediaArchiveBytes(
          archivePath: path,
          dataOffset: layout.entryNamed('media/b')!.dataOffset,
          length: 9000,
        ).readSync(),
        File(b).readAsBytesSync(),
      );
    });

    test('media can come FROM an archive — which is what save-as does', () {
      // Save-as streams a clean cel out of the old file into the new one.
      // Media rides the same road: nothing is re-encoded, and the source
      // being an archive rather than a file changes nothing here.
      final first = '${temp.path}/first.anicel';
      final source = writeSource('voice.wav', 4096);
      final expected = File(source).readAsBytesSync();
      final one = writeAnicelArchiveFile(
        path: first,
        entries: [
          (name: 'project.json', bytes: Uint8List.fromList(const [123, 125])),
        ],
        streamedEntries: [
          AnicelStreamedEntry(
            name: 'media/v',
            length: expected.length,
            readInto: MediaFileBytes(source).readIntoSync,
          ),
        ],
      );

      final inFirst = one.entryNamed('media/v')!;
      final second = '${temp.path}/second.anicel';
      final two = writeAnicelArchiveFile(
        path: second,
        entries: [
          (name: 'project.json', bytes: Uint8List.fromList(const [123, 125])),
        ],
        streamedEntries: [
          AnicelStreamedEntry(
            name: 'media/v',
            length: inFirst.length,
            readInto: MediaArchiveBytes(
              archivePath: first,
              dataOffset: inFirst.dataOffset,
              length: inFirst.length,
            ).readIntoSync,
          ),
        ],
      );

      expect(
        MediaArchiveBytes(
          archivePath: second,
          dataOffset: two.entryNamed('media/v')!.dataOffset,
          length: expected.length,
        ).readSync(),
        expected,
      );
    });
  });

  test('appending the same media name replaces it rather than doubling it',
      () {
    // Shadowing by name, the same rule cels live by — a re-import of the
    // same asset must not leave two live entries claiming one path.
    final archive = seedArchive();
    final first = writeSource('one.wav', 512);
    final second = writeSource('two.wav', 900);

    appendAnicelEntries(
      path: archive,
      newEntries: const {},
      streamedEntries: [
        AnicelStreamedEntry(
          name: 'media/same',
          length: 512,
          readInto: MediaFileBytes(first).readIntoSync,
        ),
      ],
    );
    final layout = appendAnicelEntries(
      path: archive,
      newEntries: const {},
      streamedEntries: [
        AnicelStreamedEntry(
          name: 'media/same',
          length: 900,
          readInto: MediaFileBytes(second).readIntoSync,
        ),
      ],
    );

    expect(layout.entries.where((e) => e.name == 'media/same'), hasLength(1));
    expect(layout.entryNamed('media/same')!.length, 900);
    final decoded = ZipDecoder().decodeBytes(File(archive).readAsBytesSync());
    expect(
      decoded.files.firstWhere((f) => f.name == 'media/same').content,
      File(second).readAsBytesSync(),
    );
  });
}

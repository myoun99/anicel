import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';

/// 🚨ONE PARSE, TWO BYTE SOURCES.
///
/// [parseAnicelZipLayout] holds the archive in memory;
/// [parseAnicelZipLayoutFile] seeks a multi-gigabyte project's tail. That
/// is the ONLY difference they are allowed to have — every offset, length
/// and CRC they report must be the same number, because the appender
/// writes at the offset one of them reported and the media layer reads at
/// the offset the other did.
///
/// ⛔They used to be two hand-written copies of the same EOCD scan, ZIP64
/// end record and central-directory walk, and they HAD drifted: only the
/// file one bounded the central directory at the ZIP64 record. This test
/// is what says they cannot drift again.
void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('qa_zip_two_sources_');
  });

  tearDown(() {
    try {
      temp.deleteSync(recursive: true);
    } on Object {
      // Windows handles.
    }
  });

  /// Every field of every entry, in order — an equality that fails on a
  /// single wrong offset rather than on a count.
  List<({String name, int header, int data, int length, int crc})> shapeOf(
    AnicelZipLayout layout,
  ) => [
    for (final entry in layout.entries)
      (
        name: entry.name,
        header: entry.localHeaderOffset,
        data: entry.dataOffset,
        length: entry.length,
        crc: entry.crc32,
      ),
  ];

  /// Names long enough that the per-entry local-header read (the four
  /// bytes at +26, the one thing the two sources fetch differently) has a
  /// different answer per entry.
  Iterable<({String name, Uint8List bytes})> entriesOf(int count) sync* {
    for (var i = 0; i < count; i += 1) {
      yield (
        name: 'cels/${'n' * i}$i.celz',
        bytes: Uint8List.fromList(List<int>.filled(7 + i, i)),
      );
    }
  }

  void expectBothSourcesAgree(String fileName) {
    final path = '${temp.path}/$fileName';
    writeAnicelArchiveFile(path: path, entries: entriesOf(5));
    final bytes = File(path).readAsBytesSync();

    final fromBytes = parseAnicelZipLayout(bytes);
    final fromFile = parseAnicelZipLayoutFile(path);

    expect(shapeOf(fromBytes), shapeOf(fromFile));
    expect(fromBytes.centralDirectoryOffset, fromFile.centralDirectoryOffset);
    expect(fromBytes.entries, hasLength(5));
    // The offsets are real: the bytes at dataOffset are the entry's own.
    for (final entry in fromBytes.entries) {
      expect(
        bytes.sublist(entry.dataOffset, entry.dataOffset + entry.length),
        List<int>.filled(entry.length, entry.length - 7),
        reason: entry.name,
      );
    }
  }

  test('a ZIP64 archive reads the same from memory as from the file', () {
    anicelAlwaysZip64 = true;
    expectBothSourcesAgree('zip64.anicel');
  });

  test('a plain-EOCD archive reads the same from memory as from the '
      'file', () {
    anicelAlwaysZip64 = false;
    expectBothSourcesAgree('plain.anicel');
  });
}

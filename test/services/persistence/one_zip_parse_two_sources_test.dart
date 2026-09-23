import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';
import '../../helpers/temp_dir.dart';

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

  tearDown(() => deleteTempQuietly(temp));

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

  /// Names of different lengths, so the per-entry local-header read (the
  /// four bytes at +26, the one thing the two sources fetch differently)
  /// has a different answer per entry. [payload] is the first entry's byte
  /// count; each later one is one byte longer, so an entry's own length
  /// says which entry it is.
  Iterable<({String name, Uint8List bytes})> entriesOf(
    int count, {
    required int payload,
  }) sync* {
    for (var i = 0; i < count; i += 1) {
      yield (
        name: 'cels/${'n' * i}$i.celz',
        bytes: Uint8List.fromList(List<int>.filled(payload + i, i)),
      );
    }
  }

  void expectBothSourcesAgree(String fileName, {int payload = 7}) {
    final path = '${temp.path}/$fileName';
    writeAnicelArchiveFile(
      path: path,
      entries: entriesOf(5, payload: payload),
    );
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
        List<int>.filled(entry.length, entry.length - payload),
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

  test('an entry past the field limit carries a local EXTRA field, and '
      'both sources step over it', () {
    // ⛔A LOCAL HEADER IS 30 BYTES PLUS ITS NAME PLUS ITS EXTRA. Every
    // archive this app writes at shipped settings has an empty extra, so
    // only an entry past [anicelZip64FieldLimit] — where the spec makes
    // the local header carry BOTH sizes — proves the walk adds the extra
    // length as well as the name length. Without this the data offsets
    // land 20 bytes early and every cel reads as its own ZIP64 field.
    anicelAlwaysZip64 = true;
    anicelZip64FieldLimit = 64;
    addTearDown(() => anicelZip64FieldLimit = anicelZip64FieldLimitShipped);
    expectBothSourcesAgree('zip64-extra.anicel', payload: 64);
  });
}

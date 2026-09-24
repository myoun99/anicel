import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';
import '../../helpers/temp_dir.dart';

/// 🚨★★★A CORRUPT CENTRAL DIRECTORY IS A [FormatException], NEVER A
/// [RangeError].
///
/// Both parsers' bounds checks exist for exactly one reason: every caller
/// that opens or appends catches `FormatException` and recovers by walking
/// the local headers instead. A RangeError escaping those catches turns a
/// salvageable project into one that refuses to open — which is the bug the
/// checks were added for.
///
/// ⛔The mutation campaign found all four bounds SURVIVING (2026-09-04): the
/// suite built only well-formed archives, so nothing ever reached a check.
/// Each case below turns one guard's own mutant red.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anicel-central');
  });

  tearDown(() => deleteTempQuietly(directory));

  /// A small, valid archive to damage.
  String archiveAt(String name, {int entries = 3, String? comment}) {
    final path = '${directory.path}/$name';
    writeAnicelArchiveFile(
      path: path,
      entries: [
        for (var i = 0; i < entries; i += 1)
          (
            name: 'entry$i.bin',
            bytes: Uint8List.fromList(List<int>.filled(64, i)),
          ),
      ],
    );
    return path;
  }

  /// The offset of the first central-directory record, read from the file's
  /// own layout so the damage lands where the parser will look.
  int centralOffsetOf(String path) =>
      parseAnicelZipLayoutFile(path).centralDirectoryOffset;

  Uint8List bytesOf(String path) => File(path).readAsBytesSync();

  void writeBytes(String path, Uint8List bytes) =>
      File(path).writeAsBytesSync(bytes);

  test('a record whose name length runs past the directory is a '
      'FormatException, not a RangeError', () {
    final path = archiveAt('nameLength.anicel');
    final central = centralOffsetOf(path);
    final bytes = bytesOf(path);
    // Central record layout: the name length sits at +28. A huge one makes
    // every following read run off the end.
    final data = ByteData.sublistView(bytes);
    data.setUint16(central + 28, 0xFFFF, Endian.little);
    writeBytes(path, bytes);

    expect(() => parseAnicelZipLayout(bytes), throwsFormatException);
    expect(() => parseAnicelZipLayoutFile(path), throwsFormatException);
  });

  test('a record whose local offset points past the file is a '
      'FormatException, not a RangeError', () {
    final path = archiveAt('localOffset.anicel');
    final central = centralOffsetOf(path);
    final bytes = bytesOf(path);
    // The local header offset sits at +42 of the central record.
    final data = ByteData.sublistView(bytes);
    data.setUint32(central + 42, 0x7FFFFFF0, Endian.little);
    writeBytes(path, bytes);

    expect(() => parseAnicelZipLayout(bytes), throwsFormatException);
    expect(() => parseAnicelZipLayoutFile(path), throwsFormatException);
  });

  test('a truncated final record is a FormatException, not a RangeError', () {
    final path = archiveAt('short.anicel');
    final bytes = bytesOf(path);
    final central = centralOffsetOf(path);
    // Keep the EOCD (so the parse gets as far as the records) but leave the
    // last record without its fixed 46 bytes: copy the tail 22 bytes back
    // over the middle of the final record.
    final eocd = bytes.length - 22;
    final cut = central + 20;
    final damaged = Uint8List(cut + 22)
      ..setRange(0, cut, bytes)
      ..setRange(cut, cut + 22, bytes.sublist(eocd));
    final shortPath = '${directory.path}/short-cut.anicel';
    writeBytes(shortPath, damaged);

    expect(() => parseAnicelZipLayout(damaged), throwsFormatException);
    expect(() => parseAnicelZipLayoutFile(shortPath), throwsFormatException);
  });

  test('a record carrying a comment still leads to the next one', () {
    // ⛔The walk adds the comment length to reach the following record. A
    // walk that forgets it lands mid-record and the whole directory reads
    // as corrupt — but only when a comment EXISTS, and this app's writer
    // emits none (유저 2026-08-26 「zip64로 통일화」: every archive it writes
    // is ZIP64 with empty comments). So the archive is grown here by hand,
    // which means moving the ZIP64 records the splice pushed along too.
    final path = archiveAt('comment.anicel', entries: 2);
    final bytes = bytesOf(path);
    final central = centralOffsetOf(path);
    final data = ByteData.sublistView(bytes);
    final nameLength = data.getUint16(central + 28, Endian.little);
    final extraLength = data.getUint16(central + 30, Endian.little);
    final recordEnd = central + 46 + nameLength + extraLength;
    const comment = 'anicel';
    final grown = Uint8List(bytes.length + comment.length)
      ..setRange(0, recordEnd, bytes)
      ..setRange(recordEnd, recordEnd + comment.length, comment.codeUnits)
      ..setRange(
        recordEnd + comment.length,
        bytes.length + comment.length,
        bytes.sublist(recordEnd),
      );
    final grownData = ByteData.sublistView(grown);
    grownData.setUint16(central + 32, comment.length, Endian.little);

    // The plain EOCD's central-directory size.
    final eocd = grown.length - 22;
    grownData.setUint32(
      eocd + 12,
      grownData.getUint32(eocd + 12, Endian.little) + comment.length,
      Endian.little,
    );
    // The ZIP64 locator sits in the 20 bytes before it and points at the
    // ZIP64 end record, which the splice pushed along by the same amount.
    final locator = eocd - 20;
    final zip64End =
        grownData.getUint64(locator + 8, Endian.little) + comment.length;
    grownData.setUint64(locator + 8, zip64End, Endian.little);
    // And that record states the directory's size as well.
    grownData.setUint64(
      zip64End + 40,
      grownData.getUint64(zip64End + 40, Endian.little) + comment.length,
      Endian.little,
    );

    final commented = '${directory.path}/comment-grown.anicel';
    writeBytes(commented, grown);

    expect(
      parseAnicelZipLayout(grown).entries.map((e) => e.name),
      ['entry0.bin', 'entry1.bin'],
      reason:
          'the walk must step over the comment to land on the second '
          'record, not inside the first',
    );
    expect(
      parseAnicelZipLayoutFile(commented).entries.map((e) => e.name),
      ['entry0.bin', 'entry1.bin'],
      reason: 'and the streaming walk reads the same directory',
    );
  });

  test('a record overrunning the ZIP64 central directory is a '
      'FormatException in BOTH parsers', () {
    // ⛔THE DIRECTORY ENDS AT THE ZIP64 RECORD, NOT AT THE EOCD. Between
    // them sit the ZIP64 end record and its locator — 76 bytes a record
    // may not grow into. Bounding at the EOCD instead hands the walk 76
    // bytes of slack, so an overrun this size reads as well-formed.
    //
    // 🚨This is the bound the in-memory parser SILENTLY LACKED while the
    // two parsers were two hand-written copies (found 2026-09-05, when
    // they became one). Both are asserted here so neither can lose it.
    final path = archiveAt('zip64Overrun.anicel', entries: 2);
    final bytes = bytesOf(path);
    final central = centralOffsetOf(path);
    final data = ByteData.sublistView(bytes);
    // Step over the first record to reach the last one — only the LAST
    // record can overrun the directory without also landing the walk on a
    // wrong signature, which every parser refuses anyway.
    final last =
        central +
        46 +
        data.getUint16(central + 28, Endian.little) +
        data.getUint16(central + 30, Endian.little) +
        data.getUint16(central + 32, Endian.little);
    expect(
      data.getUint32(last, Endian.little),
      0x02014b50,
      reason: 'the walk above must land on the second central record',
    );
    // A comment 30 bytes long: past the ZIP64 directory end, short of the
    // EOCD, so ONLY the correct bound rejects it.
    data.setUint16(last + 32, 30, Endian.little);
    writeBytes(path, bytes);

    expect(() => parseAnicelZipLayout(bytes), throwsFormatException);
    expect(() => parseAnicelZipLayoutFile(path), throwsFormatException);
  });
}

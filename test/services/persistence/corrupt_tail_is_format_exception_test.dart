import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';
import '../../helpers/temp_dir.dart';

/// Corruption behind a SURVIVING EOCD must fall out as the FormatException
/// the callers catch — their `on FormatException` IS the recovery.
///
/// A torn tail (no EOCD) always threw the right type; a garbage length or
/// offset behind a valid EOCD (out-of-order page writeback on power loss,
/// external corruption, a half-synced cloud file) threw RangeError or
/// IndexError instead, escaped both production fallbacks, and turned a
/// file the local-header walk could fully salvage into one that refused
/// to open with a raw error.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anicel-corrupt');
  });

  tearDown(() => deleteTempQuietly(directory));

  (String, AnicelZipLayout) builtArchive() {
    final path = '${directory.path}/f.anicel';
    writeAnicelArchiveFile(
      path: path,
      entries: [
        (name: 'project.json', bytes: Uint8List.fromList(List.filled(40, 7))),
        (name: 'cels/a.celz', bytes: Uint8List.fromList(List.filled(64, 9))),
      ],
    );
    return (path, parseAnicelZipLayoutFile(path));
  }

  void stompUint16At(String path, int offset, int value) {
    final raf = File(path).openSync(mode: FileMode.append);
    try {
      raf.setPositionSync(offset);
      raf.writeFromSync(
        (ByteData(2)..setUint16(0, value, Endian.little)).buffer.asUint8List(),
      );
    } finally {
      raf.closeSync();
    }
  }

  void stompUint32At(String path, int offset, int value) {
    final raf = File(path).openSync(mode: FileMode.append);
    try {
      raf.setPositionSync(offset);
      raf.writeFromSync(
        (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List(),
      );
    } finally {
      raf.closeSync();
    }
  }

  test('a garbage name length in a central record is a FormatException, '
      'and the walk still salvages every entry', () {
    final (path, healthy) = builtArchive();
    // First central record's nameLength field sits at +28.
    stompUint16At(path, healthy.centralDirectoryOffset + 28, 0xFFF0);

    expect(() => parseAnicelZipLayoutFile(path), throwsFormatException);
    expect(
      {for (final e in recoverAnicelZipLayoutFile(path).entries) e.name},
      {for (final e in healthy.entries) e.name},
      reason: 'the file was salvageable all along — which is why the '
          'wrong exception type mattered',
    );
  });

  test('a local-header offset pointing beyond EOF is a FormatException',
      () {
    final (path, healthy) = builtArchive();
    // First central record's local-header offset field sits at +42.
    stompUint32At(path, healthy.centralDirectoryOffset + 42, 0x00FFFF00);

    expect(() => parseAnicelZipLayoutFile(path), throwsFormatException);
  });

  test('the in-memory parser answers the same way', () {
    final (path, healthy) = builtArchive();
    stompUint16At(path, healthy.centralDirectoryOffset + 28, 0xFFF0);

    expect(
      () => parseAnicelZipLayout(File(path).readAsBytesSync()),
      throwsFormatException,
    );
  });
}

import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/core/on_a_worker.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/temp_dir.dart';

/// F-608-Q2 (유저 2026-11-17: 「내려받는중에 퍼센테이지가 조금이라도
/// 안느는게 문제」): a picture the import window places is read whole, and
/// one in the cloud comes down inside that read — so the read tells how
/// much of it is in, a piece at a time, off the screen's isolate.
void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('qa_whole_read_'));
  tearDown(() => deleteTempQuietly(temp));

  const mb = 1 << 20;

  /// [length] bytes, each its place's low byte.
  Uint8List counting(int length) =>
      Uint8List.fromList(List<int>.generate(length, (i) => i & 0xff));

  /// A file of [bytes].
  String fileOf(List<int> bytes) =>
      (File('${temp.path}/picture.bin')..writeAsBytesSync(bytes)).path;

  test('🎯a whole read tells how much is in — none, after each piece, all '
      'of it — and hands back every byte where it stands', () {
    const length = 9 * mb + 5;
    final told = <double>[];

    final bytes = MediaFileBytes(
      fileOf(counting(length)),
    ).readSync(onRead: told.add);

    expect(told, [0, 4 * mb / length, 8 * mb / length, 1]);
    expect(bytes, counting(length));
  });

  test('an archive\'s entry is read from its own place, a piece at a '
      'time', () {
    const length = 5 * mb;
    final told = <double>[];
    final source = MediaArchiveBytes(
      archivePath: fileOf([
        ...List<int>.filled(37, 0xAA),
        ...counting(length),
        ...List<int>.filled(41, 0xBB),
      ]),
      dataOffset: 37,
      length: length,
    );

    final bytes = source.readSync(onRead: told.add);

    expect(told, [0, 4 * mb / length, 1]);
    expect(bytes, counting(length));
  });

  test('an entry the file ends inside is a read error, never short '
      'bytes', () {
    final source = MediaArchiveBytes(
      archivePath: fileOf(counting(120)),
      dataOffset: 20,
      length: 200,
    );

    expect(source.readSync, throwsA(isA<FileSystemException>()));
  });

  test('on the road production takes — a worker of its own — the read '
      'crosses and its bar is heard', () async {
    debugWorkersRunHere = false;
    addTearDown(() => debugWorkersRunHere = true);
    const length = 9 * mb;
    final told = <double>[];

    final bytes = await MediaFileBytes(
      fileOf(counting(length)),
    ).read(onRead: told.add);

    expect(bytes, counting(length));
    expect(told, isNotEmpty);
    expect(told.first, 0);
    for (var i = 1; i < told.length; i += 1) {
      expect(told[i], greaterThan(told[i - 1]));
    }
  });
}

import 'dart:io';

import 'package:anicel/src/services/persistence/failed_save_copies.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/temp_dir.dart';

/// The list 「실패본 백업…」 offers, and the copy a backup is.
///
/// 🗣️유저 2026-09-23 (whole-write-temp-beside-the-file): 「해당파일
/// 지정해서 백업할수있게」.
void main() {
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('anicel-failed-copies');
  });

  tearDown(() => deleteTempQuietly(folder));

  String standing(String name) {
    final path = '${folder.path.replaceAll('\\', '/')}/$name';
    File(path).writeAsStringSync(name);
    return path;
  }

  test('the copies still standing, the newest first — one no longer there '
      'is not offered', () {
    final copies = FailedSaveCopies();
    final older = standing('older.anicel');
    final newer = standing('newer.anicel');
    copies.record(older, '/work/older.anicel');
    sleep(const Duration(milliseconds: 20));
    copies.record(newer, '/work/newer.anicel');

    expect(copies.entries.map((e) => e.copyPath), [newer, older]);

    File(older).deleteSync();
    expect(copies.entries.map((e) => e.copyPath), [newer]);
  });

  test('a copy whose project took a save is neither offered nor named', () {
    final copies = FailedSaveCopies();
    final copy = standing('take.anicel');
    copies.record(copy, '/work/take.anicel');
    expect(copies.projectOf(copy), '/work/take.anicel');

    copies.forget(copy);

    expect(copies.entries, isEmpty);
    expect(copies.projectOf(copy), isNull);
  });

  test('a backup the destination refuses leaves nothing beside it', () async {
    final copy = standing('take.anicel');
    final destination = '${folder.path.replaceAll('\\', '/')}/kept.anicel';
    Directory(destination).createSync();

    await expectLater(
      FailedSaveCopies.copyWhole(copy, destination),
      throwsA(isA<FileSystemException>()),
    );

    expect(
      [
        for (final entity in folder.listSync())
          if (entity.path.replaceAll('\\', '/').startsWith(
            '$destination.tmp-',
          ))
            entity.path,
      ],
      isEmpty,
    );
    expect(Directory(destination).existsSync(), isTrue);
  });
}

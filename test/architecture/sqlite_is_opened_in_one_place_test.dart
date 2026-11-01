import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨**THE APP OPENS AN SQLITE FILE IN ONE PLACE** — `readSqliteBytes`
/// (board `three-readers-copy-an-sqlite-file-their-own-way`, 2026-10-31).
///
/// The brush files, the `.clip` door and the shortcut files each took bytes
/// to a copy of their own, opened it read-only and removed it — three
/// spellings of one walk. Every copy reads as well as the next, so the
/// ratchet is a source scan.
void main() {
  const seat = 'lib/src/services/persistence/sqlite_bytes.dart';
  const open = 'sqlite3.open(';

  test('premise: the seat is where it opens', () {
    expect(File(seat).readAsStringSync(), contains(open));
  });

  test('nothing else opens one', () {
    expect(
      [
        for (final file in dartFilesUnder('lib'))
          if (file.path.replaceAll(r'\', '/') != seat &&
              file.readAsStringSync().contains(open))
            file.path,
      ],
      isEmpty,
      reason: 'read it through readSqliteBytes',
    );
  });
}

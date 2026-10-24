import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// [read] over the SQLite database [bytes] hold: opened read-only from a
/// copy in a folder of its own under the system's temp, which goes again
/// once [read] has answered. The reader needs a file, and it is never the
/// user's — a file read in place can be locked by its program, or written.
///
/// ⚠️Sync on purpose: async `dart:io` never completes under the widget-test
/// clock, and all a reader does here is query.
///
/// ↩️Two readers still copy on their own — the brush library's `.sut` and
/// `readClipDocument`'s embedded database. The third, the shortcut files
/// (I-107), came here first; the board card
/// `three-readers-copy-an-sqlite-file-their-own-way` asks their owners to
/// move onto this one.
T readSqliteBytes<T>(List<int> bytes, T Function(Database database) read) {
  final folder = Directory.systemTemp.createTempSync('anicel_sqlite');
  try {
    final copy = File('${folder.path}/copy.db')
      ..writeAsBytesSync(bytes, flush: true);
    final database = sqlite3.open(copy.path, mode: OpenMode.readOnly);
    try {
      return read(database);
    } finally {
      database.close();
    }
  } finally {
    try {
      folder.deleteSync(recursive: true);
    } on FileSystemException {
      // Held for a moment by a scanner: the system's temp is swept anyway,
      // and a read that answered must not be turned into a failure.
    }
  }
}

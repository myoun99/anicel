import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// [read] over the SQLite database [bytes] hold: opened read-only from a
/// copy in a folder of its own under [within] — the system's temp unless
/// the reader keeps its copies in a room of its own — which goes again
/// once [read] has answered. The reader needs a file, and it is never the
/// user's — a file read in place can be locked by its program, or written.
///
/// [within] is the `.clip` door's: its copy waits in this run's room
/// (`SessionScratch.volatileFolder`), which goes with the run even when the
/// run ends without saying goodbye — a large file's database is tens of
/// megabytes (2026-10-08, the door's first landing). The room is named by
/// the caller, never found here: the door reads on a worker, and a worker
/// asking for the room would build and lock it a second time — the lock
/// `SessionScratch` holds is the isolate's own.
///
/// ⚠️Sync on purpose: async `dart:io` never completes under the widget-test
/// clock, and all a reader does here is query.
///
/// ↩️One reader still copies on its own — the brush library's `.sut`. The
/// shortcut files (I-107) came here first and `readClipDocument` moved here
/// (2026-10-30); the board card `three-readers-copy-an-sqlite-file-their-
/// own-way` asks the brush library's owner to follow.
T readSqliteBytes<T>(
  List<int> bytes,
  T Function(Database database) read, {
  Directory? within,
}) {
  final folder = (within ?? Directory.systemTemp).createTempSync(
    'anicel_sqlite',
  );
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

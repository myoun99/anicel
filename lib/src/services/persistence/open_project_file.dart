import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// The project file, held OPEN for as long as the session reads from it.
///
/// 🚨★★★**WHY: DELETING THE PROJECT FILE USED TO DELETE THE WORK.** After a
/// save, a clean cel drops its RAM and keeps only `{path, offset, length}`
/// — the `.anicel` is the cold tier. So the user's own output file is also
/// the app's backing store, and moving it to the desktop mid-session left
/// the session with nothing to read. 유저 2026-08-31: 「이 문제 발생시
/// 해결법이 없기때문」, and it had already cost 94 drawings.
///
/// Holding the file open is what turns that from a loss into a refusal.
/// **Measured on Windows** (2026-09-07, all four with a read handle open):
///
/// | | |
/// |---|---|
/// | delete the file | **blocked** (`PathAccessException`) |
/// | move/rename it | **blocked** |
/// | our own incremental append | **works** |
/// | our own whole-file rewrite in place | **works** |
///
/// ⇒ Windows gives the guarantee as 「you cannot take it away」. POSIX gives
/// it as 「`unlink` only removes the name; the bytes live while a descriptor
/// does」 — the session survives either way, but on POSIX **closing the app
/// is then the moment the file really goes**, which is why losing the file
/// has to be caught before shutdown rather than at it.
///
/// 🚨★★★**AND THE FOURTH MEASUREMENT IS WHY THIS CLASS HAS A `release`.**
/// A full save and a compaction do not write in place — they build a temp
/// file and `rename` it onto the project path, and **renaming ONTO a file
/// this process holds open is blocked too**. Left alone, a session-long
/// handle would break every full save on Windows, and it would look exactly
/// like the foreign lock `_renameWithRetry` already retries for. So the one
/// funnel that replaces the project file lets go of ours first.
///
/// ⚠️Letting go is cheap and needs no bookkeeping: the next read opens it
/// again. There is nothing to restore.
class OpenProjectFile {
  OpenProjectFile._();

  /// One per process, because one project is open at a time — the same
  /// shape the native decoder's single document has.
  static final OpenProjectFile instance = OpenProjectFile._();

  String? _path;
  RandomAccessFile? _handle;

  /// How many times a read had to open the file.
  ///
  /// 🚨★★★**BECAUSE 「IT STILL WORKS」 CANNOT SEE THIS CLASS.** Opening per
  /// read and holding one open return the same bytes; what separates them is
  /// how many times the file was opened, and nothing else in the app can
  /// tell. A test that only checked the bytes would pass with the whole
  /// thing deleted.
  static int debugOpens = 0;

  /// [length] bytes of [path] from [offset], through a handle kept for next
  /// time.
  ///
  /// ⚠️Sequential by nature — the callers are the session's cel stores on
  /// one isolate. A second reader would need its own handle, not a share of
  /// this one, and there is no such caller.
  ///
  /// 🚨★★★**A FAILED READ DROPS THE HANDLE AND TRIES ONCE MORE, BECAUSE
  /// OTHERWISE THIS CLASS TURNS A BAD MOMENT INTO A BAD SESSION.** Opening
  /// per read had one property worth keeping: a read that failed failed
  /// alone, and the next one opened again and worked. A handle held for the
  /// session has no such luck — a network share that blinks, a cloud
  /// provider that evicts and rehydrates, a volume that remounts, all leave
  /// a descriptor that answers nothing, and every cel after it would fail
  /// against a file that is sitting there readable.
  ///
  /// ⛔Once, not a loop. If the file is genuinely gone the second open
  /// throws, and that throw is the answer the save path already handles (a
  /// cel whose only copy went with its file is SKIPPED and counted). A
  /// retry loop would turn that into a hang.
  Uint8List readAt(String path, int offset, int length) {
    try {
      return _readThrough(_handleFor(path), offset, length);
    } on Object {
      release();
      return _readThrough(_handleFor(path), offset, length);
    }
  }

  static Uint8List _readThrough(
    RandomAccessFile handle,
    int offset,
    int length,
  ) {
    handle.setPositionSync(offset);
    return handle.readSync(length);
  }

  RandomAccessFile _handleFor(String path) {
    final open = _handle;
    if (open != null && _path == path) {
      return open;
    }
    // A different project: the old handle has no reason to keep the old
    // file undeletable.
    release();
    debugOpens += 1;
    final opened = File(path).openSync();
    _path = path;
    _handle = opened;
    return opened;
  }

  /// Lets go if — and only if — the file being held is [path].
  ///
  /// ⛔The path test is the point. A blanket release from whoever is about
  /// to write SOMETHING would drop the project file for a sidecar write,
  /// and the protection would be off during exactly the window a save
  /// takes.
  void releaseFor(String path) {
    if (_path == path) {
      release();
    }
  }

  void release() {
    final open = _handle;
    _handle = null;
    _path = null;
    if (open == null) {
      return;
    }
    try {
      open.closeSync();
    } on Object {
      // A handle that cannot be closed is already gone; holding the
      // reference would only keep the file undeletable for no one.
    }
  }

  /// Whether a file is being held right now (diagnostics/tests).
  bool get isHolding => _handle != null;

  /// The file being held, or null.
  String? get heldPath => _path;

  static void debugResetForTests() {
    instance.release();
    debugOpens = 0;
  }

  /// Closes the held descriptor while KEEPING it as the held one — the
  /// state a share that dropped leaves behind.
  ///
  /// 🧪The seam exists because nothing else can produce that state on
  /// demand, and without it the retry in [readAt] is code no test can
  /// reach: deleting the file does not do it (Windows refuses while we
  /// hold it, POSIX keeps our descriptor working), and neither does a
  /// rename.
  @visibleForTesting
  static void debugBreakHeldHandle() {
    instance._handle?.closeSync();
  }
}

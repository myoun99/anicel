import 'dart:io';
import 'dart:typed_data';

/// A folder of files kept under names it mints, which [isName] tells from
/// every other — a library of this device's: the fonts a person brought
/// (`FontLibraryService`), the fx plugins they installed
/// (`FxPluginLibraryService`).
///
/// ⛔THE ONE LINE THAT JOINS SUCH A FOLDER AND A NAME IT WAS HANDED (board
/// `law-저장`, as the staging room's `_pathInTheRoom` is its) — [pathOf]:
/// an index is a file on a disk and a project is a file from anywhere, and
/// what either says reaches the disk through here or not at all. Nothing
/// is written, read or deleted under a name that is not one of the
/// folder's own.
///
/// ↩️The font library and the plugin library each wrote this out — the
/// same guard, write, read and delete (the clone ratchet, 2026-10-30).
final class NamedFileFolder {
  const NamedFileFolder(this.directoryPath, {required this.isName});

  final String directoryPath;

  /// Whether a file may be kept here under [file].
  final bool Function(String file) isName;

  /// Where the folder keeps a file called [file] — null where [file] is
  /// not a name of its own.
  String? pathOf(String file) => isName(file) ? '$directoryPath/$file' : null;

  /// Writes [bytes] under [file], making the folder where it is not yet.
  ///
  /// ⚠️[file] is a name the folder's owner minted; one that is not a name
  /// of its own is the caller's mistake and is refused, rather than
  /// written where nothing would read it back.
  Future<void> write(String file, Uint8List bytes) async {
    final path = pathOf(file);
    if (path == null) {
      throw ArgumentError.value(file, 'file', 'is not a name of the library');
    }
    final target = File(path);
    await target.parent.create(recursive: true);
    await target.writeAsBytes(bytes, flush: true);
  }

  /// The bytes of [file] — null where it is gone, unreadable, or not a name
  /// of the folder's own.
  Future<Uint8List?> read(String file) async {
    final path = pathOf(file);
    if (path == null) {
      return null;
    }
    try {
      return await File(path).readAsBytes();
    } on Object {
      return null;
    }
  }

  /// Removes [file]. A missing file is not an error — the owner's index is
  /// the record that matters — and one that will not delete stays on disk,
  /// read by nothing once the index has dropped it.
  Future<void> delete(String file) async {
    final path = pathOf(file);
    if (path == null) {
      return;
    }
    try {
      final target = File(path);
      if (await target.exists()) {
        await target.delete();
      }
    } on Object {
      // Left on disk, read by nothing.
    }
  }
}

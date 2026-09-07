import 'dart:io';
import 'dart:typed_data';

/// Writing and reading one file in the app container's per-run room —
/// the mechanism, with no opinion about WHICH room or what the bytes mean.
///
/// 🚨★★★**THE ROOM IS THE DIFFERENCE, NOT THE MECHANISM.** The container's
/// run holds two kinds of tenant with opposite lifetimes — 이사대기, bytes
/// waiting to move into the project file, and 휘발성, bytes that mean
/// nothing once the run ends — and both need exactly this: create the
/// parent, write through a neighbour, rename into place, tolerate a
/// refusal. Written twice it would be one algorithm under two names, and
/// the second copy is where the two lifetimes start to drift.
///
/// ⛔**A refusal is not an exception to throw.** Every caller here is
/// parking bytes it must otherwise KEEP: a cel that cannot be written
/// stays hot, an undo payload that cannot be written stays in memory.
/// Throwing would turn "no room on disk" into "the drawing is gone".
class ScratchFile {
  const ScratchFile._();

  /// Writes [bytes] to [path] and answers it, or null when the write
  /// refused.
  ///
  /// ⚠️Through a neighbour and a rename: a kill mid-write would otherwise
  /// leave a SHORT file under the real name, and no reader can tell a
  /// short payload from a small one.
  ///
  /// ⚠️The PARENT of the file, not the room — a caller whose name carries
  /// its own folder (`cels/<name>.celz`) has nowhere to land otherwise,
  /// and every write silently refuses.
  static String? write(String path, Uint8List bytes) {
    try {
      File(path).parent.createSync(recursive: true);
      final part = File('$path.part')..writeAsBytesSync(bytes, flush: true);
      part.renameSync(path);
      return path;
    } on Object {
      return null;
    }
  }

  /// The bytes at [path], or null when it will not read — a torn write, a
  /// file somebody removed under us.
  static Uint8List? read(String path) {
    try {
      return File(path).readAsBytesSync();
    } on Object {
      return null;
    }
  }

  /// Removes [path]. Silent: the room goes with the run anyway, so a
  /// leftover costs nothing but space until then.
  static void remove(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } on Object {
      // Locked by a sync client or an open handle; the room's own ending
      // takes it.
    }
  }
}

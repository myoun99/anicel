import 'dart:io';

import '../../models/media_identity.dart';

/// The identity of the file at [path], or null when nothing is there.
///
/// A public function rather than a private helper on the session, because
/// the session is where wiring goes to become unobservable: the conform
/// cache move shipped a correct law with nobody watching the assembly that
/// used it, and only a mutation found that out. Registration reaches this
/// from four different places; they should all reach the same named thing.
///
/// Asks the PATH, not a `File`: `File(dir).existsSync()` answers false for
/// a directory, which would report "nothing here" for a path that plainly
/// has something at it.
///
/// Records the length alone. Reading the bytes for a CRC is what this
/// deliberately does not do — see [MediaIdentity.crc32].
MediaIdentity? readMediaIdentity(String path) {
  final stat = _fileStatOf(path);
  return stat == null ? null : MediaIdentity(lengthBytes: stat.size);
}

/// When the file at [path] was last changed, or null when nothing is there
/// — what a 품기 of it records ([MediaCarriedAs]), read as it is carried.
DateTime? readMediaModified(String path) => _fileStatOf(path)?.modified;

/// The stat of the FILE at [path] — null for a directory, for nothing, and
/// for a path the system will not answer about.
FileStat? _fileStatOf(String path) {
  try {
    final stat = FileStat.statSync(path);
    return stat.type == FileSystemEntityType.file ? stat : null;
  } on Object {
    return null;
  }
}

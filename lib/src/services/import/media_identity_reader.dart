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
  try {
    final stat = FileStat.statSync(path);
    if (stat.type != FileSystemEntityType.file) {
      return null;
    }
    return MediaIdentity(lengthBytes: stat.size);
  } on Object {
    return null;
  }
}

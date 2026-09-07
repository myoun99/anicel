import 'package:anicel/src/services/media/media_byte_source.dart';

/// The FILE a conform's byte source names, or null when it names a range
/// inside a project archive instead.
///
/// ⛔**Test-only, and deliberately not on [MediaByteSource].** Production
/// reads a source without ever asking where it is — that is the whole
/// point of the type, and the reason a conform the project carries stopped
/// being copied out of the archive to make a file for something to open.
/// A test that pins WHICH spelling was written still has to ask, so it
/// asks here rather than teaching the production type a question nothing
/// in production needs.
String? conformFilePathOrNull(MediaByteSource? source) => switch (source) {
  MediaAppFileBytes(:final path) => path,
  MediaFileBytes(:final path) => path,
  _ => null,
};

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
/// 🚨★★★**A FRAMED SOURCE IS ONE OF THOSE, WRAPPED.** Whether a conform is
/// compressed is decided by measurement, so the same call answers with a
/// bare file source on a machine with no native engine and a
/// [MediaFramedBytes] over one where the compressor is available. This
/// switch had no case for the wrapper, so it answered null the moment the
/// engine was actually there — and nine tests died on the `!` at their call
/// sites. ⛔They had never run with one, because the conform reader resolves
/// the engine through `QA_ENGINE_PATH` and `flutter test` sets none
/// (2026-09-08).
///
/// ⚠️The file it names then holds COMPRESSED BLOCKS. A test that wants the
/// conform's own bytes reads the SOURCE (`readSync`), never the file — that
/// is the whole reason the wrapper exists.
String? conformFilePathOrNull(MediaByteSource? source) => switch (source) {
  MediaFramedBytes(:final stored) => conformFilePathOrNull(stored),
  MediaAppFileBytes(:final path) => path,
  MediaFileBytes(:final path) => path,
  _ => null,
};

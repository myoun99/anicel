import 'dart:io';
import 'dart:typed_data';

import '../../native/qa_cel_compressor.dart';

/// Which compressor wrote a payload.
///
/// 🚨★★★**deflate is the FLOOR and that is not a fallback to apologise
/// for.** `dart:io` has zlib, so every build can read a deflate payload —
/// a test run, a host run, any build where the engine did not load. zstd
/// is written only when the engine answered. ⛔A file this app writes must
/// never need a library that might not be there.
const int anicelCodecDeflate = 0;
const int anicelCodecZstd = 1;

/// The normal save's zstd level, and the「smallest file」one.
///
/// Both READ at the same speed — the level is a save cost only, and only
/// on the parts a save actually re-encodes. 19 is a quarter smaller than
/// deflate on real cel data; it is a choice rather than the default
/// because compressing takes noticeably longer per hot cel (6ms → 30ms on
/// a 1MB cel, measured).
///
/// ⛔22 is not offered: 0.4% smaller than 19 and **36× slower** on the
/// same cel. Measured, not assumed.
const int anicelZstdLevelNormal = 9;
const int anicelZstdLevelSmallest = 19;

/// Compresses [bytes] with the best codec this build has, saying which.
///
/// 🚨ONE place picks the codec. It was about to be written twice — once
/// for cel blobs and once for the project manifest — and two copies of
/// "zstd if the engine answered, else deflate" is exactly the kind of
/// pair that drifts when one of them learns something.
({int codec, Uint8List bytes}) compressAnicelPayload(
  Uint8List bytes, {
  int? zstdLevel,
}) {
  final compressor = QaCelCompressor.instance;
  final zstd = compressor != null && compressor.isSupported
      ? compressor.compress(bytes, level: zstdLevel ?? anicelZstdLevelNormal)
      : null;
  if (zstd != null) {
    return (codec: anicelCodecZstd, bytes: zstd);
  }
  // Level 9 for deflate: inflate is the same speed whatever level wrote
  // the stream, and every encode site runs off the UI thread, so the level
  // is paid once where nobody is waiting.
  return (
    codec: anicelCodecDeflate,
    bytes: Uint8List.fromList(ZLibCodec(level: 9).encode(bytes)),
  );
}

/// The inverse. Throws when [codec] is zstd and this build cannot read it
/// — the file is fine, this BUILD cannot open it, and saying so beats a
/// zlib error about a zstd frame.
Uint8List decompressAnicelPayload(int codec, Uint8List payload) {
  if (codec == anicelCodecZstd) {
    final compressor = QaCelCompressor.instance;
    final out = compressor == null || !compressor.isSupported
        ? null
        : compressor.decompress(payload);
    if (out == null) {
      throw const FormatException(
        'This payload was written with zstd and no engine is available to '
        'read it.',
      );
    }
    return out;
  }
  final inflated = ZLibDecoder().convert(payload);
  return inflated is Uint8List ? inflated : Uint8List.fromList(inflated);
}

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

/// The zstd level, and there is exactly one.
///
/// 🪦**19 WAS OFFERED AND REJECTED — 유저 확정 2026-08-30: 「9로통일이고
/// 19의 남은잔재는 깔끔하게 삭제하고싶어」.** The numbers that settled it,
/// re-measured on cels from a real project, because the「6ms → 30ms on a
/// 1MB cel」that used to stand here did NOT reproduce:
///
/// | cel | level 9 | level 19 | | smaller |
/// |---|---|---|---|---|
/// | 512KB | 4.1ms | 48ms | 12× | 6–8% |
/// | 768KB | 4.1ms | 50ms | 12× | 6.9% |
/// | 17.9MB | 256ms | **5.4s** | 21× | 10.1% |
///
/// So 19 bought 6–10% for 12–21× the compression time, and the multiplier
/// GREW with the cel — one big cel costs five seconds. Reading is
/// unaffected either way (1,522 MB/s against 1,496, which is noise), so
/// the whole cost sat on the save.
///
/// ⛔And it could never have been a simple flag on「save」: a cel's level
/// is fixed when it COOLS (see `BrushFrameStore._coolLoop`), and a save
/// hands cold and file-backed bytes through untouched. Offering it meant
/// re-inflating and re-compressing every cel a save would otherwise have
/// copied — which is exactly the incremental-append fast path.
///
/// ⛔22 was never offered either: 0.4% smaller than 19 and **36× slower**
/// on the same cel (measured 2026-08-29).
///
/// ⚠️This paragraph is the record, not a proposal. Anyone reaching for a
/// second level should read the table first.
const int anicelZstdLevel = 9;

/// Compresses [bytes] with the best codec this build has, saying which.
///
/// 🚨ONE place picks the codec. It was about to be written twice — once
/// for cel blobs and once for the project manifest — and two copies of
/// "zstd if the engine answered, else deflate" is exactly the kind of
/// pair that drifts when one of them learns something.
({int codec, Uint8List bytes}) compressAnicelPayload(Uint8List bytes) {
  final compressor = QaCelCompressor.instance;
  final zstd = compressor != null && compressor.isSupported
      ? compressor.compress(bytes, level: anicelZstdLevel)
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

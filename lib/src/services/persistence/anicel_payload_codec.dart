import 'dart:io';
import 'dart:typed_data';

import '../../native/qa_cel_compressor.dart';
import 'zstd_payload.dart';

/// Which compressor wrote a payload.
///
/// 🚨★★★**deflate is the FLOOR and that is not a fallback to apologise
/// for.** `dart:io` has zlib, so every build can read a deflate payload.
/// zstd is written wherever the engine does not refuse it. ⛔A file this
/// app writes must never need a library that might not be there.
/// ↩️zstd was written only where the C engine loaded, until the connection
/// round put the compressor in the engine the app ships with
/// (connection-round-checklist H, 2026-11-08).
const int anicelCodecDeflate = 0;
const int anicelCodecZstd = 1;

/// Compresses [bytes] with the best codec this build has, saying which —
/// zstd at its one level (native/compress's `compress` keeps the record of
/// why there is one, 🗣️유저 2026-08-30 「9로통일」), deflate where it
/// refuses.
///
/// 🚨ONE place picks the codec. It was about to be written twice — once
/// for cel blobs and once for the project manifest — and two copies of
/// "zstd unless it refuses, else deflate" is exactly the kind of
/// pair that drifts when one of them learns something.
({int codec, Uint8List bytes}) compressAnicelPayload(Uint8List bytes) {
  final zstd = QaCelCompressor.compress(bytes);
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

/// The inverse, kept: a copy of the bytes for a caller that holds on to
/// them ([readAnicelPayload] hands them only while its reader runs).
Uint8List decompressAnicelPayload(int codec, Uint8List payload) =>
    readAnicelPayload(codec, payload, Uint8List.fromList);

/// What [read] makes of [payload] decompressed, the bytes handed to it only
/// while it runs — a zstd payload's are native and freed when it returns
/// ([QaCelCompressor.readFrame] has why) — so [read] copies what it keeps.
/// Throws when [codec] is zstd and this build cannot read it — the file is
/// fine, this BUILD cannot open it, and saying so beats a zlib error about
/// a zstd frame.
///
/// 🧪In a debug build the bytes are spoiled when [read] returns, deflate's
/// as zstd's: a view of them kept past it reads [spoiledPayloadByte]
/// rather than the picture, so a test that keeps one fails on either codec
/// — not only on the one whose bytes are freed under it, and not by luck.
/// ⛔Spoiled around the codecs, not inside either: a test can read a kept
/// view only where it is not freed (deflate's), so a spoiling one codec
/// skipped would show on no test.
R readAnicelPayload<R>(
  int codec,
  Uint8List payload,
  R Function(Uint8List bytes) read,
) => _decompressed(codec, payload, (bytes) {
  try {
    return read(bytes);
  } finally {
    assert(_spoiled(bytes));
  }
});

/// [read] handed [payload] decompressed by the codec that wrote it.
R _decompressed<R>(
  int codec,
  Uint8List payload,
  R Function(Uint8List bytes) read,
) => codec == anicelCodecZstd
    ? readZstdPayload(payload, 'payload', read)
    : read(_inflated(payload));

/// What a decompressed payload's bytes read once its reader has returned,
/// in a debug build ([readAnicelPayload]).
const int spoiledPayloadByte = 0xDD;

bool _spoiled(Uint8List bytes) {
  bytes.fillRange(0, bytes.length, spoiledPayloadByte);
  return true;
}

Uint8List _inflated(Uint8List payload) {
  final List<int> inflated;
  try {
    inflated = ZLibDecoder().convert(payload);
  } on FormatException catch (error) {
    // 🚨zlib answers「Filter error, bad data」, which names ITS OWN internal
    // filter and says nothing about the file. That string went straight to
    // the screen — `_showFileError` writes `'$error'` — and 유저 2026-08-31
    // met it on a project with nothing in it to act on.
    //
    // The zstd arm above already answers in the app's terms. This makes
    // both do it, and keeps zlib's own words at the end for the person
    // reading a bug report rather than a dialog.
    throw FormatException(
      'this project could not be decompressed — the file is damaged, or it '
      'was written by a build this one cannot read (${error.message})',
    );
  }
  return inflated is Uint8List ? inflated : Uint8List.fromList(inflated);
}

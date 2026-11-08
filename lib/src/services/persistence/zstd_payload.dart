import 'dart:typed_data';

import '../../native/qa_cel_compressor.dart';

/// What [read] makes of [bytes] through the zstd engine — handed to it only
/// while it runs ([QaCelCompressor.readFrame]) — or a FormatException
/// naming [what] when they are no frame it can read.
///
/// ⛔Written once for the payloads that read zstd: the reader that forgot
/// the null check would hand a null on to a caller expecting bytes.
/// ↩️Until the connection round (connection-round-checklist H, 2026-11-08)
/// the engine was optional at runtime, and this exception said "no engine
/// is available"; the engine's compressor ships with the app now, so a
/// frame it cannot read is a frame that does not decode.
R readZstdPayload<R>(
  Uint8List bytes,
  String what,
  R Function(Uint8List bytes) read,
) {
  // In a record, so a [read] that answers null is not taken for a frame
  // the engine could not read.
  final out = QaCelCompressor.readFrame(bytes, (inflated) => (read(inflated),));
  if (out == null) {
    throw FormatException('This $what is a zstd frame that does not decode.');
  }
  return out.$1;
}

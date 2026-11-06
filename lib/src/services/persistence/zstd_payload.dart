import 'dart:typed_data';

import '../../native/qa_cel_compressor.dart';

/// What [read] makes of [bytes] through the zstd engine — handed to it only
/// while it runs ([QaCelCompressor.readFrame]) — or a FormatException
/// naming [what] when there is no engine available to read them.
///
/// ⛔BOTH ZSTD READERS ASK THE SAME QUESTION, AND THE ANSWER IS A
/// FILE-LEVEL ONE. The engine is optional at runtime — a build without
/// it, an unsupported platform — so "no engine" is something the user can
/// act on, and it must not reach the screen as "corrupt". Written twice,
/// the reader that forgot the null check would hand a null on to a caller
/// expecting bytes.
R readZstdPayload<R>(
  Uint8List bytes,
  String what,
  R Function(Uint8List bytes) read,
) {
  final compressor = QaCelCompressor.instance;
  // In a record, so a [read] that answers null is not taken for a frame
  // the engine could not read.
  final out = compressor == null || !compressor.isSupported
      ? null
      : compressor.readFrame(bytes, (inflated) => (read(inflated),));
  if (out == null) {
    throw FormatException(
      'This $what was compressed with zstd and no engine is available to '
      'read it.',
    );
  }
  return out.$1;
}

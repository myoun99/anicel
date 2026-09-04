import 'dart:typed_data';

import '../../native/qa_cel_compressor.dart';

/// [bytes] through the zstd engine, or a FormatException naming [what]
/// when there is no engine available to read them.
///
/// ⛔BOTH ZSTD READERS ASK THE SAME QUESTION, AND THE ANSWER IS A
/// FILE-LEVEL ONE. The engine is optional at runtime — a build without
/// it, an unsupported platform — so "no engine" is something the user can
/// act on, and it must not reach the screen as "corrupt". Written twice,
/// the reader that forgot the null check would hand a null on to a caller
/// expecting bytes.
Uint8List decompressZstdPayload(Uint8List bytes, String what) {
  final compressor = QaCelCompressor.instance;
  final out = compressor == null || !compressor.isSupported
      ? null
      : compressor.decompress(bytes);
  if (out == null) {
    throw FormatException(
      'This $what was compressed with zstd and no engine is available to '
      'read it.',
    );
  }
  return out;
}

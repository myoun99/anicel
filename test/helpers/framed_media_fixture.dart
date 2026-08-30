import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/services/persistence/media_blob_codec.dart';

/// The bytes a framed media entry HAS — produced by the writer that ships.
///
/// ⛔**Not a second encoder.** [writeMediaBlob] is the only thing in the
/// app that lays this format down, and these tests read the layout byte by
/// byte: a fixture that built the header and the blocks itself would be
/// free to drift from the writer, and the drift would hide in exactly the
/// assertions meant to catch it. There WAS such a second encoder — an
/// in-memory `compressMediaBlob` that held the whole asset and every
/// compressed block beside it — and it was removed when the write started
/// streaming, so this reads back what the real one wrote.
///
/// Null when the writer decided the data was not worth framing, which is
/// the same answer the callers already branch on.
Uint8List? framedEntryBytes(
  Uint8List source, {
  int blockBytes = mediaBlockBytes,
}) {
  final directory = Directory.systemTemp.createTempSync('anicel-framed-');
  try {
    final written = writeMediaBlob(
      basePath: '${directory.path.replaceAll(r'\', '/')}/entry',
      length: source.length,
      readInto: mediaBytesReader(source),
      blockBytes: blockBytes,
    );
    return written.framed ? File(written.path).readAsBytesSync() : null;
  } finally {
    try {
      directory.deleteSync(recursive: true);
    } on Object {
      // A leaked handle on Windows must not fail the suite.
    }
  }
}

@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_cel_compressor.dart';

/// The zstd doors driven against the real engine ([_compressor]): what
/// [QaCelCompressor] compresses it decompresses byte for byte, and a frame
/// that is not zstd comes back null rather than as bytes.
///
/// ↩️Real-binary-or-skip until the connection round (connection-round-
/// checklist H): the compressor was the C engine's, found by a path. It is
/// the engine's own now, in the code asset every run builds, so nothing
/// here skips.
void main() {
  Uint8List patterned(int length, int seed) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i += 1) {
      bytes[i] = (i * seed + (i >> 5)) & 0xFF;
    }
    return bytes;
  }

  test('compress then decompress is the identity', () {
    for (final seed in [1, 37, 91]) {
      final bytes = patterned(64 * 64 * 4, seed);
      final frame = QaCelCompressor.compress(bytes);
      expect(frame, isNotNull, reason: '$_compressor wrote no frame');
      expect(frame!.length, lessThan(bytes.length));
      expect(QaCelCompressor.readFrame(frame, Uint8List.fromList), bytes);
    }
  });

  test('the last byte in is the last byte out', () {
    // A copy-in that stops short, or a copy-out that reads one byte less,
    // both show at the tail — so the tail is pinned on its own.
    final bytes = patterned(4097, 5);
    bytes[4096] = 0xAB;
    final frame = QaCelCompressor.compress(bytes)!;
    final back = QaCelCompressor.readFrame(frame, Uint8List.fromList)!;
    expect(back.length, 4097);
    expect(back[4096], 0xAB);
  });

  test('a frame that is not zstd decompresses to null, not to bytes', () {
    for (final notZstd in [patterned(64, 3), Uint8List(0)]) {
      var read = false;
      expect(
        QaCelCompressor.readFrame(notZstd, (_) => read = true),
        isNull,
      );
      expect(read, isFalse, reason: 'no bytes to hand a reader');
    }
    expect(QaCelCompressor.compress(Uint8List(0)), isNull);
  });

  test('🧪a forced refusal answers null, which is what writes deflate', () {
    QaCelCompressor.debugForceRefusal = true;
    addTearDown(() => QaCelCompressor.debugForceRefusal = false);
    expect(QaCelCompressor.compress(patterned(4096, 7)), isNull);
  });
}

/// The compressor these ask — named as a path, so a lane that changed only
/// the engine's compressor runs this file (`affected_tests` picks a test by
/// the paths it writes out, 보드/인프라 2026-11-08 05:35).
const _compressor = 'packages/gpu_engine/rust/native/compress';

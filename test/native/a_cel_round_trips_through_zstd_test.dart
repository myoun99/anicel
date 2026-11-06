@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_cel_compressor.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';

import '../helpers/native_engine_path.dart';

/// The zstd doors driven against the real engine: what [QaCelCompressor]
/// compresses it decompresses byte for byte, and a frame that is not zstd
/// comes back null rather than as bytes.
///
/// Real-binary-or-skip, like every engine suite — the cooling-path tests
/// reach the compressor through `instance` with no path override, so on a
/// machine whose engine lives under build/ they skip and nothing here ran.
void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();
  final skip = libraryPath != null ? false : nativeEngineMissingSkipReason;

  setUp(() {
    QaCelCompressor.debugResetForTests();
    debugQaEngineLibraryPathOverride = libraryPath;
  });

  tearDown(() {
    QaCelCompressor.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
  });

  QaCelCompressor requireCompressor() {
    final compressor = QaCelCompressor.instance;
    expect(
      compressor,
      isNotNull,
      reason: 'the binary at $libraryPath loaded but zstd did not bind',
    );
    expect(compressor!.isSupported, isTrue);
    return compressor;
  }

  Uint8List patterned(int length, int seed) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i += 1) {
      bytes[i] = (i * seed + (i >> 5)) & 0xFF;
    }
    return bytes;
  }

  test('compress then decompress is the identity', () {
    final compressor = requireCompressor();
    for (final seed in [1, 37, 91]) {
      final bytes = patterned(64 * 64 * 4, seed);
      final frame = compressor.compress(bytes, level: 3);
      expect(frame, isNotNull);
      expect(frame!.length, lessThan(bytes.length));
      expect(compressor.readFrame(frame, Uint8List.fromList), bytes);
    }
  }, skip: skip);

  test('the last byte in is the last byte out', () {
    // A copy-in that stops short, or a copy-out that reads one byte less,
    // both show at the tail — so the tail is pinned on its own.
    final compressor = requireCompressor();
    final bytes = patterned(4097, 5);
    bytes[4096] = 0xAB;
    final frame = compressor.compress(bytes, level: 1)!;
    final back = compressor.readFrame(frame, Uint8List.fromList)!;
    expect(back.length, 4097);
    expect(back[4096], 0xAB);
  }, skip: skip);

  test('a frame that is not zstd decompresses to null, not to bytes', () {
    final compressor = requireCompressor();
    for (final notZstd in [patterned(64, 3), Uint8List(0)]) {
      var read = false;
      expect(compressor.readFrame(notZstd, (_) => read = true), isNull);
      expect(read, isFalse, reason: 'no bytes to hand a reader');
    }
    expect(compressor.compress(Uint8List(0), level: 3), isNull);
  }, skip: skip);
}

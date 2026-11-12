import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/native_engine_path.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';

/// R18 A-0: the native engine core must be BYTE-IDENTICAL to the Dart
/// reference implementation — a tile's premultiply through both paths,
/// compared per byte. Skips (loudly) when no locally built binary is
/// found; CI/dev machines with the standalone cmake build run it.
///
/// ↩️Till 2026-11-12 the brush was here too — stamps, generic dabs, mixed
/// sequences and masked tips materialized through the C kernel and the Dart
/// one, compared per pixel. The C brush went (ABI 80).
void main() {
  // R26/2A: resolved per platform (and via QA_ENGINE_PATH on CI) so these
  // byte-parity pins are not silently Windows-only.
  final dllPath = nativeEngineLibraryPathOrNull();
  final available = dllPath != null;

  setUp(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugForceDartFallback = false;
  });

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugForceDartFallback = false;
  });

  test('native premultiply == Dart reference over EVERY colour at EVERY '
      'alpha — four pixels a step and the scalar tail alike', () {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    // Pixel i holds colour i & 0xFF in red, its inverse in green, its
    // half in blue, at alpha i >> 8: all 65,536 pairs the formula takes,
    // in one 256px tile — and a 255px one, whose rows end three pixels
    // into a step, so the tail meets them too.
    for (final size in [256, 255]) {
      final bytes = Uint8List(size * size * 4);
      for (var i = 0; i < size * size; i += 1) {
        final pair = i & 0xFFFF;
        bytes[i * 4] = pair & 0xFF;
        bytes[i * 4 + 1] = 255 - (pair & 0xFF);
        bytes[i * 4 + 2] = (pair & 0xFF) >> 1;
        bytes[i * 4 + 3] = pair >> 8;
      }
      final tile = BitmapTile(size: size, pixels: bytes);

      QaNativeEngine.debugForceDartFallback = true;
      final dartUpload = BitmapTileImageCache.premultipliedTileUpload(tile);
      QaNativeEngine.debugForceDartFallback = false;
      final nativeUpload = BitmapTileImageCache.premultipliedTileUpload(tile);
      final dartResult = Uint8List.fromList(dartUpload.view);
      final nativeResult = Uint8List.fromList(nativeUpload.view);
      dartUpload.free();
      nativeUpload.free();

      expect(nativeResult, dartResult, reason: '${size}x$size');
    }
  });

  test('native premultiply == Dart reference, byte for byte (randomized)', () {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    final random = Random(7);
    for (var round = 0; round < 12; round += 1) {
      final size = 1 + random.nextInt(48);
      final bytes = Uint8List(size * size * 4);
      for (var i = 0; i < bytes.length; i += 1) {
        // Edge-biased: plenty of alpha 0 / 255 plus the full range.
        final roll = random.nextInt(6);
        bytes[i] = roll == 0
            ? 0
            : roll == 1
            ? 255
            : random.nextInt(256);
      }
      final tile = BitmapTile(
        size: size,
        pixels: bytes,
      );

      QaNativeEngine.debugForceDartFallback = true;
      final dartUpload = BitmapTileImageCache.premultipliedTileUpload(tile);
      QaNativeEngine.debugForceDartFallback = false;
      final nativeUpload = BitmapTileImageCache.premultipliedTileUpload(tile);
      // Copy the native view out before releasing it: the comparison
      // below outlives the scratch.
      final dartResult = Uint8List.fromList(dartUpload.view);
      final nativeResult = Uint8List.fromList(nativeUpload.view);
      dartUpload.free();
      nativeUpload.free();

      expect(
        nativeResult,
        dartResult,
        reason: 'round $round (${size}x$size) must be byte-identical',
      );
    }
  });
}

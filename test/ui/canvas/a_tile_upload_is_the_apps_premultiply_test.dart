import 'dart:math';
import 'dart:typed_data';

import 'package:anicel/src/core/rgba_premultiply.dart';
import 'package:anicel/src/core/sync_image_upload.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:flutter_test/flutter_test.dart';

/// A tile's staged upload ([BitmapTileImageCache.premultipliedTileUpload])
/// is the app's premultiply, byte for byte, and its block is freed once the
/// door has read it.
///
/// 🚨THE PIN OF A KNOWN COPY. The upload's bytes are the engine library's
/// four-pixel premultiply (native/premultiply) and the law is the Dart loop
/// ([premultiplyRgbaInPlace]): one formula spelled twice, kept so for the
/// upload's speed (관제 2026-11-13, connection-round-checklist). These hold
/// the two to the same bytes till board card
/// `the-premultiply-is-spelled-twice-on-the-cpu` makes them one, and go
/// with the loop.
///
/// ↩️Till C ABI 83 the fast one was the C engine's and this was
/// `qa_native_engine_parity_test`, which skipped wherever no C binary was
/// built. Till ABI 80 the brush was in it too — stamps, generic dabs, mixed
/// sequences and masked tips materialized through the C kernel and the Dart
/// one, compared per pixel.
void main() {
  Uint8List staged(BitmapTile tile) {
    final upload = BitmapTileImageCache.premultipliedTileUpload(tile);
    try {
      return Uint8List.fromList(upload.view);
    } finally {
      upload.free();
    }
  }

  test('a staged upload is the law over EVERY colour at EVERY alpha — four '
      'pixels a step and a pixel taken alone alike', () {
    // Pixel i holds colour i & 0xFF in red, its inverse in green, its
    // half in blue, at alpha i >> 8: all 65,536 pairs the formula takes,
    // in one 256px tile — and a 255px one, one pixel past its last whole
    // step, so a pixel taken alone is met too.
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

      expect(
        staged(tile),
        premultipliedRgbaCopy(bytes),
        reason: '${size}x$size',
      );
    }
  });

  test('a staged upload is the law, byte for byte (randomized)', () {
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
      final tile = BitmapTile(size: size, pixels: bytes);

      expect(
        staged(tile),
        premultipliedRgbaCopy(bytes),
        reason: 'round $round (${size}x$size) must be byte-identical',
      );
    }
  });

  test('the staging is freed once the door has read it', () {
    addTearDown(() => debugPictureOfUploads = null);
    final tile = BitmapTile(
      size: 8,
      pixels: Uint8List(8 * 8 * 4)..fillRange(0, 8 * 8 * 4, 200),
    );
    final before = PremultipliedTileUpload.debugLiveCount;

    // The test runner draws (Skia): told it uploads, the door stages the
    // tile's bytes for an upload, and the runner refuses it.
    debugPictureOfUploads = true;
    BitmapTileImageCache.pictureOfTile(tile).dispose();

    expect(
      pictureOfUploads,
      isFalse,
      reason: '⛔premise: the upload was asked, and refused',
    );
    expect(PremultipliedTileUpload.debugLiveCount, before);
  });
}

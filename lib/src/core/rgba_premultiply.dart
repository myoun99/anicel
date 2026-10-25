import 'dart:math' as math;
import 'dart:typed_data';

/// Premultiplies straight RGBA bytes IN PLACE — the same mul-div-255
/// rounding every tile upload in the app uses: alpha 255 is left alone,
/// alpha 0 zeroes the colour, anything between multiplies and rounds.
///
/// 🚨ONE law. The live-stroke rasterizer, the brush edit view's fill
/// fallback, the stroke overlay's tile decode and the tile image cache's
/// upload each carried this loop (the audit's clone scan, 2026-09-03);
/// a rounding that drifted in one of them would have shown as a seam
/// between a stroke and its landed pixels.
void premultiplyRgbaInPlace(Uint8List bytes) {
  for (var offset = 0; offset < bytes.length; offset += 4) {
    final alpha = bytes[offset + 3];
    if (alpha == 255) {
      continue;
    }
    if (alpha == 0) {
      bytes[offset] = 0;
      bytes[offset + 1] = 0;
      bytes[offset + 2] = 0;
      continue;
    }
    bytes[offset] = mul255Round(bytes[offset], alpha);
    bytes[offset + 1] = mul255Round(bytes[offset + 1], alpha);
    bytes[offset + 2] = mul255Round(bytes[offset + 2], alpha);
  }
}

/// Zeroes the colour of every fully clear pixel of straight RGBA [bytes],
/// IN PLACE: a pixel no alpha shows is (0,0,0,0), whatever colour it came
/// with.
///
/// ONE law for a clear pixel's bytes. A stroke's landing writes one so
/// (its srcOver skips α==0 — `preBlendStrokeOverlayPixels` mirrors it), and
/// the engine's decoder hands one back so, as the app's own decoders of a
/// picture past its side do (`readPngRows`, `readFramesByPackage`) — the
/// third to carry the loop (2026-10-20), so it is one.
void zeroFullyClearPixels(Uint8List bytes) {
  for (var offset = 3; offset < bytes.length; offset += 4) {
    if (bytes[offset] == 0) {
      bytes[offset - 3] = 0;
      bytes[offset - 2] = 0;
      bytes[offset - 1] = 0;
    }
  }
}

/// A premultiplied copy of [straight]; the source is left as it was.
Uint8List premultipliedRgbaCopy(Uint8List straight) {
  final bytes = Uint8List.fromList(straight);
  premultiplyRgbaInPlace(bytes);
  return bytes;
}

/// Straight RGBA bytes that [premultiplyRgbaInPlace] turns back into
/// exactly [premultiplied]; the source is left as it was. What a picture
/// DRAWN from straight colours (the door's Skia road, `pictureOf`) needs of
/// bytes that were only ever premultiplied — a timeline tile's raster.
///
/// ⚠️Not the colour the premultiply came from: under a low alpha many
/// colours premultiply alike, and nothing tells which one it was. It is the
/// one whose premultiply IS the channel, so the picture's bytes are the
/// raster's to the last one. A channel over its alpha, which no premultiply
/// makes, takes 255.
Uint8List straightRgbaFor(Uint8List premultiplied) {
  final bytes = Uint8List.fromList(premultiplied);
  for (var offset = 0; offset < bytes.length; offset += 4) {
    final alpha = bytes[offset + 3];
    if (alpha == 255 || alpha == 0) {
      continue;
    }
    for (var channel = offset; channel < offset + 3; channel += 1) {
      // The rounded inverse of [mul255Round] lands on it exactly for every
      // channel up to its alpha — pinned over all of them.
      bytes[channel] = math.min(
        255,
        (bytes[channel] * 255 + alpha ~/ 2) ~/ alpha,
      );
    }
  }
  return bytes;
}

/// `value * alpha / 255`, rounded the way the whole app rounds it.
int mul255Round(int value, int alpha) {
  final product = value * alpha + 128;
  return (product + (product >> 8)) >> 8;
}

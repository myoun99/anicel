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

/// A premultiplied copy of [straight]; the source is left as it was.
Uint8List premultipliedRgbaCopy(Uint8List straight) {
  final bytes = Uint8List.fromList(straight);
  premultiplyRgbaInPlace(bytes);
  return bytes;
}

/// `value * alpha / 255`, rounded the way the whole app rounds it.
int mul255Round(int value, int alpha) {
  final product = value * alpha + 128;
  return (product + (product >> 8)) >> 8;
}

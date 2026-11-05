import 'package:image/image.dart' as img;

/// A GIF's black-and-white palette: black where a pixel is darker than
/// half, white elsewhere — the one answer however the pixel is asked.
///
/// ↩️It was the image package's `BinaryQuantizer`, which asks a colour its
/// brightness out of 1 but asks three channels their brightness out of 255
/// against the same 0.5 — and a dither asks by channels, so every grey but
/// black came out white and a Floyd–Steinberg ramp was 41% black where it
/// is half (I-152, 2026-11-05).
/// 🧭관제 (gpu-export-path ③, 2026-11-05): the cut is 299r + 587g + 114b
/// < 127500 — BT.601 brightness under half of 255, in whole numbers.
class GifBlackWhiteQuantizer extends img.Quantizer {
  @override
  final img.PaletteUint8 palette = img.PaletteUint8(2, 3)
    ..setRgb(1, 255, 255, 255);

  @override
  int getColorIndexRgb(int r, int g, int b) =>
      r * 299 + g * 587 + b * 114 < 127500 ? 0 : 1;

  @override
  int getColorIndex(img.Color c) =>
      getColorIndexRgb(c.r.toInt(), c.g.toInt(), c.b.toInt());

  @override
  img.Color getQuantizedColor(img.Color c) {
    final level = getColorIndex(c) * 255;
    return img.ColorRgb8(level, level, level);
  }
}

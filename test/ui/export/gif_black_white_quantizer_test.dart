import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:anicel/src/ui/export/gif_black_white_quantizer.dart';

/// 🧭관제 (gpu-export-path ③, 2026-11-05): black is 299r + 587g + 114b
/// < 127500 — and one answer however a pixel is asked (I-152).
void main() {
  final quantizer = GifBlackWhiteQuantizer();

  test('the cut is BT.601 brightness under half of 255, each channel at '
      'its own weight', () {
    final cases = {
      (128, 127, 127): 0, // 127299
      (128, 128, 127): 1, // 127886
      (255, 0, 0): 0, // 76245
      (0, 255, 0): 1, // 149685
      (0, 0, 255): 0, // 29070
    };
    for (final MapEntry(key: (r, g, b), value: index) in cases.entries) {
      expect(
        quantizer.getColorIndexRgb(r, g, b),
        index,
        reason: '($r, $g, $b)',
      );
    }
  });

  test('a colour asked whole and asked by its channels gets one answer — '
      'black, or white', () {
    for (var r = 0; r < 256; r += 15) {
      for (var g = 0; g < 256; g += 15) {
        for (var b = 0; b < 256; b += 15) {
          final colour = img.ColorRgb8(r, g, b);
          final index = quantizer.getColorIndexRgb(r, g, b);
          expect(quantizer.getColorIndex(colour), index);
          final level = index * 255;
          final cut = quantizer.getQuantizedColor(colour);
          expect((cut.r, cut.g, cut.b), (level, level, level));
        }
      }
    }
    expect(quantizer.palette.numColors, 2);
    expect(
      [quantizer.palette.getRed(0), quantizer.palette.getRed(1)],
      [0, 255],
    );
  });
}

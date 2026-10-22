import 'dart:typed_data';

/// Multiplies a layer mask into the alpha of [rgba] — straight RGBA,
/// [layerWidth] × [layerHeight] with its top-left at ([layerLeft],
/// [layerTop]) — which is what "bake the mask" means: the covered pixels
/// stop existing.
///
/// The mask carries its OWN rectangle in the same space, one byte a pixel,
/// and anything outside it is [defaultColor] — a black default hides
/// everything the mask does not reach, so ignoring the rectangle is not a
/// small error.
///
/// 🚨ONE bake for every decoder that brings a mask in: Photoshop's, and
/// CLIP STUDIO's since 10-17 (보드 `the-clip-import-leaves-masks-and-locks-
/// unsaid` — 「PSD 와 같은 법」). It was the Photoshop reader's own.
void applyMaskToAlpha(
  Uint8List rgba, {
  required int layerLeft,
  required int layerTop,
  required int layerWidth,
  required int layerHeight,
  required Uint8List mask,
  required int maskLeft,
  required int maskTop,
  required int maskWidth,
  required int maskHeight,
  required int defaultColor,
}) {
  for (var y = 0; y < layerHeight; y += 1) {
    final maskY = layerTop + y - maskTop;
    for (var x = 0; x < layerWidth; x += 1) {
      final maskX = layerLeft + x - maskLeft;
      final inside =
          maskX >= 0 && maskY >= 0 && maskX < maskWidth && maskY < maskHeight;
      final coverage = inside ? mask[maskY * maskWidth + maskX] : defaultColor;
      if (coverage == 255) {
        continue;
      }
      final index = (y * layerWidth + x) * 4 + 3;
      rgba[index] = (rgba[index] * coverage) ~/ 255;
    }
  }
}

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
  final stride = layerWidth * 4;
  for (var y = 0; y < layerHeight; y += 1) {
    applyMaskToAlphaRow(
      Uint8List.sublistView(rgba, y * stride, (y + 1) * stride),
      left: layerLeft,
      top: layerTop + y,
      mask: mask,
      maskLeft: maskLeft,
      maskTop: maskTop,
      maskWidth: maskWidth,
      maskHeight: maskHeight,
      defaultColor: defaultColor,
    );
  }
}

/// [applyMaskToAlpha] for ONE row of straight RGBA, its first pixel at
/// ([left], [top]) in the mask's space — what a picture handed on a row at
/// a time and never held whole (a Photoshop layer cut into tiles as it is
/// packed, 2026-11-16) bakes its mask with. The whole picture's bake is its
/// rows, each through here.
void applyMaskToAlphaRow(
  Uint8List row, {
  required int left,
  required int top,
  required Uint8List mask,
  required int maskLeft,
  required int maskTop,
  required int maskWidth,
  required int maskHeight,
  required int defaultColor,
}) {
  final maskY = top - maskTop;
  final count = row.length ~/ 4;
  for (var x = 0; x < count; x += 1) {
    final maskX = left + x - maskLeft;
    final inside =
        maskX >= 0 && maskY >= 0 && maskX < maskWidth && maskY < maskHeight;
    final coverage = inside ? mask[maskY * maskWidth + maskX] : defaultColor;
    if (coverage == 255) {
      continue;
    }
    final index = x * 4 + 3;
    row[index] = (row[index] * coverage) ~/ 255;
  }
}

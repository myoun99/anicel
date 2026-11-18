import 'dart:typed_data';

/// A layer mask in the space of the picture it is baked into: one byte a
/// pixel over its own [width] × [height] rectangle from ([left], [top]),
/// and [defaultColor] everywhere past it.
typedef LayerMask = ({
  Uint8List plane,
  int left,
  int top,
  int width,
  int height,
  int defaultColor,
});

/// Multiplies a layer [mask] into the alpha of [rgba] — straight RGBA,
/// [layerWidth] × [layerHeight] with its top-left at ([layerLeft],
/// [layerTop]) — which is what "bake the mask" means: the covered pixels
/// stop existing.
///
/// The mask carries its OWN rectangle in the same space, and anything
/// outside it is its default — a black default hides everything the mask
/// does not reach, so ignoring the rectangle is not a small error.
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
  required LayerMask mask,
}) {
  final stride = layerWidth * 4;
  for (var y = 0; y < layerHeight; y += 1) {
    applyMaskToAlphaRow(
      Uint8List.sublistView(rgba, y * stride, (y + 1) * stride),
      left: layerLeft,
      top: layerTop + y,
      mask: mask,
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
  required LayerMask mask,
}) {
  final maskY = top - mask.top;
  final count = row.length ~/ 4;
  for (var x = 0; x < count; x += 1) {
    final maskX = left + x - mask.left;
    final inside =
        maskX >= 0 && maskY >= 0 && maskX < mask.width && maskY < mask.height;
    final coverage = inside
        ? mask.plane[maskY * mask.width + maskX]
        : mask.defaultColor;
    if (coverage == 255) {
      continue;
    }
    final index = x * 4 + 3;
    row[index] = (row[index] * coverage) ~/ 255;
  }
}

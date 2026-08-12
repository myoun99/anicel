import 'dart:math' as math;
import 'dart:typed_data';

import '../models/brush_tip_mask.dart';
import '../models/cut_piece.dart';

/// Turns a held cut piece into a brush tip mask.
///
/// 🚨**Coverage comes from ALPHA, not brightness** — and that is the one
/// place this deliberately parts company with Photoshop and with our own
/// image-import codec.
///
/// Photoshop's rule when you Define Brush Preset is that black is opaque
/// and white is transparent, which is right when the source is an opaque
/// scan of ink on paper. Our source is the opposite: a transparent-
/// background animation cel. Apply the brightness rule to one of those and
/// a bright drawing — a white highlight, a pale fill — reads as "nearly
/// transparent" and all but disappears; in Photoshop a bright piece on
/// transparency is refused outright as an empty selection. The silhouette
/// is what the animator drew, so the silhouette is the coverage.
///
/// The library's own shape rules still apply: square, and no longer than
/// [maxBrushTipMaskSide] on a side.
BrushTipMask cutPieceToTipMask(CutPiece piece, {required String id}) {
  // The POSE is honoured here, unlike paste-at-origin: registering says
  // "this shape, the way I have it set up", and a flipped or resized piece
  // is what the user is looking at when they press the button.
  final source = piece.flippedImage();
  final width = source.width;
  final height = source.height;

  var coverage = Uint8List(width * height);
  for (var index = 0; index < coverage.length; index += 1) {
    coverage[index] = source.rgba[index * 4 + 3];
  }

  var maskWidth = width;
  var maskHeight = height;
  final longSide = math.max(width, height);
  if (longSide > maxBrushTipMaskSide) {
    final scale = maxBrushTipMaskSide / longSide;
    final scaledWidth = math.max(1, (width * scale).round());
    final scaledHeight = math.max(1, (height * scale).round());
    coverage = _boxResize(
      coverage,
      width: width,
      height: height,
      newWidth: scaledWidth,
      newHeight: scaledHeight,
    );
    maskWidth = scaledWidth;
    maskHeight = scaledHeight;
  }

  // Square, content centred — the mask contract.
  final side = math.max(maskWidth, maskHeight);
  final alpha = Uint8List(side * side);
  final offsetX = (side - maskWidth) ~/ 2;
  final offsetY = (side - maskHeight) ~/ 2;
  for (var y = 0; y < maskHeight; y += 1) {
    alpha.setRange(
      (offsetY + y) * side + offsetX,
      (offsetY + y) * side + offsetX + maskWidth,
      coverage,
      y * maskWidth,
    );
  }
  return BrushTipMask(id: id, size: side, alpha: alpha);
}

/// Box average over the source footprint of each destination pixel.
///
/// Averaging rather than point sampling because this is a REDUCTION and a
/// point sampler drops whole strokes out of thin line art. The two-value
/// argument that keeps the stamp path on Pick does not apply here: a tip
/// mask is coverage, and a partly covered tip pixel is a real thing rather
/// than an invented mid-alpha edge.
Uint8List _boxResize(
  Uint8List source, {
  required int width,
  required int height,
  required int newWidth,
  required int newHeight,
}) {
  final out = Uint8List(newWidth * newHeight);
  for (var y = 0; y < newHeight; y += 1) {
    final srcTop = y * height ~/ newHeight;
    final srcBottom = math.max(srcTop + 1, (y + 1) * height ~/ newHeight);
    for (var x = 0; x < newWidth; x += 1) {
      final srcLeft = x * width ~/ newWidth;
      final srcRight = math.max(srcLeft + 1, (x + 1) * width ~/ newWidth);
      var sum = 0;
      var count = 0;
      for (var sy = srcTop; sy < srcBottom; sy += 1) {
        for (var sx = srcLeft; sx < srcRight; sx += 1) {
          sum += source[sy * width + sx];
          count += 1;
        }
      }
      out[y * newWidth + x] = count == 0 ? 0 : sum ~/ count;
    }
  }
  return out;
}

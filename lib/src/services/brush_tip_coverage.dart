import 'dart:math' as math;
import 'dart:typed_data';

import '../models/brush_tip_mask.dart';
import 'resample/coverage_resample.dart';

/// [width] × [height] shrunk to fit [maxBrushTipMaskSide] on the long side,
/// aspect kept, never below 1; unchanged when it already fits.
///
/// 🚨ONE fit for the image decoder and the cut-piece tip (the audit's clone
/// scan, 2026-09-03).
({int width, int height}) brushTipMaskFitted(int width, int height) {
  final longSide = math.max(width, height);
  if (longSide <= maxBrushTipMaskSide) {
    return (width: width, height: height);
  }
  final scale = maxBrushTipMaskSide / longSide;
  return (
    width: math.max(1, (width * scale).round()),
    height: math.max(1, (height * scale).round()),
  );
}

/// [coverage] of [size] as a tip mask: fitted to [maxBrushTipMaskSide],
/// read down through the app's one resampler when the fit shrank it, then
/// squared and centred.
///
/// The tail every coverage source ends with — the image decoder's inverted
/// luminance, the cut piece's alpha plane and the Photoshop pattern's
/// inverted luminance alike.
///
/// 🚨WHICH RESAMPLER IS NO LONGER THE CALLER'S TO PICK (ARCH-audit-Q7,
/// answered 2026-09-07). This used to take a `GrayDownscale` parameter, and
/// the three callers handed it three different filters — a fixed 4-tap
/// bilinear, a box area-average, and a hand-rolled box average with the
/// padding fused in. Three filters is three answers to one question, so
/// the parameter is gone and [resampleCoverage] is the answer. Handing a
/// filter in here again is how they drift apart a second time.
///
/// This file sits in `services` rather than beside [BrushTipMask] in
/// `models` for exactly that reason: the resampler lives in `services`, and
/// the layer order forbids a model reaching out to it. [BrushTipMask] and
/// [maxBrushTipMaskSide] stay inward, where the pure-Dart importers can
/// still name them.
BrushTipMask brushTipMaskFromCoverage(
  Uint8List coverage, {
  required ({int width, int height}) size,
  required String id,
}) {
  final fit = brushTipMaskFitted(size.width, size.height);
  if (fit.width != size.width || fit.height != size.height) {
    coverage = resampleCoverage(
      coverage,
      width: size.width,
      height: size.height,
      newWidth: fit.width,
      newHeight: fit.height,
    );
  }
  return BrushTipMask.square(
    id: id,
    pixels: coverage,
    width: fit.width,
    height: fit.height,
  );
}

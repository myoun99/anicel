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

/// What the straight RGBA picture [rgba] lays as a tip: alpha shaped by
/// darkness, so a black-on-transparent tip reads as its own alpha and a
/// black-on-white scan as inverted luminance. Where that holds nothing at
/// all — a white-on-transparent tip — the alpha alone stands in.
///
/// 🚨ONE reading for a picture that came as a PNG and one that came out of a
/// Clip Studio material (`sutMaterialTipCoverage`): 📏the two-plane tips
/// measured read through it to the ink of their own previews.
Uint8List brushTipCoverageOfRgba(Uint8List rgba) {
  final coverage = Uint8List(rgba.length ~/ 4);
  var sum = 0;
  for (var index = 0; index < coverage.length; index += 1) {
    final r = rgba[index * 4];
    final g = rgba[index * 4 + 1];
    final b = rgba[index * 4 + 2];
    final a = rgba[index * 4 + 3];
    final luminance = (r * 299 + g * 587 + b * 114) ~/ 1000;
    final value = a * (255 - luminance) ~/ 255;
    coverage[index] = value;
    sum += value;
  }
  if (sum == 0) {
    for (var index = 0; index < coverage.length; index += 1) {
      coverage[index] = rgba[index * 4 + 3];
    }
  }
  return coverage;
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

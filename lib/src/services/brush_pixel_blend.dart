import '../models/brush_dab.dart';
import '../models/brush_pixel_coverage.dart';
import '../models/rgba_color.dart';
import '../models/stroke_pixel.dart';
import 'brush_dab_share.dart';
import 'rgba_blend.dart';

double effectiveBrushPixelOpacity({
  required BrushDab dab,
  required BrushPixelCoverage coverage,
}) {
  return dab.opacity * coverage.coverage;
}

/// What [dab] leaves on one pixel of its stroke at [coverage] — the
/// reference for the tile kernels' pixel (`blendDabTilesDart`,
/// `qa_dab_blend_tile`): what is under the dab comes off [destination]'s
/// 16-bit plane and the result lands on both planes (ABI 40), the dab
/// laying its share of what it would lay whole (`stampShareOf`, ABI 41).
StrokePixel blendBrushDabStrokePixel({
  required BrushDab dab,
  required BrushPixelCoverage coverage,
  required StrokePixel destination,
}) {
  final evening = eveningTableOf(dab);
  if (dab.erase) {
    return strokeDestinationOut(
      source: RgbaColor.fromArgbInt(dab.color),
      destination: destination,
      opacity: effectiveBrushPixelOpacity(dab: dab, coverage: coverage),
      flow: dab.flow,
      evening: evening,
    );
  }
  if (dab.opacity >= 1.0) {
    return strokeSourceOver(
      source: RgbaColor.fromArgbInt(dab.color),
      destination: destination,
      opacity: effectiveBrushPixelOpacity(dab: dab, coverage: coverage),
      flow: dab.flow,
      evening: evening,
    );
  }
  final source = RgbaColor.fromArgbInt(dab.color);
  final whole = effectiveSourceAlpha(
    source: source,
    opacity: coverage.coverage,
    flow: dab.flow,
  );
  final sourceAlpha = settledDabAlpha(
    laid: evening == null ? whole : evenedLaid(evening, whole),
    opacity: dab.opacity,
    destinationAlpha: destination.a / 65535.0,
  );
  if (sourceAlpha == null || sourceAlpha == 0.0) {
    return destination;
  }
  return strokeSourceOverAt(
    source: source,
    destination: destination,
    sourceAlpha: sourceAlpha,
  );
}

/// What a dab whose opacity is under one lays over [destinationAlpha]:
/// [laid] — what it would lay over nothing — scaled by how much of the way
/// to its [opacity] is left, or null where the pixel already stands there.
///
/// 🚨★★★A DAB SETTLES AT ITS OPACITY (F-205) — the law and its reasons are
/// written once, beside `qa_dab_source_alpha` in qa_engine.c; this is its
/// arithmetic, operation by operation, for the reference blend above and
/// the brush swatch (`rasterizeBrushStrokeSample`), which piled its dabs by
/// the old multiplied opacity until 2026-10-01. The tile kernel writes the
/// same grouping out inline.
double? settledDabAlpha({
  required double laid,
  required double opacity,
  required double destinationAlpha,
}) {
  if (destinationAlpha >= opacity) {
    return null;
  }
  return laid * (opacity - destinationAlpha) / (1.0 - destinationAlpha);
}

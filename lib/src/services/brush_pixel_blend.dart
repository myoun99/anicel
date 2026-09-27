import '../models/brush_dab.dart';
import '../models/brush_pixel_coverage.dart';
import '../models/rgba_color.dart';
import 'rgba_blend.dart';

double effectiveBrushPixelOpacity({
  required BrushDab dab,
  required BrushPixelCoverage coverage,
}) {
  return dab.opacity * coverage.coverage;
}

RgbaColor blendBrushDabPixelCoverage({
  required BrushDab dab,
  required BrushPixelCoverage coverage,
  required RgbaColor destination,
}) {
  if (dab.erase) {
    return rgbaDestinationOut(
      source: RgbaColor.fromArgbInt(dab.color),
      destination: destination,
      opacity: effectiveBrushPixelOpacity(dab: dab, coverage: coverage),
      flow: dab.flow,
    );
  }
  if (dab.opacity >= 1.0) {
    return rgbaSourceOver(
      source: RgbaColor.fromArgbInt(dab.color),
      destination: destination,
      opacity: effectiveBrushPixelOpacity(dab: dab, coverage: coverage),
      flow: dab.flow,
    );
  }
  // 🚨★★★A DAB SETTLES AT ITS OPACITY (F-205) — the law and its reasons
  // are written once, beside `qa_dab_source_alpha` in qa_engine.c; this is
  // the reference's copy of its arithmetic, operation by operation.
  final destinationAlpha = destination.a / 255.0;
  if (destinationAlpha >= dab.opacity) {
    return destination;
  }
  final source = RgbaColor.fromArgbInt(dab.color);
  final sourceAlpha =
      effectiveSourceAlpha(
        source: source,
        opacity: coverage.coverage,
        flow: dab.flow,
      ) *
      (dab.opacity - destinationAlpha) /
      (1.0 - destinationAlpha);
  if (sourceAlpha == 0.0) {
    return destination;
  }
  return rgbaSourceOverAt(
    source: source,
    destination: destination,
    sourceAlpha: sourceAlpha,
  );
}

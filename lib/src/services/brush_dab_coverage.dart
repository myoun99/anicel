
import '../models/brush_dab.dart';
import '../models/brush_pixel_coverage.dart';
import 'brush_dab_dirty_region.dart';
import 'brush_dab_tip_geometry.dart';
import 'brush_tip_mask_sampling.dart';

List<BrushPixelCoverage> brushPixelCoveragesForDab(BrushDab dab) {
  final dirtyRegion = dirtyRegionForBrushDab(dab);
  if (dirtyRegion == null) {
    return List<BrushPixelCoverage>.unmodifiable(const []);
  }

  final coverages = <BrushPixelCoverage>[];
  final tip = brushDabTipGeometry(dab);
  final tipMask = tip.tipMask;
  final isRound = tip.isRound;
  final isRotatedRect = tip.isRotatedRect;

  // Applies the dual-brush and paper-texture multiplications with the EXACT
  // multiplication order of the commit/live rasterizers (separate `*=`
  // steps; folding the factors first would change float associativity).
  final dualMask = dab.dualMask;
  final textureMask = dab.textureMask;
  double texturedCoverageAt(double coverage, int x, int y) {
    var result = coverage;
    if (dualMask != null) {
      result *= sampleBrushTipMaskTiledCoverage(
        mask: dualMask,
        dx: x + 0.5 - dab.center.x,
        dy: y + 0.5 - dab.center.y,
        period: dab.size * dab.dualMaskScale,
        offsetU: dab.dualOffsetU,
        offsetV: dab.dualOffsetV,
      );
      if (result <= 0.0) {
        return 0.0;
      }
    }
    if (textureMask != null) {
      final textureSample = sampleBrushTipMaskTiledCoverage(
        mask: textureMask,
        dx: x + 0.5,
        dy: y + 0.5,
        period: textureMask.size * dab.textureScale,
        offsetU: 0.0,
        offsetV: 0.0,
      );
      result *= (1.0 - dab.textureDensity) + dab.textureDensity * textureSample;
    }
    return result;
  }

  for (var y = dirtyRegion.top; y < dirtyRegion.bottomExclusive; y += 1) {
    for (var x = dirtyRegion.left; x < dirtyRegion.rightExclusive; x += 1) {
      final dx = x + 0.5 - dab.center.x;
      final dy = y + 0.5 - dab.center.y;
      double coverage;
      if (tipMask != null) {
        coverage = rotatedTipMaskCoverage(tip, tipMask, dx, dy);
      } else if (isRound) {
        coverage = analyticRoundTipCoverage(tip, dx, dy);
      } else {
        if (isRotatedRect && rotatedRectTipMisses(tip, dx, dy)) {
          continue;
        }
        coverage = 1.0;
      }
      if (coverage <= 0.0) {
        continue;
      }
      coverage = texturedCoverageAt(coverage, x, y);
      if (coverage <= 0.0) {
        continue;
      }
      coverages.add(BrushPixelCoverage(x: x, y: y, coverage: coverage));
    }
  }

  return List<BrushPixelCoverage>.unmodifiable(coverages);
}



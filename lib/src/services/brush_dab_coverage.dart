import '../models/brush_dab.dart';
import '../models/separable_blend_mode.dart';
import 'brush_stroke_blend.dart';
import '../models/brush_pixel_coverage.dart';
import 'brush_dab_dirty_region.dart';
import 'brush_dab_tip_geometry.dart';
import 'brush_tip_mask_sampling.dart';

/// THE reference traversal: every pixel a dab actually covers, with the
/// coverage it lands at, in scan order.
///
/// 🚨THIS IS THE ONE PLACE THE CASCADE IS WRITTEN. [brushPixelCoveragesForDab]
/// is this walk with a list on the end, so a caller that wants the list and a
/// caller that wants to consume pixels as they come are running the SAME
/// arithmetic rather than two transcriptions of it.
///
/// ⚠️Why the visitor exists at all: the list form allocates one
/// [BrushPixelCoverage] per covered pixel and then copies the whole thing for
/// `List.unmodifiable`. Measured on the brush roster (2026-09-10), one bake of
/// the 53 previews at a DPR-2 one-column cell made **8,480,380** of those
/// objects, and the container alone was 127 ms of an 833 ms raster. A consumer
/// that only wants to fold the pixels into a buffer never needed them.
///
/// ⛔The visitor is called once per covered pixel, so it must stay a plain
/// function call — no closure allocation inside the loop, nothing captured
/// that the loop could hoist.
void forEachBrushPixelCoverage(
  BrushDab dab,
  void Function(int x, int y, double coverage) visit,
) {
  final dirtyRegion = dirtyRegionForBrushDab(dab);
  if (dirtyRegion == null) {
    return;
  }

  final tip = brushDabTipGeometry(dab);
  final tipMask = tip.tipMask;
  final isRound = tip.isRound;

  // Applies the dual-brush and paper-texture multiplications with the EXACT
  // multiplication order of the commit/live rasterizers (separate `*=`
  // steps; folding the factors first would change float associativity).
  final dualMask = dab.dualMask;
  final textureMask = dab.textureMask;
  double texturedCoverageAt(double coverage, int x, int y) {
    var result = coverage;
    if (dualMask != null) {
      final dualSample = sampleBrushTipMaskTiledCoverage(
        mask: dualMask,
        dx: x + 0.5 - dab.center.x,
        dy: y + 0.5 - dab.center.y,
        period: dab.size * dab.dualMaskScale,
        offsetU: dab.dualOffsetU,
        offsetV: dab.dualOffsetV,
      );
      // 🚨THE DUAL TIP HAS A MODE (v33) — see [BrushDab.dualCompositeMode].
      //
      // ⛔MULTIPLY KEEPS ITS OWN LINE, AND THAT IS NOT AN OPTIMISATION. The
      // general form below is `lerp(coverage, B(dual, coverage), d)`, which
      // for B = multiply is the SAME NUMBER and NOT THE SAME BYTES:
      // `c * ((1-d) + d*s)` and `c*(1-d) + d*s*c` differ in the last bit of
      // a double. Every brush that ever shipped multiplies, so the old
      // expression stays exactly as written.
      if (dab.dualCompositeMode == SeparableBlendMode.multiply) {
        result *= (1.0 - dab.dualDensity) + dab.dualDensity * dualSample;
      } else {
        final combined = blendDualCoverage(
          dab.dualCompositeMode,
          dualSample,
          result,
        );
        result = result * (1.0 - dab.dualDensity) + dab.dualDensity * combined;
        if (result > 1.0) {
          result = 1.0;
        }
      }
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
        // A square dab is the fill and stamp verbs' "cover exactly this
        // rect", and the dab constructor refuses to build one that is
        // squashed or rotated — so there is no rotated-rect case to test.
        coverage = 1.0;
      }
      if (coverage <= 0.0) {
        continue;
      }
      // The brush's own EDGE, ahead of the tiled masks — the same place and
      // the same arithmetic as `blendDabTilesDart`, which is what makes this
      // a reference for it rather than a second opinion.
      coverage = dab.antiAlias.applyTo(coverage);
      if (coverage <= 0.0) {
        continue;
      }
      coverage = texturedCoverageAt(coverage, x, y);
      if (coverage <= 0.0) {
        continue;
      }
      visit(x, y, coverage);
    }
  }
}

/// [forEachBrushPixelCoverage] collected into a list.
///
/// ⚠️Kept because this is the shape the parity suites read — they compare
/// dab rasters pixel by pixel and want a value they can index and count. A
/// consumer that is going to fold the pixels into a buffer anyway should call
/// the visitor: this form's objects and its `unmodifiable` copy are pure cost
/// there, and at roster scale they are millions of them.
List<BrushPixelCoverage> brushPixelCoveragesForDab(BrushDab dab) {
  final coverages = <BrushPixelCoverage>[];
  forEachBrushPixelCoverage(
    dab,
    (x, y, coverage) =>
        coverages.add(BrushPixelCoverage(x: x, y: y, coverage: coverage)),
  );
  return List<BrushPixelCoverage>.unmodifiable(coverages);
}

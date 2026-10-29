import '../models/brush_dab.dart';
import '../models/brush_texture_mode.dart';
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
  void Function(int x, int y, double coverage, double ceiling) visit,
) {
  final dirtyRegion = dirtyRegionForBrushDab(dab);
  if (dirtyRegion == null) {
    return;
  }

  final tip = brushDabTipGeometry(dab);
  final edge = brushDabEdgeLaw(dab);
  final edgeHeld = tipHoldsAnEdge(tip, edge);

  // Applies the paper-texture multiplication with the EXACT multiplication
  // order of the commit/live rasterizers (separate `*=` steps; folding the
  // factors first would change float associativity).
  final textureMask = dab.textureMask;
  double texturedCoverageAt(double coverage, int x, int y) {
    var result = coverage;
    if (textureMask != null) {
      final textureSample = sampleBrushTipMaskTiledCoverage(
        mask: textureMask,
        dx: x + 0.5,
        dy: y + 0.5,
        period: textureMask.size * dab.textureScale,
        offsetU: 0.0,
        offsetV: 0.0,
      );
      // ⛔MULTIPLY KEEPS ITS OWN LINE, as the dual view's does: every brush
      // that shipped before F-451 multiplies, and its bytes stay as written.
      if (dab.textureMode == BrushTextureMode.height) {
        result = paperHeightCoverage(result, textureSample, dab.textureDensity);
      } else {
        result *=
            (1.0 - dab.textureDensity) + dab.textureDensity * textureSample;
      }
    }
    return result;
  }

  for (var y = dirtyRegion.top; y < dirtyRegion.bottomExclusive; y += 1) {
    for (var x = dirtyRegion.left; x < dirtyRegion.rightExclusive; x += 1) {
      final dx = x + 0.5 - dab.center.x;
      final dy = y + 0.5 - dab.center.y;
      var coverage = tipCoverageAt(tip, dx, dy);
      if (coverage <= 0.0) {
        continue;
      }
      // The brush's own EDGE, ahead of the tiled masks — the same place and
      // the same arithmetic as `blendDabTilesDart`, which is what makes this
      // a reference for it rather than a second opinion.
      coverage = brushEdgeApplied(edge, coverage);
      if (coverage <= 0.0) {
        continue;
      }
      // What of it is the tip's EDGE, which does not pile — the kernel's
      // ceiling, worked out where the kernel works it ([tipPileAt]).
      final ceiling = edgeHeld
          ? edgeCeiling(coverage, tipPileAt(tip, dx, dy))
          : 1.0;
      coverage = texturedCoverageAt(coverage, x, y);
      if (coverage <= 0.0) {
        continue;
      }
      visit(x, y, coverage, ceiling);
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
    (x, y, coverage, ceiling) => coverages.add(
      BrushPixelCoverage(x: x, y: y, coverage: coverage, ceiling: ceiling),
    ),
  );
  return List<BrushPixelCoverage>.unmodifiable(coverages);
}

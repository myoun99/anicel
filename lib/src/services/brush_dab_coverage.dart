import 'dart:math' as math;

import '../models/brush_dab.dart';
import '../models/brush_pixel_coverage.dart';
import '../models/brush_tip_shape.dart';
import 'brush_dab_dirty_region.dart';
import 'brush_dab_tip_geometry.dart';
import 'brush_tip_mask_sampling.dart';

List<BrushPixelCoverage> brushPixelCoveragesForDab(BrushDab dab) {
  final dirtyRegion = dirtyRegionForBrushDab(dab);
  if (dirtyRegion == null) {
    return List<BrushPixelCoverage>.unmodifiable(const []);
  }

  final coverages = <BrushPixelCoverage>[];
  final (
    :radius,
    :hardRadius,
    :isRound,
    :tipMask,
    :isEllipse,
    :isRotatedRect,
    :tipCos,
    :tipSin,
    :inverseRoundness,
  ) = brushDabTipGeometry(dab);
  final minorRadius = radius * dab.roundness;

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
      if (tipMask != null) {
        final dx = x + 0.5 - dab.center.x;
        final dy = y + 0.5 - dab.center.y;
        final tipU = dx * tipCos - dy * tipSin;
        final tipV = (dx * tipSin + dy * tipCos) * inverseRoundness;
        if (tipU.abs() > radius || tipV.abs() > radius) {
          continue;
        }
        var coverage = sampleBrushTipMaskCoverage(
          mask: tipMask,
          tipU: tipU,
          tipV: tipV,
          radius: radius,
        );
        if (coverage <= 0.0) {
          continue;
        }
        coverage = texturedCoverageAt(coverage, x, y);
        if (coverage <= 0.0) {
          continue;
        }
        coverages.add(BrushPixelCoverage(x: x, y: y, coverage: coverage));
        continue;
      }
      switch (dab.tipShape) {
        case BrushTipShape.square:
          if (isRotatedRect) {
            final dx = x + 0.5 - dab.center.x;
            final dy = y + 0.5 - dab.center.y;
            final tipU = dx * tipCos - dy * tipSin;
            final tipV = dx * tipSin + dy * tipCos;
            if (tipU.abs() > radius || tipV.abs() > minorRadius) {
              continue;
            }
          }
          var coverage = 1.0;
          coverage = texturedCoverageAt(coverage, x, y);
          if (coverage <= 0.0) {
            continue;
          }
          coverages.add(BrushPixelCoverage(x: x, y: y, coverage: coverage));
        case BrushTipShape.round:
          final dx = x + 0.5 - dab.center.x;
          final dy = y + 0.5 - dab.center.y;
          double distance;
          if (isEllipse) {
            final tipU = dx * tipCos - dy * tipSin;
            final tipV = (dx * tipSin + dy * tipCos) * inverseRoundness;
            distance = math.sqrt(tipU * tipU + tipV * tipV);
          } else {
            distance = math.sqrt(dx * dx + dy * dy);
          }

          if (distance > radius) {
            continue;
          }

          var coverage = _roundCoverage(
            distance: distance,
            radius: radius,
            hardRadius: hardRadius,
          );
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
  }

  return List<BrushPixelCoverage>.unmodifiable(coverages);
}

double _roundCoverage({
  required double distance,
  required double radius,
  required double hardRadius,
}) {
  if (distance <= hardRadius) {
    return 1.0;
  }

  final edgeSpan = radius - hardRadius;
  if (edgeSpan <= 0.0) {
    return 1.0;
  }

  return (1.0 - ((distance - hardRadius) / edgeSpan)).clamp(0.0, 1.0);
}

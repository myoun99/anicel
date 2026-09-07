import 'dart:typed_data';

import '../models/brush_tip_mask.dart';

/// The bilinear blend of a texel quad, clamped to unit coverage — THE lerp
/// grouping every mask sampler in this file shares.
///
/// ⛔THE GROUPING IS THE CONTRACT, not a detail: the two lattice samplers
/// are pinned byte-for-byte against the two scalar ones, and that parity
/// holds only while all four multiply and add in exactly this order (top
/// row, bottom row, then vertically). Four hand-written copies of it is
/// exactly where a regrouping breaks the parity silently, so there is one.
///
/// The one-minus fractions are ARGUMENTS: the lattices already hold them
/// precomputed per axis pixel, and recomputing `1 - f` here would put an
/// arithmetic op back into the hot loop the lattices exist to empty.
/// [vm:prefer-inline] keeps this a leaf, not a per-pixel call.
@pragma('vm:prefer-inline')
double bilinearMix({
  required double topLeft,
  required double topRight,
  required double bottomLeft,
  required double bottomRight,
  required double fractionX,
  required double oneMinusFractionX,
  required double fractionY,
  required double oneMinusFractionY,
}) =>
    ((topLeft * oneMinusFractionX + topRight * fractionX) * oneMinusFractionY +
            (bottomLeft * oneMinusFractionX + bottomRight * fractionX) *
                fractionY)
        .clamp(0.0, 1.0);

/// Bilinear coverage sample of a sampled brush tip at a tip-space offset.
///
/// [tipU]/[tipV] are the pixel-center offset rotated onto the tip axes with
/// the minor axis already stretched by `1/roundness` (the same tip-space
/// transform the parametric elliptical tips use), so the mask always maps
/// onto the square `[-radius, radius]^2`. Texels outside the mask read as
/// zero, so coverage fades out cleanly at the tip border.
///
/// This is THE single coverage implementation for sampled tips: the commit
/// rasterizer, the live rasterizer, and the per-pixel oracle all call it, so
/// live and committed pixels stay byte-identical by construction.
double sampleBrushTipMaskCoverage({
  required BrushTipMask mask,
  required double tipU,
  required double tipV,
  required double radius,
}) {
  final scale = mask.size / (2.0 * radius);
  final maskX = (tipU + radius) * scale - 0.5;
  final maskY = (tipV + radius) * scale - 0.5;
  final x0 = maskX.floor();
  final y0 = maskY.floor();
  final fractionX = maskX - x0;
  final fractionY = maskY - y0;

  final size = mask.size;
  final alpha = mask.alphaNormalized;
  double texel(int x, int y) {
    if (x < 0 || y < 0 || x >= size || y >= size) {
      return 0.0;
    }
    return alpha[y * size + x];
  }

  return bilinearMix(
    topLeft: texel(x0, y0),
    topRight: texel(x0 + 1, y0),
    bottomLeft: texel(x0, y0 + 1),
    bottomRight: texel(x0 + 1, y0 + 1),
    fractionX: fractionX,
    oneMinusFractionX: 1.0 - fractionX,
    fractionY: fractionY,
    oneMinusFractionY: 1.0 - fractionY,
  );
}

/// Precomputed one-axis lattice of [sampleBrushTipMaskCoverage] for
/// UNROTATED tips (`angleDegrees == 0`): tip-space u then depends only on
/// the pixel's x (and v only on y), so the per-pixel mask coordinate,
/// texel pair and fraction can be computed once per axis with EXACTLY the
/// scalar sampler's arithmetic. The rasterizer hot loops sample through
/// two of these; the scalar function stays the reference (the parity
/// tests pin grid == scalar byte-for-byte through the blend).
class BrushTipMaskAxisLattice {
  BrushTipMaskAxisLattice._(
    this.texel0,
    this.fraction,
    this.oneMinusFraction,
    this.inRange,
  );

  /// Floor texel index per pixel along the axis (may be -1 or size-1; the
  /// sampler reads out-of-range texels as zero, exactly like the scalar's
  /// bounds check).
  final Int32List texel0;
  final Float64List fraction;
  final Float64List oneMinusFraction;

  /// Whether the pixel passes the scalar path's `|tip coordinate| > radius`
  /// cull (1 = sample, 0 = skip the pixel entirely).
  final Uint8List inRange;

  /// Lattice for pixels `start..start+count-1` whose tip-space coordinate
  /// is `(pixel + 0.5 - center) * inverseRoundness` (pass 1.0 for the
  /// unscaled major axis).
  factory BrushTipMaskAxisLattice.compute({
    required BrushTipMask mask,
    required double radius,
    required int start,
    required int count,
    required double center,
    double inverseRoundness = 1.0,
  }) {
    final texel0 = Int32List(count);
    final fraction = Float64List(count);
    final oneMinusFraction = Float64List(count);
    final inRange = Uint8List(count);
    // Same expression as the scalar sampler: scale, then
    // (tip + radius) * scale - 0.5.
    final scale = mask.size / (2.0 * radius);
    for (var index = 0; index < count; index += 1) {
      final tip = ((start + index) + 0.5 - center) * inverseRoundness;
      inRange[index] = tip.abs() > radius ? 0 : 1;
      final maskCoord = (tip + radius) * scale - 0.5;
      final floor = maskCoord.floor();
      texel0[index] = floor;
      final f = maskCoord - floor;
      fraction[index] = f;
      oneMinusFraction[index] = 1.0 - f;
    }
    return BrushTipMaskAxisLattice._(
      texel0,
      fraction,
      oneMinusFraction,
      inRange,
    );
  }
}

/// Samples an unrotated tip mask through two precomputed axis lattices —
/// byte-identical to [sampleBrushTipMaskCoverage] (same texel bounds
/// semantics, same lerp grouping, same clamp).
double sampleBrushTipMaskCoverageLattice({
  required BrushTipMask mask,
  required BrushTipMaskAxisLattice uAxis,
  required int uIndex,
  required BrushTipMaskAxisLattice vAxis,
  required int vIndex,
}) {
  final size = mask.size;
  final alpha = mask.alphaNormalized;
  final x0 = uAxis.texel0[uIndex];
  final y0 = vAxis.texel0[vIndex];
  final x1 = x0 + 1;
  final y1 = y0 + 1;
  final fractionX = uAxis.fraction[uIndex];
  final oneMinusFractionX = uAxis.oneMinusFraction[uIndex];

  // Out-of-range texels read as ZERO, exactly like the scalar sampler's
  // bounds check — and a zero texel contributes exactly 0.0 to the row
  // lerp, so a whole out-of-range row still lands on 0.0.
  final row0 = y0 >= 0 && y0 < size ? y0 * size : -1;
  final row1 = y1 >= 0 && y1 < size ? y1 * size : -1;
  final x0In = x0 >= 0 && x0 < size;
  final x1In = x1 >= 0 && x1 < size;

  return bilinearMix(
    topLeft: row0 >= 0 && x0In ? alpha[row0 + x0] : 0.0,
    topRight: row0 >= 0 && x1In ? alpha[row0 + x1] : 0.0,
    bottomLeft: row1 >= 0 && x0In ? alpha[row1 + x0] : 0.0,
    bottomRight: row1 >= 0 && x1In ? alpha[row1 + x1] : 0.0,
    fractionX: fractionX,
    oneMinusFractionX: oneMinusFractionX,
    fractionY: vAxis.fraction[vIndex],
    oneMinusFractionY: vAxis.oneMinusFraction[vIndex],
  );
}

/// Precomputed one-axis lattice of [sampleBrushTipMaskTiledCoverage]: the
/// tiled samplers' u depends only on x and v only on y (they never rotate),
/// so the wrapped texel pair and fraction are a pure function of the axis
/// pixel — computed here once per dab with EXACTLY the scalar arithmetic.
class TiledMaskAxisLattice {
  TiledMaskAxisLattice._(
    this.texel0,
    this.texel1,
    this.fraction,
    this.oneMinusFraction,
  );

  /// WRAPPED texel indices per pixel along the axis.
  final Int32List texel0;
  final Int32List texel1;
  final Float64List fraction;
  final Float64List oneMinusFraction;

  /// Lattice for pixels `start..start+count-1`; the sample coordinate is
  /// `((pixel + 0.5 + originOffset) / period + offset)` wrapped to [0, 1) —
  /// pass `originOffset = -center` for dab-anchored masks (dual) and `0`
  /// for canvas-anchored ones (paper texture).
  factory TiledMaskAxisLattice.compute({
    required BrushTipMask mask,
    required int start,
    required int count,
    required double originOffset,
    required double period,
    required double offset,
  }) {
    final size = mask.size;
    final texel0 = Int32List(count);
    final texel1 = Int32List(count);
    final fraction = Float64List(count);
    final oneMinusFraction = Float64List(count);
    for (var index = 0; index < count; index += 1) {
      // Same expressions as the scalar sampler.
      final d = (start + index) + 0.5 + originOffset;
      var u = d / period + offset;
      u -= u.floorToDouble();
      final maskCoord = u * size - 0.5;
      final floor = maskCoord.floor();
      final f = maskCoord - floor;
      texel0[index] = ((floor % size) + size) % size;
      texel1[index] = (((floor + 1) % size) + size) % size;
      fraction[index] = f;
      oneMinusFraction[index] = 1.0 - f;
    }
    return TiledMaskAxisLattice._(texel0, texel1, fraction, oneMinusFraction);
  }
}

/// Samples a tiled mask through two precomputed axis lattices —
/// byte-identical to [sampleBrushTipMaskTiledCoverage].
double sampleBrushTipMaskTiledCoverageLattice({
  required BrushTipMask mask,
  required TiledMaskAxisLattice uAxis,
  required int uIndex,
  required TiledMaskAxisLattice vAxis,
  required int vIndex,
}) {
  final size = mask.size;
  final alpha = mask.alphaNormalized;
  final x0 = uAxis.texel0[uIndex];
  final x1 = uAxis.texel1[uIndex];
  final row0 = vAxis.texel0[vIndex] * size;
  final row1 = vAxis.texel1[vIndex] * size;
  final fractionX = uAxis.fraction[uIndex];
  final oneMinusFractionX = uAxis.oneMinusFraction[uIndex];

  return bilinearMix(
    topLeft: alpha[row0 + x0],
    topRight: alpha[row0 + x1],
    bottomLeft: alpha[row1 + x0],
    bottomRight: alpha[row1 + x1],
    fractionX: fractionX,
    oneMinusFractionX: oneMinusFractionX,
    fractionY: vAxis.fraction[vIndex],
    oneMinusFractionY: vAxis.oneMinusFraction[vIndex],
  );
}

/// Tiled (wrapping) bilinear coverage sample — the dual-brush texture.
///
/// [dx]/[dy] are the pixel-center offset from the dab center in canvas
/// pixels, [period] the tile size in canvas pixels, and [offsetU]/[offsetV]
/// the dab's random phase in tile fractions. Like [sampleBrushTipMaskCoverage]
/// this is THE single implementation all rasterizers call, keeping live and
/// committed pixels byte-identical.
double sampleBrushTipMaskTiledCoverage({
  required BrushTipMask mask,
  required double dx,
  required double dy,
  required double period,
  required double offsetU,
  required double offsetV,
}) {
  final size = mask.size;
  final alpha = mask.alphaNormalized;
  var u = dx / period + offsetU;
  var v = dy / period + offsetV;
  u -= u.floorToDouble();
  v -= v.floorToDouble();
  final maskX = u * size - 0.5;
  final maskY = v * size - 0.5;
  final x0 = maskX.floor();
  final y0 = maskY.floor();
  final fractionX = maskX - x0;
  final fractionY = maskY - y0;

  double texel(int x, int y) {
    final wrappedX = ((x % size) + size) % size;
    final wrappedY = ((y % size) + size) % size;
    return alpha[wrappedY * size + wrappedX];
  }

  return bilinearMix(
    topLeft: texel(x0, y0),
    topRight: texel(x0 + 1, y0),
    bottomLeft: texel(x0, y0 + 1),
    bottomRight: texel(x0 + 1, y0 + 1),
    fractionX: fractionX,
    oneMinusFractionX: 1.0 - fractionX,
    fractionY: fractionY,
    oneMinusFractionY: 1.0 - fractionY,
  );
}

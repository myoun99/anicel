import '../models/brush_tip_mask.dart';

/// The bilinear blend of a texel quad, clamped to unit coverage — THE lerp
/// grouping both mask samplers in this file share (top row, bottom row,
/// then vertically), so neither groups it another way.
///
/// ↩️Two lattice samplers — the Dart dab loop's, which held the fractions
/// precomputed per axis pixel and handed them in (hence the one-minus
/// fractions as arguments) — were pinned byte for byte against these till
/// 2026-11-14, and went with that loop (board
/// `the-off-engine-cpu-commit-lives-only-for-tests`).
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
/// This is THE single coverage implementation for sampled tips on the CPU
/// (`tipCoverageAt` — the brush swatch's, a stamp's tip); the engine's is
/// `dab.wgsl`'s. ↩️The commit and the live rasterizer read it too, till
/// the engine took them (the last of them 2026-11-14).
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

/// Tiled (wrapping) bilinear coverage sample — the dual-brush texture.
///
/// [dx]/[dy] are the pixel-center offset from the dab center in canvas
/// pixels, [period] the tile size in canvas pixels, and [offsetU]/[offsetV]
/// the dab's random phase in tile fractions. Like [sampleBrushTipMaskCoverage]
/// this is THE single implementation on the CPU
/// (`forEachBrushPixelCoverage`).
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

import 'dart:typed_data';

import '../guide_geometry.dart' show GuideTransform;
import '../selection_affine.dart';
import 'resample_kernel.dart';

/// The selection transform's door onto R1: the three destination-to-source
/// folds it needs, the nine the engine reads of each, and the one radius
/// floor every warp is handed.

/// The footprint floor, named once so both sides of the native/Dart split
/// are handed the same number.
///
/// It is no longer an override — the kernel's floor is 1.0 for both modes
/// now, since a floor above the true extent has no meaning under a
/// coverage weight. The constant survives because the engine REQUIRES an
/// explicit floor, and two call sites free to disagree is exactly how the
/// picture on screen and the picture Enter lands come out of different
/// kernels.
const double kSelectionResampleRadiusFloor = 1.0;

/// The nine elements in the order the engine reads them.
Float64List resampleTransformElements(ResampleTransform t) =>
    Float64List.fromList(<double>[t.a, t.b, t.c, t.d, t.e, t.f, t.g, t.h, t.i]);

/// The free-transform affine, folded into the kernel's destination-pixel
/// index → source-pixel index form.
///
/// The tool's own inverse (`canvas_selection.dart`) computes a CANVAS-space
/// source point `p = S⁻¹·R⁻¹·(q − pivot − t) + pivot` from a canvas-space
/// destination point `q`, and the sampler then subtracts `srcLeft` and a
/// half pixel to reach a source index. The kernel instead takes destination
/// INDICES and adds the half pixel itself, so the fold is that whole chain
/// written as one matrix — no ±0.5 appears below, because the kernel
/// supplies both halves.
///
/// Two traps, each worth about a pixel and each silent (the picture still
/// looks right, just moved): **b takes +sin and d takes −sin** — this is
/// S⁻¹·R⁻¹, not a transposed R⁻¹·S⁻¹ — and **the inverse scale multiplies
/// the whole offset bracket but not the trailing `pivot − src`**.
ResampleTransform selectionAffineResampleTransform({
  required SelectionAffine affine,
  required double srcLeft,
  required double srcTop,
  required int outLeft,
  required int outTop,
}) {
  final turn = affine.turn;
  final invSx = 1 / affine.sx;
  final invSy = 1 / affine.sy;
  final offset = turn.back.apply(
    outLeft - affine.pivot.x - affine.appliedTx,
    outTop - affine.pivot.y - affine.appliedTy,
  );
  return ResampleTransform(
    a: turn.cos * invSx,
    b: turn.sin * invSx,
    c: offset.x * invSx + affine.pivot.x - srcLeft,
    d: -turn.sin * invSy,
    e: turn.cos * invSy,
    f: offset.y * invSy + affine.pivot.y - srcTop,
  );
}

/// A plane affine that takes destination CANVAS points to source canvas
/// points, folded the same way: for an output whose first pixel is at
/// ([outLeft], [outTop]) reading a source whose first pixel is at
/// ([srcLeft], [srcTop]). The kernel supplies both half pixels, as above.
///
/// What carries a picture through a row's PLACEMENT — any affine, a shear
/// included, which [selectionAffineResampleTransform]'s scale-then-turn
/// cannot say: the fill reading a posed layer, a stamp crossing onto the
/// canvas and back.
ResampleTransform planeResampleTransform({
  required GuideTransform toSource,
  required num srcLeft,
  required num srcTop,
  required int outLeft,
  required int outTop,
}) => ResampleTransform(
  a: toSource.a,
  b: toSource.c,
  c: toSource.a * outLeft + toSource.c * outTop + toSource.tx - srcLeft,
  d: toSource.b,
  e: toSource.d,
  f: toSource.b * outLeft + toSource.d * outTop + toSource.ty - srcTop,
);

/// The perspective quad's homography, folded the same way.
///
/// [h] maps canvas destination to canvas source (the tool solves that
/// direction directly, so there is no matrix inversion here). The fold is
/// the matrix product `translate(−srcLeft, −srcTop) · h · translate(outLeft,
/// outTop)`: shifting the source origin means subtracting `srcLeft` times
/// the homogeneous row from the u row, which is the only part that is not
/// obvious.
///
/// An affine quad stays affine through it — `h[6] = h[7] = 0` makes the new
/// `i` exactly 1, so the kernel keeps its divide-free path.
ResampleTransform selectionQuadResampleTransform({
  required Float64List h,
  required double srcLeft,
  required double srcTop,
  required int outLeft,
  required int outTop,
}) {
  final w = h[6] * outLeft + h[7] * outTop + h[8];
  return ResampleTransform(
    a: h[0] - srcLeft * h[6],
    b: h[1] - srcLeft * h[7],
    c: (h[0] * outLeft + h[1] * outTop + h[2]) - srcLeft * w,
    d: h[3] - srcTop * h[6],
    e: h[4] - srcTop * h[7],
    f: (h[3] * outLeft + h[4] * outTop + h[5]) - srcTop * w,
    g: h[6],
    h: h[7],
    i: w,
  );
}

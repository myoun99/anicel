import 'dart:typed_data';

import '../../models/canvas_point.dart';
import '../../native/qa_native_engine.dart';
import '../canvas_selection.dart' show SelectionAffine;
import 'resample_kernel.dart';

/// The selection transform's door onto the shared resampler: the three
/// destination-to-source folds it needs, and the one function that decides
/// native-or-Dart.
///
/// It exists so preview and commit cannot diverge. The Dart reference
/// derives its radius floor from the mode while the native binding demands
/// one explicitly, so two call sites is all it takes for the picture on
/// screen and the picture Enter lands to come out of different kernels with
/// nothing in the type system to notice.

/// The footprint floor the selection transform uses, overriding the
/// mode-derived default in [resampleRadiusFloor].
///
/// 1.0, not the kernel's 1.5 for Pick, and the difference is destructive
/// rather than cosmetic. Measured on a 40×40 two-value fixture holding a
/// 1px diagonal and a 1px vertical (63 ink pixels), driven straight through
/// the reference:
///
/// | rotation | floor 1.5 | floor 1.0 |
/// |---|---|---|
/// | 90° | 32 ink | **63 ink** (exact permutation) |
/// | 15° | 33 ink | 47 ink |
///
/// The 1.5 was tuned on a dense 16-colour production cel, where the extra
/// ring smooths jagged spurs along a rotated edge. On line art the same
/// ring lets ground pixels the preimage never touched outvote the one it
/// did, which is the very breach the kernel's magnification early-out
/// exists to prevent — only here it is reached from the other side.
///
/// Blend's default already IS 1.0, so one constant serves both modes and
/// the two share it by construction.
const double kSelectionResampleRadiusFloor = 1.0;

/// Resample [src] into [dst] through [transform], native when the engine is
/// loaded and the Dart reference otherwise.
///
/// The two produce identical bytes — that is what
/// `test/native/resample_parity_test.dart` exists to hold — so which one
/// ran is invisible in the result and only shows in the clock.
void resampleSelectionInto({
  required Uint8List src,
  required int srcWidth,
  required int srcHeight,
  required Uint8List dst,
  required int dstWidth,
  required int dstHeight,
  required ResampleTransform transform,
  required ResampleMode mode,
}) {
  final engine = QaNativeEngine.instance;
  if (engine != null &&
      engine.resampleRgbaInto(
        src: src,
        srcWidth: srcWidth,
        srcHeight: srcHeight,
        dst: dst,
        dstWidth: dstWidth,
        dstHeight: dstHeight,
        inverse: resampleTransformElements(transform),
        radiusFloor: kSelectionResampleRadiusFloor,
        mode: resampleModeCode(mode),
      )) {
    return;
  }
  resampleRgbaReferenceInto(
    src: src,
    srcWidth: srcWidth,
    srcHeight: srcHeight,
    dst: dst,
    dstWidth: dstWidth,
    dstHeight: dstHeight,
    transform: transform,
    mode: mode,
    radiusFloor: kSelectionResampleRadiusFloor,
  );
}

/// The nine elements in the order the C kernel reads them.
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
  final cos = affine.cosTheta;
  final sin = affine.sinTheta;
  final invSx = 1 / affine.sx;
  final invSy = 1 / affine.sy;
  final offsetX = outLeft - affine.pivot.x - affine.tx;
  final offsetY = outTop - affine.pivot.y - affine.ty;
  return ResampleTransform(
    a: cos * invSx,
    b: sin * invSx,
    c: (offsetX * cos + offsetY * sin) * invSx + affine.pivot.x - srcLeft,
    d: -sin * invSy,
    e: cos * invSy,
    f: (offsetX * -sin + offsetY * cos) * invSy + affine.pivot.y - srcTop,
  );
}

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

/// One mesh triangle's destination-to-source map.
///
/// Barycentric interpolation of three source corners over a destination
/// triangle is an AFFINE function of the destination point — which is why
/// the mesh can share the kernel at all, rather than needing a warp path of
/// its own. [d0]/[d1]/[d2] are the destination corners, [s0]/[s1]/[s2] the
/// source ones, [denominator] the edge cross product the rasteriser has
/// already computed, and [left]/[top] the CLIPPED destination bbox origin
/// the resampled rectangle starts at.
ResampleTransform selectionTriangleResampleTransform({
  required CanvasPoint d0,
  required CanvasPoint d1,
  required CanvasPoint d2,
  required CanvasPoint s0,
  required CanvasPoint s1,
  required CanvasPoint s2,
  required double denominator,
  required int left,
  required int top,
  required double srcLeft,
  required double srcTop,
}) {
  final e1x = d1.x - d0.x;
  final e1y = d1.y - d0.y;
  final e2x = d2.x - d0.x;
  final e2y = d2.y - d0.y;
  final f1x = s1.x - s0.x;
  final f1y = s1.y - s0.y;
  final f2x = s2.x - s0.x;
  final f2y = s2.y - s0.y;
  final a = (e2y * f1x - e1y * f2x) / denominator;
  final b = (e1x * f2x - e2x * f1x) / denominator;
  final d = (e2y * f1y - e1y * f2y) / denominator;
  final e = (e1x * f2y - e2x * f1y) / denominator;
  return ResampleTransform(
    a: a,
    b: b,
    c: a * (left - d0.x) + b * (top - d0.y) + s0.x - srcLeft,
    d: d,
    e: e,
    f: d * (left - d0.x) + e * (top - d0.y) + s0.y - srcTop,
  );
}

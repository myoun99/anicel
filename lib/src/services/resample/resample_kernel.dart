/// R1's vocabulary: the modes and the map the app hands the one image
/// resampler, the engine's (`resample.wgsl`, through the app's door
/// `resampleOnTheEngine`). Why two modes and not two resamplers, the
/// contract Pick keeps and the footprint each mode reads are said beside
/// the kernel that keeps them.
///
/// ↩️This file was R1 itself, on the CPU — the reference a C mirror
/// (`qa_resample_rgba`) and then the engine were pinned to. A float's warps
/// went to the engine first (float-warp-resamples-in-the-c-engine,
/// 2026-11-11), a tip's coverage last (tip-coverage-is-a-second-r1,
/// 2026-11-13), and the reference went with it: its contracts are pinned
/// on the engine's R1 (`resample_kernel_test.dart`), against the same
/// oracle (`coverage_truth.dart`).
enum ResampleMode {
  /// Weighted mean through a tent kernel. Produces new colours; that is the
  /// point.
  ///
  /// Tent, not a cubic: cubics have negative lobes, and a negative lobe
  /// beside a dark line produces a pixel BRIGHTER than anything in its own
  /// footprint — the pale halo that shows up along every inked edge. A tent
  /// is a convex combination, so its output is confined to the min..max of
  /// the pixels it read and the halo cannot exist.
  blend,

  /// Area argmax over a supersampled preimage. The source colours come
  /// through untouched.
  pick,
}

/// Fully transparent — what R1 lands where a destination pixel's preimage
/// falls outside the source (`resample_texel`'s 0 outside it).
///
/// Alpha 0 rather than a background colour keeps the Pick contract honest
/// at the edge: the rule is "no new colours INSIDE, plus one designated
/// empty token", and alpha 0 is that token. It is also still two-valued
/// alpha, so it does not smuggle in the partial alpha the whole feature
/// exists to avoid.
const int kResampleOutsideToken = 0x00000000;

/// A destination-to-source map, row-major, with the homogeneous row last:
///
///     u' = a*x + b*y + c
///     v' = d*x + e*y + f
///     w  = g*x + h*y + i        (affine: 0, 0, 1)
///     (u, v) = (u'/w, v'/w)
///
/// One shape covers translation, scale, rotation, shear and the perspective
/// quad, so R1 has a single geometry path. [isAffine]: the homogeneous row
/// is 0, 0, 1.
class ResampleTransform {
  ResampleTransform({
    required this.a,
    required this.b,
    required this.c,
    required this.d,
    required this.e,
    required this.f,
    this.g = 0,
    this.h = 0,
    this.i = 1,
  }) : isAffine = g == 0 && h == 0 && i == 1;

  /// Identity.
  ResampleTransform.identity()
    : a = 1,
      b = 0,
      c = 0,
      d = 0,
      e = 1,
      f = 0,
      g = 0,
      h = 0,
      i = 1,
      isAffine = true;

  /// Inverse of "scale about the origin by [scale], then translate by
  /// ([tx], [ty])" — the shape import fit and screen zoom both need.
  factory ResampleTransform.scaleTranslate({
    required double scale,
    double tx = 0,
    double ty = 0,
  }) {
    final inverse = 1 / scale;
    return ResampleTransform(
      a: inverse,
      b: 0,
      c: -tx * inverse,
      d: 0,
      e: inverse,
      f: -ty * inverse,
    );
  }

  final double a;
  final double b;
  final double c;
  final double d;
  final double e;
  final double f;
  final double g;
  final double h;
  final double i;
  final bool isAffine;
}

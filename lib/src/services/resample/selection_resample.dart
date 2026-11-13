import 'dart:typed_data';

import 'package:gpu_engine/gpu_engine.dart' show GpuSampling, GpuStampPicture;

import '../../core/on_a_worker.dart';
import '../../native/app_gpu_engine.dart';
import '../guide_geometry.dart' show GuideTransform;
import '../selection_affine.dart';
import 'resample_kernel.dart';

/// The app's door onto R1 — the engine's: the three destination-to-source
/// folds a selection transform needs, the nine the engine reads of each,
/// the one radius floor every warp is handed, the sampling each mode names,
/// and a picture carried through it and read back ([resampleOnTheEngine]).

/// Lower bound for the footprint radius — **Blend's radius, and only
/// Blend's** — the one every warp is handed: the engine REQUIRES an
/// explicit floor, and two call sites free to disagree is exactly how the
/// picture on screen and the picture Enter lands come out of different
/// kernels.
///
/// It stops a tent narrower than a pixel, which would sample nothing but
/// the pixel it sits on and make Blend a point sampler. That is the only
/// job it has left.
///
/// It used to be 1.5 for Pick, on the theory that a wider ring smooths the
/// jagged spurs a rotation leaves along an edge — measured on a dense
/// production cel, where it did. That number stopped meaning anything the
/// moment Pick's weight became a measure of AREA: a floor above the true
/// extent claims the preimage reaches further than it does, so the vote
/// counts area the destination pixel never covered. It was not a quality
/// knob, it was a lie about geometry, and it cost what a lie about
/// geometry costs — on 1px line art the inflated ring let ground outvote
/// ink and deleted the drawing. Pick has since stopped having a radius at
/// all: it supersamples the preimage instead of gathering taps around it,
/// and ignores whatever floor it is handed.
///
/// ↩️The Dart reference R1 defaulted the same number by mode
/// (`resampleRadiusFloor`), a second answer to one question; it went with
/// that R1 (tip-coverage-is-a-second-r1, 2026-11-13).
const double kSelectionResampleRadiusFloor = 1.0;

/// The nine elements in the order the engine reads them.
Float64List resampleTransformElements(ResampleTransform t) =>
    Float64List.fromList(<double>[t.a, t.b, t.c, t.d, t.e, t.f, t.g, t.h, t.i]);

/// R1's sampling of [mode], as the engine names it.
GpuSampling resampleSampling(ResampleMode mode) => switch (mode) {
  ResampleMode.blend => GpuSampling.blend,
  ResampleMode.pick => GpuSampling.pick,
};

/// [src] — straight RGBA8, [srcWidth] × [srcHeight] — carried through
/// [transform] by R1 in [mode], on the app's engine: the [dstWidth] ×
/// [dstHeight] picture it lands, straight RGBA8, nothing where the map
/// lands nothing.
///
/// 🗣️tip-coverage-is-a-second-r1-Q1 (유저 2026-11-12: 「미리 만들어 둔다 —
/// 엔진이 열리면 기다리지 않고 받아 둔다」): it waits for the engine to be
/// open and its kernels compiled ([openAppGpuEngine], `AppKernels.ready`) —
/// opened and compiled off this isolate, never on it — and the GPU's answer
/// is read on a worker ([onAWorker]), so the isolate that asks goes on
/// meanwhile. ↩️A tip's coverage came down through a Dart R1 of its own,
/// the engine's written a second time (card tip-coverage-is-a-second-r1).
Future<Uint8List> resampleOnTheEngine({
  required Uint8List src,
  required int srcWidth,
  required int srcHeight,
  required int dstWidth,
  required int dstHeight,
  required ResampleTransform transform,
  required ResampleMode mode,
  double radiusFloor = kSelectionResampleRadiusFloor,
}) async {
  // Opened off this isolate before its kernels are asked for: asked where
  // no engine is open, they open one here.
  await openAppGpuEngine();
  final landing = await appGpuStampLandingKernels.ready;
  // 🚨ON THE ENGINE THE KERNELS ARE OF, not the one that was open before
  // they were waited for: the app may have let that one go meanwhile, its
  // device gone (`letTheGoneAppGpuEngineGo`), and these are the next
  // one's. A picture of one engine carried by another's kernels is no
  // error wgpu raises — it looks the one's buffer up among the other's and
  // panics, which ends the process (🔬2026-11-13: `Cannot get
  // BufferId(2,2), found other resource BufferId(2,1)`, a tip's thumbnail
  // on its way as the app opened another engine; ↩️the picture was made on
  // the engine first waited for).
  return _readOnAWorker(
    landing.carried(
      GpuStampPicture(landing.engine, src, srcWidth, srcHeight),
      inverse: resampleTransformElements(transform),
      radiusFloor: radiusFloor,
      sampling: resampleSampling(mode),
      width: dstWidth,
      height: dstHeight,
    ),
  );
}

/// [picture]'s pixels, read on a worker ([onAWorker]) — whose wait for the
/// GPU is that worker's.
///
/// ⚠️[picture] is held here till the read is done: a local of a
/// `Finalizable` type lives to the end of its scope, and the worker holds
/// only its address ([GpuStampPicture.reader]).
Future<Uint8List> _readOnAWorker(GpuStampPicture picture) async {
  final reader = picture.reader;
  final pixels = await onAWorker(reader.pixels);
  return pixels;
}

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

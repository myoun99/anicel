import 'dart:ui' as ui;

import 'shaded_passes.dart';

/// A camera lens blur as its lanes give it: its [radius] in raster pixels,
/// its [iris], and how it reads the [light] it spreads ([LensLight]).
typedef CameraLensBlur = ({
  double radius,
  IrisProperties iris,
  LensLight light,
});

/// [lens] as the pass that makes it: the iris gathered out of its row sums
/// ([IrisGatherPass]) — every pixel the mean of the pixels about it whose
/// centres it covers (the engine's iris_table.wgsl). [paper], on whole
/// pixels, is where it repeats its edge pixels past the paper and is cut to
/// it; null where it reads nothing past its raster.
///
/// Its fringe, 0 to 500, pushes the light out of the iris's core to its
/// edge: Adobe's help (read 2026-10-28) says 100 is a natural halo and 500
/// all the blur's energy on the ring. Ours, the form (🗣️I-132-Q4 b): the
/// core's pixels weigh `1 - fringe / 500`, the edge's 1 (the engine's
/// gather.wgsl).
///
/// Its light is none to work where it is read as stored and nothing is
/// boosted. [map] is how it reads its blur map where it reads one
/// ([IrisGatherPass.map]).
///
/// ↩️Its row sums were passes of their own before it (`RowSumPass`, 64 taps
/// a pass — twice a line's, as a raster cost ~20ms on the Surface Pro 11,
/// 10-28, card effect-step-passes-each-pay-a-snapshot), the Flutter
/// shaders' (`row_sum.frag`, `iris_gather.frag`), till the Flutter chain
/// went (the-flutter-fx-chain-is-a-second-chain): the engine sums a row
/// itself (kernels/effects/blur/lens.rs).
List<ShadedPass> cameraLensBlurPasses(
  CameraLensBlur lens, {
  required ui.Rect? paper,
  IrisMap? map,
}) {
  final (:radius, :iris, :light) = lens;
  final read = light.linear || (light.gain > 0 && light.threshold < 1)
      ? light
      : null;
  return [
    IrisGatherPass(
      radius: radius,
      iris: iris,
      paper: paper,
      light: read,
      map: map,
    ),
  ];
}

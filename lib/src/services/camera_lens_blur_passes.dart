import 'dart:math' as math;
import 'dart:ui' as ui;

import 'directional_blur_passes.dart';
import 'shaded_passes.dart';

/// The most taps one row sum's pass takes — `shaders/row_sum.frag`'s loop
/// bound. Twice a line's: a pass is a raster, and on the Surface Pro 11 a
/// raster of 1920×1080 costs ~20ms whatever is drawn in it (10-28, card
/// effect-step-passes-each-pay-a-snapshot), so a raster up to 4096 wide is
/// two passes where 32 a pass would make it three.
const int rowSumTapsAPass = 64;

/// The most rows an iris spans — `shaders/iris_gather.frag`'s loop bound:
/// a radius of 8192 raster pixels, the longest side a raster has
/// (`maxSubtreeRasterSide`), each way and its own row.
const int irisRowsAtMost = 2 * 8192 + 1;

/// The passes that make every texel of a raster [width] wide the sum of
/// its row up to it ([RowSumPass]) — a one-sided box as long as the row,
/// laid as a line's is ([lineBoxPlan]) — the first reading its picture's
/// [light] as it sums it.
List<RowSumPass> rowSumPasses(int width, {LensLight? light}) {
  final (:passes, :taps) = lineBoxPlan(
    width.toDouble(),
    tapsAPass: rowSumTapsAPass,
  );
  return [
    for (var pass = 0; pass < passes; pass += 1)
      RowSumPass(
        stride: math.pow(taps, pass).toInt(),
        taps: taps,
        light: pass == 0 ? light : null,
      ),
  ];
}

/// A camera lens blur as its lanes give it: its [radius] in raster pixels,
/// its [iris], and how it reads the [light] it spreads ([LensLight]).
typedef CameraLensBlur = ({
  double radius,
  IrisProperties iris,
  LensLight light,
});

/// [lens] over a raster [rasterWidth] wide, as the passes that make it:
/// the row sums, then the iris gathered out of them ([IrisGatherPass]) —
/// every pixel the mean of the pixels about it whose centres it covers
/// (`shaders/iris_table.frag`). [paper], on whole pixels, is where it
/// repeats its edge pixels past the paper and is cut to it; null where it
/// reads nothing past its raster.
///
/// Its fringe, 0 to 500, pushes the light out of the iris's core to its
/// edge: Adobe's help (read 2026-10-28) says 100 is a natural halo and 500
/// all the blur's energy on the ring. Ours, the form (🗣️I-132-Q4 b): the
/// core's pixels weigh `1 - fringe / 500`, the edge's 1
/// (`shaders/iris_gather.frag`).
///
/// Its light is none to work where it is read as stored and nothing is
/// boosted.
List<ShadedPass> cameraLensBlurPasses(
  CameraLensBlur lens, {
  required int rasterWidth,
  required ui.Rect? paper,
}) {
  final (:radius, :iris, :light) = lens;
  final read = light.linear || (light.gain > 0 && light.threshold < 1)
      ? light
      : null;
  return [
    ...rowSumPasses(rasterWidth, light: read),
    IrisGatherPass(radius: radius, iris: iris, paper: paper, light: read),
  ];
}

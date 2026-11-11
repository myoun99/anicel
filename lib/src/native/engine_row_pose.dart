import 'dart:ui' as ui;

import 'package:gpu_engine/gpu_engine.dart';

import '../core/display_filter.dart';
import '../services/guide_geometry.dart' show GuideTransform;

/// The engine's sampling for [quality], the display's law's answer
/// ([filterQualityForDisplayScale]): `none` is its Nearest, the rest its
/// Blend (브러시/렌더링, I-120 11-08 00:00).
GpuSampling gpuSamplingOf(ui.FilterQuality quality) =>
    quality == ui.FilterQuality.none ? GpuSampling.nearest : GpuSampling.blend;

/// How a row is laid at the canvas's own resolution, one of its pixels a
/// canvas pixel, whatever its pose (🗣️I-120-Q26 · Q28 — a picture baked
/// as the canvas shows it): the canvas's rows and a picture baked onto a
/// cel ask it alike.
GpuSampling get canvasResolutionSampling =>
    gpuSamplingOf(filterQualityForDisplayScale(1));

/// [inverse] — a canvas pixel to a row's own — as the nine a row is posed
/// by ([GpuPlan.row]), row-major with the homogeneous row last.
List<double> gpuRowInverse(GuideTransform inverse) {
  final GuideTransform(:a, :b, :c, :d, :tx, :ty) = inverse;
  return [a, c, tx, b, d, ty, 0, 0, 1];
}

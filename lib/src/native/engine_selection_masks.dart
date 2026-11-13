import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:gpu_engine/gpu_engine.dart';

import 'app_gpu_engine.dart';

/// A selection's mask made on the engine (gpu-int-spec-canvas 1b S1 · S2):
/// the selection's kernels, one set for the app, and the mask of a
/// selection asked of them.
abstract final class EngineSelectionMasks {
  static GpuSelectionMasks get kernels => _kernels.kept;
  static final _kernels = AppKernels<GpuSelectionMasks>(
    GpuSelectionMasks.new,
    GpuSelectionMasks.opening,
    (kernels) => kernels.free(),
  );

  /// Ahead of the first stroke under a selection.
  static Future<void> warm() => _kernels.warm();

  /// Test seam: how many masks have been asked for.
  @visibleForTesting
  static int debugMade = 0;

  /// The selection [spelled] (`CanvasSelectionRegion.spelled`) over [box],
  /// finished by [grow], [feather] and [antiAlias] — `buildSelectionMask`
  /// over it —, on the engine. The caller frees it.
  static GpuMask of(
    ({Uint32List program, Float64List points}) spelled, {
    required ({int left, int top, int width, int height}) box,
    required int grow,
    required double feather,
    required bool antiAlias,
  }) {
    debugMade += 1;
    return kernels.selection(
      program: spelled.program,
      points: spelled.points,
      x: box.left,
      y: box.top,
      width: box.width,
      height: box.height,
      grow: grow,
      feather: feather,
      antiAlias: antiAlias,
    );
  }

  /// Test seam: the kernels gone, as at launch.
  @visibleForTesting
  static void debugForget() => _kernels.debugForget();
}

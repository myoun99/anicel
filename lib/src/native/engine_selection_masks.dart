import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:gpu_engine/gpu_engine.dart';

import 'app_gpu_engine.dart';

/// A selection's mask made on the engine (gpu-int-spec-canvas 1b S1 · S2):
/// the selection's kernels, one set for the app, and the mask of a
/// selection asked of them — kept for the clip that asked, as long as it
/// lives ([keptFor]).
abstract final class EngineSelectionMasks {
  static GpuSelectionMasks get kernels => _kernels.kept;
  static final _kernels = AppKernels<GpuSelectionMasks>(
    GpuSelectionMasks.new,
    GpuSelectionMasks.opening,
    (kernels) => kernels.free(),
  );

  /// Ahead of the first stroke under a selection.
  static Future<void> warm() => _kernels.warm();

  /// Test seam: how many masks have been made.
  @visibleForTesting
  static int debugMade = 0;

  static final _masks = KeptOnTheAppsEngine<Expando<GpuMask>>();

  static Expando<GpuMask> get _of => _masks.of(Expando.new);

  /// [clip]'s mask on the engine the app has: [make]'s the first time it is
  /// asked there, and let go of with [clip] — what reads a selection on the
  /// engine (a stroke's landings, a stamp's) asks its clip at each landing,
  /// and the clip holds what was made, as a stamp holds its picture
  /// (`EngineStampPictures`).
  ///
  /// ↩️Till 2026-11-14 the live stroke kept the one it made and freed it as
  /// it ended, and a stamp's landing made its own: two holders of one mask,
  /// and a fill's pieces would each have made it again.
  static GpuMask keptFor(Object clip, GpuMask Function() make) =>
      _of[clip] ??= make();

  /// The selection [spelled] (`CanvasSelectionRegion.spelled`) over [box],
  /// finished by [grow], [feather] and [antiAlias] — `buildSelectionMask`
  /// over it —, on the engine. Let go of with the object ([keptFor] keeps
  /// it for a clip).
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

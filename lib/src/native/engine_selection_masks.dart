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

  /// The bytes the kernels keep between their folds — the bit planes a
  /// selection is folded in, kept for the next — for the memory census.
  static int get keptPlaneBytes => _kernels.compiled?.bytes ?? 0;

  /// The OS says memory is tight: what the kernels keep goes.
  static void letGoIdle() => _kernels.compiled?.letGo();

  /// Test seam: how many masks have been made.
  @visibleForTesting
  static int debugMade = 0;

  static final _masks = KeptOnTheAppsEngine<Expando<Object>>();

  static Expando<Object> get _of => _masks.of(Expando.new);

  /// [clip]'s mask on the engine the app has — a selection's, a fill
  /// piece's coverage, or an area's pieces' coverages together
  /// (`canvas_flood_fill.dart`): [make]'s the first time it is asked there,
  /// and let go of with [clip] — what reads a selection on the engine (a
  /// stroke's landings, a stamp's) asks its clip at each landing,
  /// and the clip holds what was made, as a stamp holds its picture
  /// (`EngineStampPictures`).
  ///
  /// ↩️Till 2026-11-14 the live stroke kept the one it made and freed it as
  /// it ended, and a stamp's landing made its own: two holders of one mask,
  /// and a fill's pieces would each have made it again.
  static T keptFor<T extends Object>(Object clip, T Function() make) =>
      (_of[clip] ??= make()) as T;

  /// Test seam: how many areas have been asked for ([area]).
  @visibleForTesting
  static int debugAreasAsked = 0;

  /// The AREA [spelled] (`CanvasSelectionRegion.spelled`) over [box],
  /// finished as a fill finishes what it flooded — grown [expand]
  /// generations, softened past its outline where [antiAlias] — over
  /// [parts] of the box alone, and cut into a mask for each, in their order
  /// (`GpuSelectionMasks.area`): what an area's pieces are laid of, none of
  /// them read back, and its range, read whole (`canvas_flood_fill.dart`).
  /// Nothing waits.
  static List<GpuMask> area(
    ({Uint32List program, Float64List points}) spelled, {
    required ({int left, int top, int width, int height}) box,
    required int expand,
    required bool antiAlias,
    required List<({int left, int top, int width, int height})> parts,
  }) {
    debugAreasAsked += 1;
    return kernels.area(
      program: spelled.program,
      points: spelled.points,
      x: box.left,
      y: box.top,
      width: box.width,
      height: box.height,
      expand: expand,
      antiAlias: antiAlias,
      parts: parts,
    );
  }

  /// The selection [spelled] (`CanvasSelectionRegion.spelled`) over [box],
  /// finished by [grow], [feather] and [antiAlias], on the engine — the one
  /// maker of a selection's mask. Let go of with the object ([keptFor]
  /// keeps it for a clip).
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

  /// The selection [spelled] (`CanvasSelectionRegion.spelled`) over [box]
  /// as its hard mask's runs, a row each — its selected pixels' starts and
  /// ends in turn, columns from the box's left (`GpuSelectionMasks.runs`):
  /// what reads a selection on the CPU (`CanvasSelectionRegion
  /// .pixelRunsFor`). Waits for the GPU.
  static List<Uint32List> runs(
    ({Uint32List program, Float64List points}) spelled, {
    required ({int left, int top, int width, int height}) box,
  }) => kernels.runs(
    program: spelled.program,
    points: spelled.points,
    x: box.left,
    y: box.top,
    width: box.width,
    height: box.height,
  );

  /// The pixels of [bytes] — a byte each over [box], row after row — that
  /// the selection [by] takes any of, whole, and none elsewhere: cut on the
  /// engine (`GpuSelectionMasks.cut`) and read back for the CPU, what a
  /// held fill's mark outlines (`FillRange.coveredWithin`). Waits for the
  /// GPU.
  static Uint8List cut(
    Uint8List bytes, {
    required ({int left, int top, int width, int height}) box,
    required GpuMask by,
  }) {
    final mask = GpuMask(
      appGpuComposite,
      bytes,
      x: box.left,
      y: box.top,
      width: box.width,
      height: box.height,
    );
    try {
      final cut = kernels.cut(mask, by);
      try {
        return cut.read();
      } finally {
        cut.free();
      }
    } finally {
      mask.free();
    }
  }

  /// Test seam: the kernels gone, as at launch.
  @visibleForTesting
  static void debugForget() => _kernels.debugForget();
}

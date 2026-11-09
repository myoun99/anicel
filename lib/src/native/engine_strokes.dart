import 'package:gpu_engine/gpu_engine.dart';

import 'app_gpu_engine.dart';

/// The strokes the app has made and is not drawing with: a stroke's pages
/// are kept for the next one, a device taking tens of ms to make a page
/// (rust/src/kernels/dab/stroke.rs).
abstract final class EngineStrokes {
  static final List<GpuStroke> _idle = [];

  /// One stroke's kernels compiled ahead of the first pen-down, which would
  /// otherwise wait for them.
  static void warm() {
    if (_idle.isEmpty) {
      _idle.add(GpuStroke(appGpuEngine));
    }
  }

  /// A stroke of no tiles.
  static GpuStroke take() =>
      _idle.isEmpty ? GpuStroke(appGpuEngine) : _idle.removeLast();

  /// [stroke] done with: cleared and kept for the next.
  static void giveBack(GpuStroke stroke) {
    stroke.clear();
    _idle.add(stroke);
  }

  /// The bytes the strokes kept hold, for the memory census.
  static int get idleBytes =>
      _idle.fold(0, (bytes, stroke) => bytes + stroke.bytes);

  /// The OS says memory is tight: the strokes kept go.
  static void letGoIdle() {
    for (final stroke in _idle) {
      stroke.free();
    }
    _idle.clear();
  }
}

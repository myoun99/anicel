import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:gpu_engine/gpu_engine.dart';

import 'app_gpu_engine.dart';

/// The strokes the app has made and is not drawing with: a stroke's pages
/// are kept for the next one, a device taking tens of ms to make a page
/// (rust/src/kernels/dab/stroke.rs).
abstract final class EngineStrokes {
  static final List<GpuStroke> _idle = [];

  /// The blur brush's kernels, one set for every stroke.
  static GpuBlurs get blurs => _blurs.kept;
  static final _blurs = AppKernels<GpuBlurs>(
    GpuBlurs.new,
    GpuBlurs.opening,
    (blurs) => blurs.free(),
  );

  /// One stroke's kernels compiled off this isolate, ahead of the first
  /// pen-down, which would otherwise wait for them.
  static Future<void> warm() async {
    if (_idle.isEmpty) {
      _idle.add(await GpuStroke.opening(appGpuEngine));
    }
  }

  /// The blur brush's, ahead of its first stroke: 🔬10.2 s on the main PC
  /// with eighteen test files running (11-10), the app frozen at the first
  /// blur of every launch.
  ///
  /// ⛔Not with [warm]: its ten kernels are a third of all the app compiles
  /// ahead (🔬main PC, 2026-11-11), and a pen put down or a selection
  /// lifted would wait behind every one of them (`compileAppKernelsAhead`).
  static Future<void> warmBlurs() => _blurs.warm();

  /// A stroke of no tiles.
  static GpuStroke take() =>
      _idle.isEmpty ? GpuStroke(appGpuEngine) : _idle.removeLast();

  /// Test seam: how many strokes wait for the next pen-down.
  @visibleForTesting
  static int get debugIdle => _idle.length;

  /// Test seam: the blur kernels gone, as at launch.
  @visibleForTesting
  static void debugForgetBlurs() => _blurs.debugForget();

  /// [stroke] done with: cleared and kept for the next.
  static void giveBack(GpuStroke stroke) {
    stroke.clear();
    _idle.add(stroke);
  }

  /// The bytes the strokes kept hold, for the memory census.
  static int get idleBytes =>
      _idle.fold(
        _blurs.compiled?.bytes ?? 0,
        (bytes, stroke) => bytes + stroke.bytes,
      );

  /// The OS says memory is tight: the strokes kept go.
  static void letGoIdle() {
    _blurs.compiled?.letGo();
    for (final stroke in _idle) {
      stroke.free();
    }
    _idle.clear();
  }
}

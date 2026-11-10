import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:gpu_engine/gpu_engine.dart';

import 'app_gpu_engine.dart';

/// The strokes the app has made and is not drawing with: a stroke's pages
/// are kept for the next one, a device taking tens of ms to make a page
/// (rust/src/kernels/dab/stroke.rs).
abstract final class EngineStrokes {
  static final List<GpuStroke> _idle = [];

  /// The blur brush's kernels, one set for every stroke — compiled here the
  /// first time anything asks, if [warm] has not got there first.
  static GpuBlurs get blurs => _blurs ??= GpuBlurs(appGpuEngine);
  static GpuBlurs? _blurs;

  /// One stroke's kernels compiled ahead of the first pen-down, which would
  /// otherwise wait for them, and the blur brush's off this isolate: 🔬10.2 s
  /// on the main PC with eighteen test files running (11-10), the app frozen
  /// at the first blur of every launch.
  static Future<void> warm() async {
    if (_idle.isEmpty) {
      _idle.add(GpuStroke(appGpuEngine));
    }
    if (_blurs != null) {
      return;
    }
    final made = await GpuBlurs.opening(appGpuEngine);
    // Asked for the other way while these compiled: the app keeps one.
    if (_blurs == null) {
      _blurs = made;
    } else {
      made.free();
    }
  }

  /// A stroke of no tiles.
  static GpuStroke take() =>
      _idle.isEmpty ? GpuStroke(appGpuEngine) : _idle.removeLast();

  /// Test seam: the blur kernels gone, as at launch.
  @visibleForTesting
  static void debugForgetBlurs() {
    _blurs?.free();
    _blurs = null;
  }

  /// [stroke] done with: cleared and kept for the next.
  static void giveBack(GpuStroke stroke) {
    stroke.clear();
    _idle.add(stroke);
  }

  /// The bytes the strokes kept hold, for the memory census.
  static int get idleBytes =>
      _idle.fold(_blurs?.bytes ?? 0, (bytes, stroke) => bytes + stroke.bytes);

  /// The OS says memory is tight: the strokes kept go.
  static void letGoIdle() {
    _blurs?.letGo();
    for (final stroke in _idle) {
      stroke.free();
    }
    _idle.clear();
  }
}

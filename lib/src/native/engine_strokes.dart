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

  /// The blur brush's, ahead of its first stroke — what a stroke cannot
  /// go without ([warmBlurStrips] has the rest): 🔬the ten were 10.2 s on
  /// the main PC with eighteen test files running (11-10), the app frozen
  /// at the first blur of every launch.
  static Future<void> warmBlurs() => _blurs.warm();

  /// The kernels a blur stroke goes by strips with, the engine's to keep:
  /// a stroke goes a pass a dispatch — the same pixels, slower — till they
  /// are compiled (`GpuBlurs.compilingStrips`).
  ///
  /// ⛔Not with [warm] or [warmBlurs]: 🔬the six are nine tenths of the
  /// blur brush's ten, which are a third of all the app compiles ahead
  /// (main PC, 2026-11-11) and 7.2 s of the Surface Pro 11's compiler — a
  /// pen put down or a selection lifted would wait behind every one of
  /// them (`compileAppKernelsAhead`). ↩️The ten were one set till
  /// 2026-11-11: a blur stroke before the list was through compiled them
  /// all on the thread the app's frames are built on, 7.0–10.1 s of a
  /// stopped app within 13 s of the canvas (🗣️관제 06:42: 「같은 선이
  /// 걸린다」).
  static Future<void> warmBlurStrips() =>
      _blurStrips ??= GpuBlurs.compilingStrips(appGpuEngine);
  static Future<void>? _blurStrips;

  /// A stroke of no tiles.
  static GpuStroke take() =>
      _idle.isEmpty ? GpuStroke(appGpuEngine) : _idle.removeLast();

  /// Test seam: how many strokes wait for the next pen-down.
  @visibleForTesting
  static int get debugIdle => _idle.length;

  /// Test seam: whether [blurs] is compiled.
  @visibleForTesting
  static bool get debugBlursCompiled => _blurs.compiled != null;

  /// Test seam: the blur kernels gone, as at launch.
  @visibleForTesting
  static void debugForgetBlurs() {
    _blurs.debugForget();
    _blurStrips = null;
  }

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

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:gpu_engine/gpu_engine.dart';

import 'app_gpu_engine.dart';

/// The kernels over a cel's pixels — the colour verbs' pass and a
/// selection's lift —, one set for the app.
abstract final class EngineCelPixels {
  static GpuCelPixels get pass => _pass.kept;
  static final _pass = AppKernels<GpuCelPixels>(
    GpuCelPixels.new,
    GpuCelPixels.opening,
    (pass) => pass.free(),
  );

  /// Ahead of the first press of a verb or grab of a selection: 🔬277 ms for
  /// the verbs' on the main PC's RTX 4080 (11-10), an old tablet's GPU many
  /// times that.
  static Future<void> warm() => _pass.warm();

  /// Test seam: the pass gone, as at launch.
  @visibleForTesting
  static void debugForget() => _pass.debugForget();
}

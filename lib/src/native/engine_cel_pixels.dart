import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:gpu_engine/gpu_engine.dart';

import 'app_gpu_engine.dart';

/// The kernels over a cel's pixels — the colour verbs' pass and a
/// selection's lift —, one set for the app.
abstract final class EngineCelPixels {
  /// Compiled here the first time anything asks, if [warm] has not got
  /// there first.
  static GpuCelPixels get pass => _pass ??= GpuCelPixels(appGpuEngine);
  static GpuCelPixels? _pass;

  /// The kernels compiled off this isolate, ahead of the first press of a
  /// verb or grab of a selection, which would otherwise wait for them with
  /// the app frozen: 🔬277 ms for the verbs' on the main PC's RTX 4080
  /// (11-10), an old tablet's GPU many times that.
  static Future<void> warm() async {
    if (_pass != null) {
      return;
    }
    final made = await GpuCelPixels.opening(appGpuEngine);
    // Asked for the other way while this compiled: the app keeps one.
    if (_pass == null) {
      _pass = made;
    } else {
      made.free();
    }
  }

  /// Test seam: the pass gone, as at launch.
  @visibleForTesting
  static void debugForget() {
    _pass?.free();
    _pass = null;
  }
}

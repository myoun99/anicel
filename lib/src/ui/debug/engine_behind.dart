import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../native/app_gpu_engine.dart' show appGpuEngineOpen;

/// The submits of the app's engine the GPU has not said it finished, as of
/// the device's last poll (`GpuEngine.submitsBehind`) — read by the frame
/// statistics at each frame built (`FrameStats`) and by a stroke's first
/// step as it goes out (`StrokeSteps`). Null where no engine is open.
abstract final class EngineBehind {
  /// Test seam: the submits behind a test says the engine has, in place of
  /// the app's engine's own word — an engine at rest has none.
  @visibleForTesting
  static int? Function()? debugNow;

  /// The submits behind now.
  static int? get now => (debugNow ?? _enginesOwn)();

  static int? _enginesOwn() => appGpuEngineOpen.value?.submitsBehind;
}

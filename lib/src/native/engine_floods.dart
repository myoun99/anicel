import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:gpu_engine/gpu_engine.dart';

import 'app_gpu_engine.dart';

/// The fill's kernels — the flood's passes and the mask's it is finished
/// by —, one set for the app.
abstract final class EngineFloods {
  static GpuFloods get kernels => _kernels.kept;
  static final _kernels = AppKernels<GpuFloods>(
    GpuFloods.new,
    GpuFloods.opening,
    (kernels) => kernels.free(),
  );

  /// Ahead of the first press of the bucket.
  static Future<void> warm() => _kernels.warm();

  /// Test seam: the kernels gone, as at launch.
  @visibleForTesting
  static void debugForget() => _kernels.debugForget();
}

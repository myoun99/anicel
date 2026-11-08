import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';

/// A surface of [width] × [height] as the platform makes the ones it
/// shows: RGBA where it can, else BGRA — Apple's make BGRA alone
/// (platform/apple.rs), Linux's RGBA alone.
GpuSurface shownSurfaceOf(int width, int height) {
  try {
    return appGpuEngine.surface(width, height, bgra: false);
  } on StateError {
    return appGpuEngine.surface(width, height, bgra: true);
  }
}

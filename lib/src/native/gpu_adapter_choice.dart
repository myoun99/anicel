/// Which adapter the app's GPU engine opens on (app_gpu_engine.dart).
enum GpuAdapterChoice {
  /// The one Flutter draws with, so what the engine draws lives on the GPU
  /// that shows it.
  flutters,

  /// The platform's first: `flutter test`'s, where no Flutter names one.
  first,
}

/// The adapter the app's engine opens on.
///
/// ⚠️test/flutter_test_config.dart sets [GpuAdapterChoice.first], and this
/// is a file of its own that imports no engine code so the config reaches
/// none: every suite reads what the config imports (tool/affected_tests,
/// kEveryTestReads), so an engine reached from there would run every suite
/// again for a change in the engine's Rust (11-05: 218 files, forty
/// minutes, for a lane that changed the engine alone).
GpuAdapterChoice debugGpuAdapterChoice = GpuAdapterChoice.flutters;

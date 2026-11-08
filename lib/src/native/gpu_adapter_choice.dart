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
/// ⚠️test/flutter_test_config.dart sets [GpuAdapterChoice.first]. This is a
/// file of its own that imports no engine code so the config would reach
/// none: every suite reads what the config imports (tool/affected_tests,
/// kEveryTestReads), so an engine reached from there runs every suite again
/// for a change in the engine's Rust (11-05: 218 files, forty minutes, for
/// a lane that changed the engine alone).
/// ↩️🗣️유저 2026-11-08, connection-round-checklist-Q24 「엔진 Rust 를 옛 C
/// 엔진 소스처럼 읽는다」: the config reaches the engine all the same — the
/// app draws its narrowed words through it from deep in its widgets
/// (word_bake.dart) — and that is the law now: the wide run asks every
/// suite of a change to the engine's Rust, as of the C, and a lane's near
/// run the suites that call it.
GpuAdapterChoice debugGpuAdapterChoice = GpuAdapterChoice.flutters;

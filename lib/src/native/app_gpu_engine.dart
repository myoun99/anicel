import 'package:gpu_engine/gpu_engine.dart';

import 'gpu_adapter_choice.dart';

/// The app's one GPU engine, opened the first time anything asks — so a
/// test file that never asks opens no device (보드/인프라 2026-11-07: 0.6–1.2
/// s a device, eighteen test files at once on the machine's line) — on the
/// adapter [debugGpuAdapterChoice] names. ⛔No fallback: a test that needs
/// the engine and gets none fails.
// ⏳The tile store asks first (screen-on-the-engine, the write path's
// commit); till then only its test does.
GpuEngine get appGpuEngine => _engine ??= switch (debugGpuAdapterChoice) {
  GpuAdapterChoice.flutters => GpuEngine.onFlutterAdapter(),
  GpuAdapterChoice.first => GpuEngine.onFirstAdapter(),
};
GpuEngine? _engine;

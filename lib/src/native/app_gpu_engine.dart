import 'package:gpu_engine/gpu_engine.dart';

/// How the app opens its one GPU engine: on the adapter Flutter draws with,
/// so what the engine draws lives on the GPU that shows it.
///
/// ⚠️`flutter test` has no Flutter adapter to name, and
/// test/flutter_test_config.dart opens the first one instead — with no
/// fallback: a test that needs the engine and gets none fails.
GpuEngine Function() debugGpuEngineOpener = GpuEngine.onFlutterAdapter;

/// The app's one GPU engine, opened the first time anything asks — so a
/// test file that never asks opens no device (보드/인프라 2026-11-07: 0.6–1.2
/// s a device, eighteen test files at once on the machine's line).
// ⏳The tile store asks first (screen-on-the-engine, the write path's
// commit); till then only its test does.
GpuEngine get appGpuEngine => _engine ??= debugGpuEngineOpener();
GpuEngine? _engine;

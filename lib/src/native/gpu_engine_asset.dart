/// The code asset the GPU engine's Rust library ships as
/// (packages/gpu_engine/hook/build.dart names it; the package's own
/// `@Native` bindings resolve to it by being that file) — for an app module
/// the library carries (rust/src/lib.rs), whose file says
/// `@DefaultAsset(gpuEngineAsset) library;` and binds its names with
/// `@Native`: the app opens no library and names no path for it
/// (connection-round-checklist A, 캔버스 베이스 2026-11-08 — the fx plugin
/// host first).
///
/// ⚠️A FILE OF ITS OWN IN THE APP THAT IMPORTS NO ENGINE CODE
/// (connection-round-checklist H, 2026-11-08). It stood in
/// `package:gpu_engine/gpu_engine.dart`, and a module that imported it for
/// this one word read as code that draws through the engine. The display
/// and the pen are reached from test/flutter_test_config.dart
/// (present_pacing.dart, pen_sidecars.dart), so a change to the engine's
/// Rust ran every suite in the wide run — which it does since
/// connection-round-checklist-Q24 all the same (gpu_adapter_choice.dart) —,
/// and the Windows CI shards, which leave the
/// tests that reach package:gpu_engine to Linux
/// (tool/tests_reaching_package.dart), left 685 more files there: the
/// pen's and the display's Windows pins among them, which skip on Linux.
/// A module's pins are chosen by its crate instead, written as a path
/// (`_host`, `_display`, `_pen`).
library;

const gpuEngineAsset = 'package:gpu_engine/src/engine_ffi.dart';

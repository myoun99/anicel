/// Anicel's native core, packaged so every platform's toolchain
/// compiles the same C sources.
///
/// There is deliberately no API here. ↩️The engine was consumed through
/// `dart:ffi` by `lib/src/native/qa_native_engine.dart` in the app till its
/// last kernel left for the GPU engine's library (C ABI 83, 2026-11-13);
/// nothing in the app opens it now, and the package goes next (board
/// connection-round-checklist). Its loader (`openQaEngineLibrary`)
/// resolves symbols differently per platform:
///
/// - **iOS / macOS**: the sources are compiled INTO the app binary by
///   CocoaPods, so symbols live in the process — `DynamicLibrary.process()`.
///   iOS does not permit loading a standalone `.dylib` from the bundle,
///   which is the reason this package exists at all.
/// - **Android / Linux**: a shared library ships beside the app —
///   `DynamicLibrary.open('libqa_engine.so')`.
/// - **Windows**: `qa_engine.dll` beside the executable.
///
/// Absence is always graceful: the app falls back to its Dart reference
/// implementations, which stay in the tree forever and are byte-parity
/// pinned by tests.
library;

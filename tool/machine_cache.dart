// This machine's folder for what the tools — and its test runs — keep
// between runs.
//
// WHERE: beside `tool/run.sh`'s exes — `%LOCALAPPDATA%\anicel` on Windows,
// `~/.cache/anicel` elsewhere. ⛔The same place spelled twice (here and in
// run.sh): change both or neither.
//
// ⚠️A file of its own that imports nothing, as
// lib/src/native/gpu_adapter_choice.dart is: test/flutter_test_config.dart
// reads it for the folder the runs keep their shaders in, and every suite
// reads what the config imports (affected_tests.dart, kEveryTestReads) — so
// a change to a tool beside it runs no suite again.

/// This machine's folder for what the tools keep between runs, or null if
/// the environment names none.
String? machineCacheFolder(Map<String, String> environment) {
  final local = environment['LOCALAPPDATA'];
  if (local != null && local.isNotEmpty) {
    return '${local.replaceAll('\\', '/')}/anicel';
  }
  final xdg = environment['XDG_CACHE_HOME'];
  if (xdg != null && xdg.isNotEmpty) return '$xdg/anicel';
  final home = environment['HOME'];
  return home == null || home.isEmpty ? null : '$home/.cache/anicel';
}

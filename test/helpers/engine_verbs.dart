import 'dart_sources.dart';

/// The verbs the engine's Rust sources export — each `extern "C"` function
/// named `gpu_engine_…` — by name, each one's body: for the scans of a law
/// the engine's two sides keep together (`test/architecture`), where a
/// landing runs the crate's own scans only if the crate changed
/// (tool/lane.sh).
Map<String, String> engineVerbBodies() => engineVerbBodiesIn(
  [
    for (final file in filesUnder('packages/gpu_engine/rust/src'))
      if (file.path.endsWith('.rs')) file.readAsStringSync(),
  ].join('\n'),
);

/// [engineVerbBodies] of [rust] — its comments cut off: a door named in a
/// comment is none gone through.
Map<String, String> engineVerbBodiesIn(String rust) {
  final code = rust
      .replaceAll('\r\n', '\n')
      .replaceAll(RegExp(r'//[^\n]*'), '');
  return {
    for (final verb in RegExp(
      r'extern "C" fn (gpu_engine_\w+)\([^{]*? \{\n([\s\S]*?)\n\}',
    ).allMatches(code))
      verb.group(1)!: verb.group(2)!,
  };
}

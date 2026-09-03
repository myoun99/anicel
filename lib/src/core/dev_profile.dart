/// Brush-lab profiling probes (R13): compile-time gated so production
/// builds pay literally nothing (`const` folding removes the wrapper).
///
///   flutter run --dart-define=BRUSH_LAB_PROFILE=true -t lib/dev/brush_lab_main.dart
///
/// Sites wrapped in [labProbe] print their wall time when a single call
/// crosses the reporting threshold — the attribution layer between the
/// lab's frame-level jank counts and the actual code paths.
library;

const bool brushLabProfile = bool.fromEnvironment('BRUSH_LAB_PROFILE');

const int _reportThresholdMs = 4;

T labProbe<T>(String site, T Function() body) {
  if (!brushLabProfile) {
    return body();
  }
  final watch = Stopwatch()..start();
  final result = body();
  watch.stop();
  if (watch.elapsedMilliseconds >= _reportThresholdMs) {
    // ignore: avoid_print
    print('[lab-probe] $site ${watch.elapsedMilliseconds}ms');
  }
  return result;
}

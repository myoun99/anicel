import 'dart:async';

/// Work asked for by key while it runs: ONE run a key, the same future to
/// every ask, and the key let go the moment the run ends — answered or
/// failed — so the next ask runs it anew.
///
/// 🚨Written once. It was written out by hand five times — a bake, a movie
/// frame's decode, a face's files, a picture's open, a cel's thaw — and two
/// of them fell into the same trap on their own ([join]).
final class InFlight<K, T> {
  final Map<K, Future<T>> _runs = {};

  /// Whether [key]'s run is going — asked of anything, as a map is.
  bool isRunning(Object? key) => _runs.containsKey(key);

  /// [key]'s run, while it goes.
  Future<T>? runOf(Object? key) => _runs[key];

  /// [key]'s run if it is going, else [work] begun as it.
  Future<T> join(K key, Future<T> Function() work) =>
      _runs[key] ??= work().whenComplete(() {
        // 🚨A BLOCK, NOT AN ARROW. `remove` answers what it removed — this
        // very future — and a `whenComplete` callback that returns a future
        // is waited for: the arrow made the run wait on itself for ever.
        // The playback warmer stopped for good at the first movie frame on
        // it (2026-09-12), and the cel thaw hung on it again (2026-10-15).
        unawaited(_runs.remove(key));
      });
}

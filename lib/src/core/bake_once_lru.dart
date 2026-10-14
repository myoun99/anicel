import 'dart:collection';

import 'in_flight.dart';

/// A bake-once, share-in-flight LRU.
///
/// ⛔THE IN-FLIGHT MAP IS THE POINT, NOT THE CACHE. Two callers asking for
/// the same key while a bake runs must get ONE bake: a store that only
/// remembers FINISHED work rasterizes the same brush sample twice under a
/// fast scroll, and the second result overwrites the first while the
/// first's handle is already out with a caller.
///
/// [retire] is called for each value evicted past [capacity] — a store
/// whose values own native handles disposes them there; one whose values
/// are plain data leaves it null. Eviction never touches an in-flight
/// bake, and never the entry just inserted.
///
/// A bake that FAILS is no answer: the asks while it ran share its failure,
/// and the next ask bakes anew. 🗣️브러시/렌더링 (2026-10-15, card
/// `cel-thaw-holds-the-ui-thread`): every store's value is 「a bake, or
/// nothing (null)」, and a throw is not that answer but an accident — kept,
/// a bake the GPU slipped on once left that word or preview blank until the
/// app restarted. ↩️It was kept, by `.then`, which nobody had decided.
class BakeOnceLru<K, V> {
  BakeOnceLru({required this.capacity, this.retire});

  final int capacity;
  final void Function(V value)? retire;

  final LinkedHashMap<K, V> _done = LinkedHashMap<K, V>();
  final InFlight<K, V> _baking = InFlight();

  /// The finished value for [key], moved to the front, or null.
  V? peek(K key) {
    if (!_done.containsKey(key)) {
      return null;
    }
    final value = _done.remove(key) as V;
    _done[key] = value;
    return value;
  }

  /// Whether [key]'s bake has finished — a null value included: a key
  /// [peek] answers null for may still be on its way, or may be done and
  /// have come to nothing, and nobody waits for the second.
  bool isDone(K key) => _done.containsKey(key);

  /// The value for [key]: the cached one, the bake already in flight, or
  /// a new bake from [bake].
  Future<V> ensure(K key, Future<V> Function() bake) {
    if (_done.containsKey(key)) {
      return Future<V>.value(peek(key));
    }
    return _baking.join(
      key,
      () => bake().then((value) {
        _done[key] = value;
        while (_done.length > capacity) {
          final evicted = _done.remove(_done.keys.first) as V;
          retire?.call(evicted);
        }
        return value;
      }),
    );
  }

  /// Every finished value, oldest first — for a store that has to walk
  /// what it holds (a byte budget, a teardown).
  Iterable<MapEntry<K, V>> get entries => _done.entries;

  int get length => _done.length;

  void clear() => _done.clear();
}

import 'in_flight.dart';
import 'lru.dart';

/// A bake-once, share-in-flight LRU.
///
/// ⛔THE IN-FLIGHT MAP IS THE POINT, NOT THE CACHE. Two callers asking for
/// the same key while a bake runs must get ONE bake: a store that only
/// remembers FINISHED work rasterizes the same brush sample twice under a
/// fast scroll, and the second result overwrites the first while the
/// first's handle is already out with a caller.
///
/// The finished bakes are an [Lru] of [capacity] entries — the one order a
/// bounded cache lets go by; [retire] is its letting go — a store whose
/// values own native handles disposes them there; one whose values are
/// plain data leaves it null. Eviction never touches an in-flight bake,
/// and never the entry just inserted. What a value weighs ([costOf]) is
/// told, never bounded: [held] is what the memory census reads of a store
/// whose values are pictures.
///
/// A bake that FAILS is no answer: the asks while it ran share its failure,
/// and the next ask bakes anew. 🗣️브러시/렌더링 (2026-10-15, card
/// `cel-thaw-holds-the-ui-thread`): every store's value is 「a bake, or
/// nothing (null)」, and a throw is not that answer but an accident — kept,
/// a bake the GPU slipped on once left that word or preview blank until the
/// app restarted. ↩️It was kept, by `.then`, which nobody had decided.
class BakeOnceLru<K, V> {
  BakeOnceLru({required this.capacity, this.retire, this.costOf});

  final int capacity;
  final void Function(V value)? retire;

  /// What a finished value weighs. Null: one each.
  final int Function(V value)? costOf;

  late final Lru<K, V> _done = Lru(
    entryCap: () => capacity,
    costOf: costOf,
    letGo: (_, value) => retire?.call(value),
  );
  final InFlight<K, V> _baking = InFlight();

  /// The finished value for [key], moved to the front, or null.
  V? peek(K key) => _done.use(key);

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
        _done.keep(key, value);
        return value;
      }),
    );
  }

  /// Every finished value, oldest first — for a store that has to walk
  /// what it holds (a teardown).
  Iterable<MapEntry<K, V>> get entries => _done.entries;

  int get length => _done.length;

  /// What the finished values weigh together ([costOf]) — how many, for a
  /// store that weighs none.
  int get held => _done.held;

  void clear() => _done.clear();
}

import 'dart:collection';

/// THE ORDER A BOUNDED CACHE LETS GO BY: what was used longest ago goes
/// first, never what was used last, until what it holds is within its
/// limit.
///
/// 🚨ONE SPELLING (card every-bounded-cache-is-one-lru, 2026-10-16). Stores
/// wrote it out by hand — a map kept in use order, taken out and put back
/// on every use, and a loop letting go of its first key past a bound —
/// some counting entries, some bytes. Same algorithm, so copies by
/// connascence (CLAUDE.md absolute command 1), whatever each one called it.
///
/// What each store still says for itself: what an entry costs ([costOf] —
/// one each when it counts entries), how much it may hold ([limit], asked
/// every time it fits — budgets move with the memory tab's allowance and
/// with a memory warning), and what letting go of an entry does besides
/// forgetting it ([letGo] — a value owning a native handle disposes it).
///
/// ⛔Not a memo: a value that owns nothing and is cheap to build again goes
/// in `BoundedMemo`, which starts over rather than reshuffle on every hit.
/// ⛔Not a cache a playhead reads, where what it wants latest goes first
/// (`letGoWantedLatest`). ⛔Nor one that pays once for a value several keys
/// share, or that must wait before it lets go — the brush frame store's
/// movie pictures and its cooling (🗣️저장, 2026-10-16): [costOf] is read
/// when an entry comes and when it goes, and [letGo] runs at once.
final class Lru<K, V> {
  Lru({required this.limit, int Function(V value)? costOf, this.letGo})
    : _costOf = costOf ?? _one;

  /// How much it may hold — entries, or whatever [costOf] counts. Asked
  /// each time it fits, never kept.
  final int Function() limit;

  /// What letting go of an entry does besides forgetting it. Never called
  /// for one [take]n, replaced by [keep] or [clear]ed: those stay the
  /// caller's.
  final void Function(K key, V value)? letGo;

  final int Function(V value) _costOf;

  final LinkedHashMap<K, V> _entries = LinkedHashMap<K, V>();
  int _held = 0;

  static int _one(Object? _) => 1;

  /// What the entries cost together.
  int get held => _held;

  int get length => _entries.length;

  bool containsKey(K key) => _entries.containsKey(key);

  /// [key]'s value as it stands — NOT a use: it keeps its place.
  V? peek(K key) => _entries[key];

  /// [key]'s value, made the most recently used; null when there is none.
  /// ⚠️A store that keeps nulls asks [containsKey] first.
  V? use(K key) {
    final before = _entries.length;
    final value = _entries.remove(key);
    if (_entries.length == before) {
      return null;
    }
    return _entries[key] = value as V;
  }

  /// Keeps [value] for [key] as the most recently used, then lets go of
  /// what no longer fits. The value it replaced comes back NOT let go — a
  /// result re-blended into its old buffer still needs that buffer.
  V? keep(K key, V value) {
    final replaced = take(key);
    _entries[key] = value;
    _held += _costOf(value);
    fit();
    return replaced;
  }

  /// Forgets [key]'s value without letting go of it — the caller has taken
  /// it over.
  V? take(K key) {
    final before = _entries.length;
    final value = _entries.remove(key);
    if (_entries.length == before) {
      return null;
    }
    _held -= _costOf(value as V);
    return value;
  }

  /// Lets go of the least recently used until what is held is within
  /// [limit] — never the most recently used: it is what was just asked
  /// for, and what is about to be drawn.
  void fit() {
    while (_held > limit() && _entries.length > 1) {
      final key = _entries.keys.first;
      final value = _entries.remove(key) as V;
      _held -= _costOf(value);
      letGo?.call(key, value);
    }
  }

  /// Least recently used first.
  Iterable<K> get keys => _entries.keys;

  /// Least recently used first.
  Iterable<V> get values => _entries.values;

  /// Least recently used first.
  Iterable<MapEntry<K, V>> get entries => _entries.entries;

  /// Forgets every entry and lets go of none — a teardown lets go of what
  /// it must by walking [values] first.
  void clear() {
    _entries.clear();
    _held = 0;
  }
}

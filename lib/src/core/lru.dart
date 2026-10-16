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
/// with a memory warning — and for a store bounded both ways how many too,
/// [entryCap]), what it is still reading ([inUse]), and what letting go of
/// an entry does besides forgetting it ([letGo] — a value owning a native
/// handle disposes it).
///
/// ⛔Not a memo: a value that owns nothing and is cheap to build again goes
/// in `BoundedMemo`, which starts over rather than reshuffle on every hit.
/// ⛔Not a cache a playhead reads, where what it wants latest goes first
/// (`letGoWantedLatest`). ⛔Nor one that pays once for a value several keys
/// share, or that must wait before it lets go — the brush frame store's
/// movie pictures and its cooling (🗣️저장, 2026-10-16): [costOf] is read
/// when an entry comes and when it goes, and [letGo] runs at once.
final class Lru<K, V> {
  Lru({
    required this.limit,
    int Function(V value)? costOf,
    this.entryCap,
    this.inUse,
    this.letGo,
  }) : _costOf = costOf ?? _one;

  /// How much it may hold — entries, or whatever [costOf] counts. Asked
  /// each time it fits, never kept.
  final int Function() limit;

  /// How many entries it may hold whatever they cost, beside [limit] — for
  /// a store bounded both ways: the engine's native uploads, a few big
  /// copies and never more than a few. Null: [limit] alone.
  final int? entryCap;

  /// Whether [K]'s entry is still being read: passed over as the newest
  /// is, and the next least recently used goes in its place — a picture a
  /// render is reading (a numbered run's pages). Null: none is.
  final bool Function(K key)? inUse;

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

  bool get isEmpty => _entries.isEmpty;

  bool get isNotEmpty => _entries.isNotEmpty;

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

  /// [key]'s value made the most recently used — or, with none, the one
  /// [build] builds, kept as it: what `BoundedMemo.resolve` is to a memo.
  /// ⚠️As [use]: a store that keeps nulls builds them again.
  ///
  /// 🔬INLINED, SO A HIT MAKES NO CLOSURE (2026-10-17 — AOT on the Surface
  /// Pro 11, the tip masks' key run, 30 rotated rounds). A caller's [build]
  /// holds what a miss needs — seven values for a tip mask — and a call
  /// made it on every dab, hit or not: 1.156 of the landed use-then-keep
  /// with every mask kept, 1.032 letting go all along. Inlined, it is made
  /// only where a miss calls it: 1.016 and 1.000.
  @pragma('vm:prefer-inline')
  V resolve(K key, V Function() build) {
    final held = use(key);
    if (held != null) {
      return held;
    }
    final built = build();
    keep(key, built);
    return built;
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
  /// [limit] and [entryCap] — never the most recently used: it is what was
  /// just asked for, and what is about to be drawn; nor one still being
  /// read ([inUse]).
  void fit() {
    while (_overLimit()) {
      if (!_letGoOfTheOldest()) {
        return;
      }
    }
  }

  bool _overLimit() {
    final cap = entryCap;
    return _held > limit() || (cap != null && _entries.length > cap);
  }

  /// Lets go of the least recently used entry that may go — false when
  /// none may: what is left is the newest and what is still being read.
  bool _letGoOfTheOldest() {
    final inUse = this.inUse;
    final newest = _entries.length - 1;
    var at = 0;
    for (final key in _entries.keys) {
      if (at == newest) {
        return false;
      }
      if (inUse == null || !inUse(key)) {
        final value = _entries.remove(key) as V;
        _held -= _costOf(value);
        letGo?.call(key, value);
        return true;
      }
      at += 1;
    }
    return false;
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

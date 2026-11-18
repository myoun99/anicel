import 'dart:collection';

/// The collections a model holds: frozen ONCE, then handed on as
/// themselves.
///
/// 🔬Card a-track-copy-wraps-its-unchanged-lists-anew (11-11): every model
/// froze what it was given with `List.unmodifiable` and its kin — which
/// COPY, and copy a collection they froze themselves as readily as one
/// from outside. So a copy that changed one field handed every other
/// collection back through the constructor and got a new object for each:
/// a track that took one stroke in one cut came back with new `seLayers`,
/// `effects` and `expandedLaneGroups`, and every lane list the conte keeps
/// by their identity was read again — seven lane labels drawn again for
/// one stroke, measured.
///
/// ⛔THE GUARANTEE IS UNCHANGED. A collection from outside — one its caller
/// may still hold and change — is copied as it always was. Only a
/// collection these functions froze is known to be frozen, and only that
/// one is handed back as itself.
///
/// 🚨THE MARK IS THE COLLECTION'S OWN CLASS ([_FrozenList] · [_FrozenSet] ·
/// [_FrozenMap]). ↩️It was an [Expando]: a weak table with an entry for
/// every frozen collection alive, which grows — and drops what died — by
/// walking every entry it holds, on whatever thread froze one more. 🔬Card
/// a-thawed-cel-is-adopted-on-the-ui-thread (11-16): a thawed cel's new
/// surface marking its tile map held the UI 33.7 ms there (Surface,
/// profile app: `_settled < frozenMap < BitmapSurface < laidCelSurface`).
/// Plain Dart, the worst single mark among N alive while short-lived ones
/// churn: N = 10k 4.5 ms · 100k 12.7 · 300k 36.3 · 1M 35.6 — a class's,
/// 1.5–4.6 ms (a collection, not the mark), on average 0.02–0.05 µs
/// against 0.06–0.52.
///
/// A class also crosses isolates, which the Expando's mark did not: what
/// a file opens on a worker (`AnicelFileService.open`) arrives frozen, so
/// a copy hands it on as itself with nothing to say. ↩️Every copy said so
/// through `ownFrozen`, kept by a scan.

/// A list frozen here, walked through the list it holds: a view walks
/// itself by index through its delegate, and a `for` over a model's list
/// is the hot use. 🔬Plain Dart, 200k walks of 100 ints: the SDK's own
/// unmodifiable list 36 ms (AOT 65) · a view 77 (143) · this 37 (65) —
/// read by index the three are alike, so only the walk is its own.
final class _FrozenList<E> extends UnmodifiableListView<E> {
  _FrozenList(Iterable<E> items) : this._(List<E>.unmodifiable(items));
  _FrozenList._(this._items) : super(_items);

  final List<E> _items;

  @override
  Iterator<E> get iterator => _items.iterator;
}

/// A set frozen here.
final class _FrozenSet<E> extends UnmodifiableSetView<E> {
  _FrozenSet(Iterable<E> items) : super(Set<E>.of(items));
}

/// A map frozen here.
final class _FrozenMap<K, V> extends UnmodifiableMapView<K, V> {
  _FrozenMap(Map<K, V> entries) : super(Map<K, V>.of(entries));
}

/// 🔬One empty collection for each type (card above, 11-11): most a model
/// holds are empty — no fx, no audio, no twirls — and each was an object of
/// its own. Measured (plain Dart, 1M lists held, 80% of them empty):
/// 216 MB frozen apiece as before, 67–75 MB with one empty for each type.
/// An empty collection changes as little as the next, so a copy keeps it
/// whichever one it is.
final Map<Type, Object> _noLists = {};
final Map<Type, Object> _noSets = {};
final Map<Type, Map<Type, Object>> _noMaps = {};

/// [frozen] — or, when it holds nothing, the one empty collection of its
/// kind and type: [empties]' under [type].
T _settled<T extends Object>(T frozen, Map<Type, Object> empties, Type type) {
  final empty = switch (frozen) {
    final Iterable<Object?> items => items.isEmpty,
    final Map<Object?, Object?> entries => entries.isEmpty,
    _ => false,
  };
  return empty ? (empties[type] ??= frozen) as T : frozen;
}

/// [items] frozen — [items] itself when it is a list frozen here.
List<E> frozenList<E>(Iterable<E> items) => items is _FrozenList<E>
    ? items
    : _settled(_FrozenList<E>(items), _noLists, E);

/// [items] frozen — [items] itself when it is a set frozen here.
Set<E> frozenSet<E>(Iterable<E> items) => items is _FrozenSet<E>
    ? items
    : _settled(_FrozenSet<E>(items), _noSets, E);

/// [entries] frozen — [entries] itself when it is a map frozen here.
Map<K, V> frozenMap<K, V>(Map<K, V> entries) => entries is _FrozenMap<K, V>
    ? entries
    : _settled(_FrozenMap<K, V>(entries), _noMaps[K] ??= {}, V);

/// [built] frozen — or [given] itself when [given] was frozen here and
/// holds what [built] holds: the same keys with the very same values, in
/// the same order.
///
/// For a constructor that BUILDS its map from the one it is given —
/// filling in defaults, dropping the empty — so that a copy handing its
/// own map back still gets that map, and not one built equal to it.
Map<K, V> frozenMapOrSame<K, V>(Map<K, V>? given, Map<K, V> built) =>
    given is _FrozenMap<K, V> && _holdsTheSame(given, built)
    ? given
    : frozenMap(built);

bool _holdsTheSame<K, V>(Map<K, V> given, Map<K, V> built) {
  if (given.length != built.length) {
    return false;
  }
  final others = built.entries.iterator;
  for (final entry in given.entries) {
    others.moveNext();
    final other = others.current;
    if (entry.key != other.key || !identical(entry.value, other.value)) {
      return false;
    }
  }
  return true;
}

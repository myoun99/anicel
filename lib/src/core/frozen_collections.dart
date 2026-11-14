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
/// ⚠️The mark is an [Expando]: weak, so it goes when the collection goes,
/// at one entry for each frozen collection alive — measured (plain Dart,
/// 1M lists held) at ~0.8 µs and ~60–140 bytes a mark.
///
/// 🚨A MARK DOES NOT CROSS ISOLATES: it is this isolate's [Expando], and a
/// file opens on a worker (`AnicelFileService.open`), so every collection
/// an opened project holds arrives here unmarked — and the first copy of
/// each model after opening wrapped them all anew. A copy says what it
/// hands on is its own ([ownFrozen]).
final Expando<bool> _frozen = Expando('frozen by a model');

/// 🔬One empty collection for each type (card above, 11-11): most a model
/// holds are empty — no fx, no audio, no twirls — and each was an object of
/// its own. Measured (plain Dart, 1M lists held, 80% of them empty):
/// 216 MB frozen apiece as before, 67–75 MB with one empty for each type.
/// An empty collection changes as little as the next, so a copy keeps it
/// whichever one it is.
final Map<Type, Object> _noLists = {};
final Map<Type, Object> _noSets = {};
final Map<Type, Map<Type, Object>> _noMaps = {};

bool _isFrozen(Object items) => _frozen[items] ?? false;

T _marked<T extends Object>(T frozen) {
  _frozen[frozen] = true;
  return frozen;
}

/// [frozen] marked — or, when it holds nothing, the one empty collection
/// of its kind and type: [empties]' under [type].
T _settled<T extends Object>(T frozen, Map<Type, Object> empties, Type type) {
  final empty = switch (frozen) {
    final Iterable<Object?> items => items.isEmpty,
    final Map<Object?, Object?> entries => entries.isEmpty,
    _ => false,
  };
  return empty ? (empties[type] ??= _marked(frozen)) as T : _marked(frozen);
}

/// [items] frozen — [items] itself when it is a list frozen here.
List<E> frozenList<E>(Iterable<E> items) =>
    items is List<E> && _isFrozen(items)
    ? items
    : _settled(List<E>.unmodifiable(items), _noLists, E);

/// [items] frozen — [items] itself when it is a set frozen here.
Set<E> frozenSet<E>(Iterable<E> items) =>
    items is Set<E> && _isFrozen(items)
    ? items
    : _settled(Set<E>.unmodifiable(items), _noSets, E);

/// [entries] frozen — [entries] itself when it is a map frozen here.
Map<K, V> frozenMap<K, V>(Map<K, V> entries) => _isFrozen(entries)
    ? entries
    : _settled(Map<K, V>.unmodifiable(entries), _noMaps[K] ??= {}, V);

/// [frozen] — a collection the model handing it on froze itself, marked
/// here so the model it is handed to keeps it as itself.
///
/// For a copy's fallback to its own field (`seLayers ?? ownFrozen(this
/// .seLayers)`), and only where EVERY constructor of the class freezes that
/// field: ⛔it marks without asking, and a list taken as it was handed
/// would be marked frozen while its giver can still change it. The scan
/// `a_model_freezes_through_one_helper_test.dart` holds both.
T ownFrozen<T extends Object>(T frozen) =>
    _isFrozen(frozen) ? frozen : _marked(frozen);

/// [built] frozen — or [given] itself when [given] was frozen here and
/// holds what [built] holds: the same keys with the very same values, in
/// the same order.
///
/// For a constructor that BUILDS its map from the one it is given —
/// filling in defaults, dropping the empty — so that a copy handing its
/// own map back still gets that map, and not one built equal to it.
Map<K, V> frozenMapOrSame<K, V>(Map<K, V>? given, Map<K, V> built) =>
    given != null && _isFrozen(given) && _holdsTheSame(given, built)
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

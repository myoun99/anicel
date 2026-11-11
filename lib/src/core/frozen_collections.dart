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
/// at one entry for each frozen collection alive.
final Expando<bool> _frozen = Expando('frozen by a model');

bool _isFrozen(Object items) => _frozen[items] ?? false;

T _marked<T extends Object>(T frozen) {
  _frozen[frozen] = true;
  return frozen;
}

/// [items] frozen — [items] itself when it is a list frozen here.
List<E> frozenList<E>(Iterable<E> items) =>
    items is List<E> && _isFrozen(items)
    ? items
    : _marked(List<E>.unmodifiable(items));

/// [items] frozen — [items] itself when it is a set frozen here.
Set<E> frozenSet<E>(Iterable<E> items) =>
    items is Set<E> && _isFrozen(items)
    ? items
    : _marked(Set<E>.unmodifiable(items));

/// [entries] frozen — [entries] itself when it is a map frozen here.
Map<K, V> frozenMap<K, V>(Map<K, V> entries) =>
    _isFrozen(entries) ? entries : _marked(Map<K, V>.unmodifiable(entries));

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

import 'package:flutter/foundation.dart';

import '../collection_equality.dart';

/// A memo-token field that compares by IDENTITY.
///
/// The row memos key on a record of their inputs and let the record
/// compare itself; a field that must NOT compare by `==` — a Layer whose
/// `==` is a deep list walk, a notifier, an identity token — says so by
/// wrapping itself here, at its own declaration, instead of in a
/// hand-written match function that could forget a field. The precedent
/// is Flutter's own `ObjectKey`.
final class ByIdentity<T> {
  const ByIdentity(this.value);

  final T value;

  @override
  bool operator ==(Object other) =>
      other is ByIdentity<T> && identical(other.value, value);

  @override
  int get hashCode => identityHashCode(value);
}

/// A memo-token field that compares by SET CONTENTS — a rebuilt set with
/// the same members is the same input.
final class BySet<T> {
  const BySet(this.value);

  final Set<T> value;

  @override
  bool operator ==(Object other) =>
      other is BySet<T> && setEquals(other.value, value);

  @override
  int get hashCode => Object.hashAllUnordered(value);
}

/// A memo-token field that compares by LIST CONTENTS — a rebuilt list
/// with equal elements in the same order is the same input.
///
/// A bare `List` in a record compares by IDENTITY (`List` does not
/// override `==`), so a list that must be compared element-wise says so
/// here rather than being read as changed on every rebuild.
final class ByList<T> {
  const ByList(this.value);

  final List<T> value;

  @override
  bool operator ==(Object other) =>
      other is ByList<T> && listEquals(other.value, value);

  @override
  int get hashCode => Object.hashAll(value);
}

/// A memo-token field that compares by MAP CONTENTS — a rebuilt map with
/// the same keys mapped to equal values is the same input.
final class ByMap<K, V> {
  const ByMap(this.value);

  final Map<K, V> value;

  @override
  bool operator ==(Object other) =>
      other is ByMap<K, V> && mapEquals(other.value, value);

  @override
  int get hashCode => mapHash(value);
}

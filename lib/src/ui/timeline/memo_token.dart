import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

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

/// What a memo holds for one key: the widget as built, and the facts it was
/// built from.
typedef Kept<F> = ({F facts, Widget built});

/// THE keep (F-244): the widget [held] holds for [key] while [facts] are what
/// it was built from — else [build]'s, kept. Flutter skips a subtree handed
/// back the identical widget, so a commit rebuilds nothing whose facts it
/// left alone.
///
/// ONE memo for every kept piece of the frame panels — the rail's rows and
/// the x-sheet's headers, the grids' cells rows, the view cluster: each says
/// only what its facts are (a record of them, each field comparing as the
/// piece needs — [ByIdentity] and kin above).
Widget keptWhileSame<K, F>(
  Map<K, Kept<F>> held,
  K key,
  F facts,
  Widget Function() build,
) {
  final kept = held[key];
  if (kept != null && kept.facts == facts) {
    return kept.built;
  }
  final built = build();
  held[key] = (facts: facts, built: built);
  return built;
}

/// THE keep (F-244) for a piece that keeps ITSELF — one that every frame
/// panel's grid stands up, each making it anew on every build. What it
/// built is handed back while its [facts] are what that was built from,
/// and it stands on a layer of its own: a grid built, laid out and painted
/// again round it builds, lays out and paints none of it.
///
/// 🚨I-57 (10-14): the grids' corner toggle, rail splitter and scrollbars
/// were built, laid out and painted again on every notify and every cut
/// crossed, all three grids alike, while nothing they show had changed.
///
/// What else the piece reads — the theme, the words — rebuilds it where it
/// reads them: [buildKept] runs in a `Builder` of its own, never through
/// this.
abstract class KeptPiece extends StatefulWidget {
  const KeptPiece({super.key});

  /// What the piece shows: a record of everything [buildKept] reads, each
  /// field comparing as the piece needs ([ByIdentity] and kin above). A
  /// callback follows R13-2 — what it closes over is the stable session —
  /// so whether there is one is the fact, never which.
  Object? get facts;

  /// The piece, built afresh.
  Widget buildKept(BuildContext context);

  @override
  State<KeptPiece> createState() => _KeptPieceState();
}

class _KeptPieceState extends State<KeptPiece> {
  Object? _facts;

  /// What was built from [_facts]. ⛔A hot reload drops nothing here: it
  /// builds every element again, the `Builder` [KeptPiece.buildKept] runs
  /// in among them (mutation, I-57 10-14).
  Widget? _built;

  @override
  Widget build(BuildContext context) {
    final facts = widget.facts;
    if (_built == null || facts != _facts) {
      _facts = facts;
      _built = RepaintBoundary(child: Builder(builder: widget.buildKept));
    }
    return _built!;
  }
}

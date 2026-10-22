/// A memo of ONE value per source object, kept on the source's identity —
/// weakly, so it goes when the source does — and answered while the
/// signature it was made under is [same] as the one asked with. A
/// different signature makes the value again and keeps that in its place:
/// the newest wins, and nothing older is held.
///
/// ★ONE memo for the hosts that carried it by hand (2026-10-16, card
/// one-memo-on-an-expando-is-written-four-times): a text's box by the
/// faces in hand, a synced attach row's mirror by its base, a timeline
/// row's agreement with the next instance of itself, a storyboard cut's
/// signature by its edit generation and a track's conte row by its
/// laying. Each kept an `Expando` of its own and spelled the same four
/// lines over it; they differed only in what made two signatures the same.
/// What a row's colour keys make of a thing — the keyed surface, the keyed
/// tile and the carried float's keyed painter — had shared one memo of
/// their own (2026-10-16), the same lines once more: it is this one now.
///
/// ⚠️[same] is the memo's, fixed where it is declared: `identical` for an
/// immutable model (`==` on one may be a deep compare, and the wrong law —
/// a rebuilt-equal instance is a different object), `listEquals` for
/// values, `==` (the default) for a number.
final class SignedMemo<S, V> {
  SignedMemo(String name, {bool Function(S kept, S asked)? same})
    : _kept = Expando<(S, V)>(name),
      _same = same ?? _equal;

  final Expando<(S, V)> _kept;
  final bool Function(S kept, S asked) _same;

  /// What [make] makes of [source] under [signature] — kept from the last
  /// ask while that ask's signature is [same] as this one.
  V resolve(Object source, S signature, V Function() make) {
    final kept = _kept[source];
    if (kept != null && _same(kept.$1, signature)) {
      return kept.$2;
    }
    final value = make();
    _kept[source] = (signature, value);
    return value;
  }

  /// The value kept for [source], under whatever signature it was last
  /// made — null where none is. A LOOKUP: it makes nothing.
  V? keptOf(Object source) => _kept[source]?.$2;
}

bool _equal(Object? kept, Object? asked) => kept == asked;

/// A one-slot memo of a value derived from an immutable object, keyed on
/// that object's IDENTITY plus one optional extra key.
///
/// The repository hands out immutable models, so "has the project
/// changed" is `identical` — never `==`, which on a Project is a deep
/// value compare (slow, and the wrong law: a rebuilt-equal project is a
/// different object with different sub-object identities). The extra
/// [key] is compared with `==`: a cut id, a camera aspect, a page.
///
/// ONE memo for the three hosts that carried it by hand (the conte's
/// sheet, the storyboard host's active-track layout, the session's
/// whole-project layout — the last's own comment named it "the same memo
/// the storyboard host keeps"). A hit costs a field read and two
/// compares, no allocation: these are asked per playback tick and per
/// scrub move.
class IdentityMemo<V> {
  Object? _identity;
  Object? _key;
  V? _value;

  /// The memoised value for [identity] (+ [key]), built by [build] on the
  /// first ask and again only when either changes.
  V resolve({
    required Object identity,
    Object? key,
    required V Function() build,
  }) {
    final cached = _value;
    if (cached != null && identical(identity, _identity) && key == _key) {
      return cached;
    }
    final value = build();
    _identity = identity;
    _key = key;
    _value = value;
    return value;
  }
}

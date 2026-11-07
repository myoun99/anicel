import 'package:flutter/foundation.dart' show Listenable, VoidCallback;

/// Listeners held by what they show: a painter that shows a [K] hears the
/// changes that name it ([notice]), never another's — each key's listeners
/// come as its painters are attached and go as they are detached, so a key
/// nothing shows is not held.
///
/// 🚨Written once (conte-one-eye-repaints-every-track, 2026-11-08). It was
/// written out by hand twice — the timeline tiles' landings by row (I-22 ③)
/// and the rows' cel answers by row (one-cel-turning-white-repaints-every-
/// row) — and the panel pictures' landings by cut were the third.
final class KeyedNotices<K extends Object> {
  KeyedNotices({void Function(K key)? unheard}) : _unheard = unheard;

  final Map<K, List<VoidCallback>> _listeners = {};

  /// Told when the last listener of a key goes — what the owner kept for a
  /// key only while something shows it goes with it.
  final void Function(K key)? _unheard;

  /// What a painter showing [key] listens to.
  Listenable of(K key) => _Heard(this, key);

  /// Whether something shows [key] now.
  bool isHeard(K key) => _listeners.containsKey(key);

  /// Tells whatever shows any of [keys] — each listener once, though it
  /// shows several of them.
  void notice(Iterable<K> keys) => _tell({
    for (final key in keys) ...?_listeners[key],
  });

  /// Tells whatever shows anything.
  void noticeAll() => _tell({
    for (final listeners in _listeners.values) ...listeners,
  });

  /// Forgets every listener.
  void clear() => _listeners.clear();

  /// [listeners] are a copy: a listener may come or go while the others are
  /// told.
  static void _tell(Set<VoidCallback> listeners) {
    for (final listener in listeners) {
      listener();
    }
  }
}

/// A key's side of a [KeyedNotices].
final class _Heard<K extends Object> implements Listenable {
  const _Heard(this._notices, this._key);

  final KeyedNotices<K> _notices;
  final K _key;

  @override
  void addListener(VoidCallback listener) => _notices._listeners
      .putIfAbsent(_key, () => <VoidCallback>[])
      .add(listener);

  @override
  void removeListener(VoidCallback listener) {
    final listeners = _notices._listeners[_key];
    if (listeners == null) {
      return;
    }
    listeners.remove(listener);
    if (listeners.isEmpty) {
      _notices._listeners.remove(_key);
      _notices._unheard?.call(_key);
    }
  }
}

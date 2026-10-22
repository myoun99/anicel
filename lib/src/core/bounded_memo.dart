/// A memo of values built from their keys that holds at most [held] of
/// them, and starts over — lets every value go — when one more would pass
/// that.
///
/// ONE memo for the three that carried it by hand (2026-10-15, I-57): a
/// brush tip's levels (`brushTipMaskWithCachedLevels`), the dab's evening
/// tables (`eveningTableFor`) and a ruler's writing (`TimelineRulerScale
/// .writtenAt`) each looked a key up in a map of their own, cleared the map
/// once it held its bound and built the value on a miss. The fourth, a
/// scale's sampling phase (`samplingPhaseFor`), let only its oldest go
/// (card every-bounded-cache-is-one-lru, 2026-10-16) — and under a pinch,
/// a new scale every frame, the other canvas's went as often either way.
///
/// ⛔Not an LRU: a miss costs one build — what the call paid before it was
/// memoised — so the bound only limits what a long run leaves behind, and a
/// recency shuffle on every hit was most of what the dab's share cost a
/// stroke (2026-10-01, `eveningTableFor`).
final class BoundedMemo<K, V extends Object> {
  BoundedMemo(this.held);

  /// The most values the memo holds.
  final int held;

  final Map<K, V> _built = <K, V>{};

  /// The value for [key] — built by [build] the first time it is asked, and
  /// again only once the memo has started over.
  V resolve(K key, V Function() build) {
    final kept = _built[key];
    if (kept != null) {
      return kept;
    }
    if (_built.length >= held) {
      _built.clear();
    }
    return _built[key] = build();
  }
}

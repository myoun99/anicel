/// A NESTING reference count, keyed by [K]: two widgets may hold the same
/// slot, and the slot stays pinned until both let go.
///
/// ⛔RELEASE WITHOUT RETAIN IS AN ASSERT, NOT A SILENT NO-OP — an
/// unbalanced release is a caller bug, and swallowing it would leave the
/// count one too low and evict a slot somebody is still drawing.
///
/// ⛔THE PAIR THAT HAS TO AGREE is retain's `?? 0` and release's
/// remove-at-one: a release that decremented to ZERO without removing
/// leaves the key present forever, and a key that is present is pinned —
/// an image the cache can then never evict. Both playback caches counted
/// this by hand before.
class PinCounts<K> {
  final Map<K, int> _counts = <K, int>{};

  void retain(K key) => _counts[key] = (_counts[key] ?? 0) + 1;

  void release(K key) {
    final count = _counts[key];
    if (count == null) {
      assert(false, 'release without a matching retain: $key');
      return;
    }
    if (count <= 1) {
      _counts.remove(key);
    } else {
      _counts[key] = count - 1;
    }
  }

  bool isPinned(K key) => _counts.containsKey(key);

  Iterable<K> get keys => _counts.keys;
}

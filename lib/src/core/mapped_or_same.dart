/// [items] with [update] applied to each — and [items] ITSELF when no
/// item changed, so the caller can ask `identical(next, items)` and skip
/// its own `copyWith`.
///
/// Identity-preserving on no-ops, so an already-normal project passes
/// through untouched. Four write-time normalizations (the covering image
/// row, the covering storyboard row, the attach mirrors and the
/// repository's per-track/per-cut walk over them) each wrote this walk
/// out by hand; the contract is theirs, stated once here. A result that
/// is EQUAL but not identical counts as a change — the walk asks
/// identity, never `==`, because equality over a timeline is the very
/// cost the no-op path exists to avoid.
List<T> mappedOrSame<T>(List<T> items, T Function(T item) update) {
  List<T>? next;
  for (var i = 0; i < items.length; i += 1) {
    final item = items[i];
    final updated = update(item);
    if (identical(updated, item)) {
      continue;
    }
    (next ??= [...items])[i] = updated;
  }
  return next ?? items;
}

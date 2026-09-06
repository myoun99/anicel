/// The inclusive run of [items] between [anchor] and [head], in list order
/// however the drag ran — or null when either end is not in the list.
///
/// ⛔TWO FAMILIES SLICED THEIR OWN ORDER — the effect lanes and the
/// transform lanes — and a third (the name tags) had already been retired
/// for it. Ids OUTSIDE the order fall back to the anchor alone: a span
/// cannot be honestly named when one end is not on the list, and the press
/// keeps only itself rather than guessing a direction. The slice is the
/// same over lane ids and over drawn row addresses, so it is generic and
/// the "anchor alone" answer is the callers' `?? [anchor]`.
library;

List<T>? inclusiveRunBetween<T>(List<T> items, T anchor, T head) {
  final anchorIndex = items.indexOf(anchor);
  final headIndex = items.indexOf(head);
  if (anchorIndex < 0 || headIndex < 0) {
    return null;
  }
  final low = anchorIndex < headIndex ? anchorIndex : headIndex;
  final high = anchorIndex < headIndex ? headIndex : anchorIndex;
  return items.sublist(low, high + 1);
}

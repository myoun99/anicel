/// Copy-then-flip-membership over an IMMUTABLE value set: the caller holds
/// a set it must not mutate (a `copyWith` field, a `ValueNotifier<Set<T>>`
/// whose identity is the change signal), so the toggle answers with a NEW
/// set and leaves [source] alone.
///
/// Removing first and adding only when nothing was removed is the whole
/// law — one membership probe, not `contains` followed by a second walk.
///
/// The sites that toggle a set they OWN in place (`if (!set.add(k))
/// set.remove(k)`) are a different idiom and keep it: this one exists to
/// answer with a value.
Set<T> toggledSet<T>(Set<T> source, T value) {
  final next = Set<T>.of(source);
  if (!next.remove(value)) {
    next.add(value);
  }
  return next;
}

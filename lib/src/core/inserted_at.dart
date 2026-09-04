/// [items] with [item] placed at [index] — appended when [index] is null,
/// and the index CLAMPED into range.
///
/// ⛔THE CLAMP IS THE LAW FOR ROWS. Three layer inserts wrote this out
/// (a track's SE rows, a cut's layers, the add-layer command) and an
/// index past the end lands at the end in all three — a row arriving
/// from a stale count still lands rather than half-applying.
///
/// ⚠️A CUT insert is NOT this law: [ProjectRepository.insertCut] throws
/// on an out-of-range index on purpose, and says so at its own site.
List<T> insertedAt<T>(List<T> items, T item, int? index) {
  final next = [...items];
  if (index == null) {
    next.add(item);
  } else {
    next.insert(index.clamp(0, next.length).toInt(), item);
  }
  return next;
}

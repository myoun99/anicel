/// [items] resequenced to exactly [order]. [order] must be a permutation
/// of the items' ids — a partial or foreign list is a programming error,
/// not a silent drop, and [orderName] names it in the error.
///
/// 🚨ONE law for the repository's three orderings — a track's cuts, a
/// cut's layers, a track's SE rows (the audit's clone scan, 2026-09-03).
List<T> reorderedByIds<T, I>(
  List<T> items,
  List<I> order, {
  required I Function(T item) idOf,
  required String orderName,
}) {
  final byId = {for (final item in items) idOf(item): item};
  if (order.length != items.length ||
      order.toSet().length != order.length ||
      !order.every(byId.containsKey)) {
    throw StateError('$orderName must be a permutation of its members.');
  }
  return [for (final id in order) byId[id]!];
}

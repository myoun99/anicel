/// The inclusive run of [order] between [anchorLaneId] and [headLaneId],
/// in display order however the drag ran.
///
/// ⛔TWO FAMILIES SLICED THEIR OWN ORDER — the effect lanes and the
/// transform lanes — and a third (the name tags) had already been retired
/// for it. Ids OUTSIDE the order fall back to the anchor alone: a span
/// cannot be honestly named when one end is not on the list, and the press
/// keeps only itself rather than guessing a direction.
library;

List<String> laneSpanInOrder(
  List<String> order,
  String anchorLaneId,
  String headLaneId,
) {
  final anchor = order.indexOf(anchorLaneId);
  final head = order.indexOf(headLaneId);
  if (anchor < 0 || head < 0) {
    return [anchorLaneId];
  }
  final low = anchor < head ? anchor : head;
  final high = anchor < head ? head : anchor;
  return order.sublist(low, high + 1);
}

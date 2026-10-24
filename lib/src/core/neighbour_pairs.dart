/// Each of [items] with the one after it, in order — none for fewer than
/// two.
///
/// 🚨ONE WALK. Every list walked two at a time — a curve's segments
/// between its keys, the speeds between them, a header graph's stroke from
/// point to point, the ruler's paper between its edges, the camera's moves
/// between its keys, the cut after each cut — was an `index + 1 <` loop of
/// its own, and the clone scan read the header graph's third one (I-3 ④,
/// a pen press on the stroke) as a copy of the ruler's.
Iterable<(T, T)> neighbourPairs<T>(List<T> items) sync* {
  for (var index = 0; index + 1 < items.length; index += 1) {
    yield (items[index], items[index + 1]);
  }
}

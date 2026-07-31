/// Resolving "which row is the pointer over?" from a cross-axis pixel
/// offset — the one question the shared range gesture must hand upward.
///
/// R9 #25. The gesture used to hand up a row COUNT, computed by dividing
/// the pointer's offset by ONE row height: the height of the row the drag
/// STARTED on. That carries an unstated invariant — *every row is as tall
/// as mine* — which is true on the timeline (`layerRowHeight` for layer
/// rows and lane rows alike) and false on the storyboard rail, where an SE
/// row is 30px, the V row is 28–160px, and a twirled-open SE row wedges
/// audio (36px) and transform (26px) strips in between.
///
/// So a drag UP from the V row under-counted the SE rows by
/// `laneHeight / 30` and stalled in the middle of the list, while a drag
/// DOWN survived only because the end clamp happened to catch it. The user
/// reported exactly that asymmetry: S4 → V works, V → S4 stops at S1.
///
/// The lesson is narrower than "the storyboard was wrong": what got shared
/// was the DERIVED value (a row delta) while the RAW value (the pointer's
/// position) stayed private to each surface. The gesture emits the raw
/// offset now, and each surface resolves it with the same heights it uses
/// to PAINT — so the answer can no longer disagree with what is on screen.
library;

/// Uniform-pitch resolve, for a surface whose rows are all one height.
///
/// [crossOffset] is measured from the anchor row's TOP (negative above it),
/// which is what the gesture's local cross-axis position already is.
int uniformRowDeltaForCrossOffset({
  required double crossOffset,
  required double rowExtent,
}) {
  if (rowExtent <= 0) {
    return 0;
  }
  return (crossOffset / rowExtent).floor();
}

/// Height-table resolve, for a surface whose rows differ.
///
/// [heights] is every VISUAL row top-to-bottom — including rows a drag
/// cannot land on, because they still take up space — and [anchorIndex] is
/// where the drag started. Returns an index into [heights], clamped to the
/// table: running off either end stops at the last row, which is the same
/// "the clamp IS the guard" rule the row list already relied on.
int rowIndexForCrossOffset({
  required double crossOffset,
  required int anchorIndex,
  required List<double> heights,
}) {
  if (heights.isEmpty) {
    return 0;
  }
  final anchor = anchorIndex.clamp(0, heights.length - 1);
  if (crossOffset >= 0) {
    var consumed = 0.0;
    for (var index = anchor; index < heights.length; index += 1) {
      consumed += heights[index];
      if (crossOffset < consumed) {
        return index;
      }
    }
    return heights.length - 1;
  }
  var top = 0.0;
  for (var index = anchor - 1; index >= 0; index -= 1) {
    top -= heights[index];
    if (crossOffset >= top) {
      return index;
    }
  }
  return 0;
}

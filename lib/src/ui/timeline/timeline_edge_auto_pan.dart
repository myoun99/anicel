/// How far a drag at [pos] has pushed past either end of a [extent]-long
/// axis, once it enters the [edge]-wide band at either end: negative near
/// the start, positive near the end, zero in the middle. The caller adds
/// this to its scroll offset to auto-pan.
///
/// Every timeline and storyboard edge-scroll shares this 24px band, so the
/// band width and the past-the-edge math live here once.
///
/// A viewport shorter than BOTH bands has no middle: `pos > extent - edge`
/// and `pos < edge` are then true everywhere, and every press — not just a
/// drag near an end — reads as an edge push. R10 R6 made that reachable for
/// the first time (the x-sheet's frame rail can now be 16px tall in a short
/// panel), and the symptom was the playhead running away under a stationary
/// pen. There is nothing to pan toward in a viewport that IS the edge, so
/// the answer is zero.
double edgeAutoPanDelta(double pos, double extent, {double edge = 24.0}) {
  if (extent < 2 * edge) {
    return 0;
  }
  if (pos > extent - edge) {
    return pos - (extent - edge);
  }
  if (pos < edge) {
    return pos - edge;
  }
  return 0;
}

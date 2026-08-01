import 'dart:math' as math;

/// How far a drag at [pos] has pushed past either end of a [extent]-long
/// axis, once it enters the [edge]-wide band at either end: negative near
/// the start, positive near the end, zero in the middle. The caller adds
/// this to its scroll offset to auto-pan.
///
/// Every timeline and storyboard edge-scroll shares this 24px band, so the
/// band width and the past-the-edge math live here once.
///
/// The band NARROWS with the viewport, never past a quarter of it, so half
/// the viewport is always neutral middle.
///
/// R10 R6 made small viewports reachable for the first time — the x-sheet's
/// frame rail is 66–96px at real dock heights and can be smaller — and a
/// fixed 24px band there is most of the rail: two of them leave 18px of
/// middle in a 66px rail, so a plain press (the rail scrubs from
/// `onPointerDown`, not only from a drag) reads as an edge push and the
/// playhead runs away under a stationary pen. Zeroing only below 48px, as
/// the first fix did, was a cliff rather than an answer: it left every
/// viewport a user can actually produce on the wrong side of it.
double edgeAutoPanDelta(double pos, double extent, {double edge = 24.0}) {
  if (extent <= 0) {
    return 0;
  }
  final band = math.min(edge, extent / 4);
  if (pos > extent - band) {
    return pos - (extent - band);
  }
  if (pos < band) {
    return pos - band;
  }
  return 0;
}

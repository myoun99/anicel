import 'dart:ui' show Offset;

/// Where [point] falls along the line from [a] (0) to [b] (1) — its
/// projection onto that line, unclamped; 0 when the two are one point.
///
/// 🚨ONE PROJECTION. A point's nearest on a segment was worked out by hand
/// twice — a model point's ([CanvasPoint.inverseLerp], what a track's auto
/// key and a stroke's wobble are measured by) and the colour wheel's
/// triangle edge — and a header graph's line would have been the third
/// (I-3 ④: a pen press lands on the line or not). The same algorithm
/// written apart is a copy, whatever its text looks like.
double shareAlongSegment(Offset point, Offset a, Offset b) {
  final ab = b - a;
  final length = ab.dx * ab.dx + ab.dy * ab.dy;
  if (length == 0) {
    return 0;
  }
  final ap = point - a;
  return (ap.dx * ab.dx + ap.dy * ab.dy) / length;
}

/// The point of the segment [a]–[b] nearest [point].
Offset nearestOnSegment(Offset point, Offset a, Offset b) =>
    a + (b - a) * shareAlongSegment(point, a, b).clamp(0.0, 1.0);

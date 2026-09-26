import 'dart:ui';

/// The part of the convex polygon [subject] that lies inside the convex
/// polygon [clip] — each as its corners in order, either way round — or
/// empty where they do not meet.
///
/// [subject] cut by the line of each edge of [clip] in turn
/// (Sutherland–Hodgman), keeping the side the rest of [clip] is on.
List<Offset> convexIntersection(List<Offset> subject, List<Offset> clip) {
  final inside = _insideOf(clip);
  var kept = subject;
  for (var edge = 0; edge < clip.length && kept.isNotEmpty; edge += 1) {
    final from = clip[edge];
    final to = clip[(edge + 1) % clip.length];
    final cut = kept;
    kept = [];
    for (var index = 0; index < cut.length; index += 1) {
      final here = cut[index];
      final before = cut[(index + cut.length - 1) % cut.length];
      final hereIn = inside(from, to, here);
      if (hereIn != inside(from, to, before)) {
        kept.add(_crossing(before, here, from, to));
      }
      if (hereIn) {
        kept.add(here);
      }
    }
  }
  return kept;
}

/// Whether [point] lies in the convex polygon [polygon], its edges
/// included. A polygon of fewer than three corners holds nothing.
bool convexContains(List<Offset> polygon, Offset point) {
  if (polygon.length < 3) {
    return false;
  }
  final inside = _insideOf(polygon);
  for (var edge = 0; edge < polygon.length; edge += 1) {
    if (!inside(polygon[edge], polygon[(edge + 1) % polygon.length], point)) {
      return false;
    }
  }
  return true;
}

/// Whether a point is on [polygon]'s side of the line from one corner to
/// the next — the side its area lies on, whichever way round it goes.
bool Function(Offset from, Offset to, Offset point) _insideOf(
  List<Offset> polygon,
) {
  var doubleArea = 0.0;
  for (var index = 0; index < polygon.length; index += 1) {
    doubleArea += _cross(polygon[index], polygon[(index + 1) % polygon.length]);
  }
  final inward = doubleArea >= 0 ? 1.0 : -1.0;
  return (from, to, point) => _cross(to - from, point - from) * inward >= 0;
}

double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;

/// Where the segment [start]→[end] meets the line through [from] and [to].
Offset _crossing(Offset start, Offset end, Offset from, Offset to) {
  final line = to - from;
  final along = _cross(line, from - start) / _cross(line, end - start);
  return start + (end - start) * along;
}

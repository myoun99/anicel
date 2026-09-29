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
    kept = _keptBy(kept, clip[edge], clip[(edge + 1) % clip.length], inside);
  }
  return kept;
}

/// The convex polygon [polygon] with every edge moved [by] toward its
/// inside — the points at least [by] within it — or empty where nothing
/// is.
///
/// [polygon] cut by each of its own edges' lines moved in, the way
/// [convexIntersection] cuts by a clip's.
List<Offset> convexInset(List<Offset> polygon, double by) {
  if (polygon.length < 3 || by <= 0) {
    return polygon;
  }
  final inside = _insideOf(polygon);
  final inward = _inwardSign(polygon);
  var kept = polygon;
  for (var edge = 0; edge < polygon.length && kept.isNotEmpty; edge += 1) {
    final start = polygon[edge];
    final end = polygon[(edge + 1) % polygon.length];
    final along = end - start;
    if (along.distance == 0) {
      continue;
    }
    final shift = Offset(-along.dy, along.dx) * (inward * by / along.distance);
    kept = _keptBy(kept, start + shift, end + shift, inside);
  }
  return kept;
}

/// [polygon] cut by the line [from]→[to], keeping the side [inside] says
/// — one step of Sutherland–Hodgman.
List<Offset> _keptBy(
  List<Offset> polygon,
  Offset from,
  Offset to,
  bool Function(Offset from, Offset to, Offset point) inside,
) {
  final kept = <Offset>[];
  for (var index = 0; index < polygon.length; index += 1) {
    final here = polygon[index];
    final before = polygon[(index + polygon.length - 1) % polygon.length];
    final hereIn = inside(from, to, here);
    if (hereIn != inside(from, to, before)) {
      kept.add(_crossing(before, here, from, to));
    }
    if (hereIn) {
      kept.add(here);
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
  final inward = _inwardSign(polygon);
  return (from, to, point) => _cross(to - from, point - from) * inward >= 0;
}

/// Which side of its edges [polygon]'s area lies on: 1 to the left of an
/// edge's direction (a positive cross), -1 to the right.
double _inwardSign(List<Offset> polygon) {
  var doubleArea = 0.0;
  for (var index = 0; index < polygon.length; index += 1) {
    doubleArea += _cross(polygon[index], polygon[(index + 1) % polygon.length]);
  }
  return doubleArea >= 0 ? 1.0 : -1.0;
}

double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;

/// Where the segment [start]→[end] meets the line through [from] and [to].
Offset _crossing(Offset start, Offset end, Offset from, Offset to) {
  final line = to - from;
  final along = _cross(line, from - start) / _cross(line, end - start);
  return start + (end - start) * along;
}

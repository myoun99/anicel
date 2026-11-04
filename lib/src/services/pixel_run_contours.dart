import 'dart:math' as math;

import '../models/canvas_point.dart';

/// The closed contours of the pixels [rows] hold — row `r` is the canvas
/// row `top + r`, its `[start, end, …]` columns counted from [left], in a
/// box [width] pixels wide — on the pixel grid, in CANVAS space.
///
/// One walk for every outline drawn around pixels: a selection's committed
/// ants (`CanvasSelectionRegion.pixelOutlineIn`) and the range a fill held
/// down will cover (I-160). ↩️It was the selection's own until the fill
/// needed the same outline of its flood.
///
/// The contours are CLOSED and walk consistently, so a dash phase runs
/// around a whole component (and around a hole), and a fill of them carves
/// the holes out under the default winding.
List<List<CanvasPoint>> pixelRunContours(
  List<List<int>> rows, {
  required int left,
  required int top,
  required int width,
}) {
  if (width <= 0 || rows.isEmpty) {
    return <List<CanvasPoint>>[];
  }
  final edges = _boundaryEdges(rows, width);
  CanvasPoint at(int v) => CanvasPoint(
    x: (left + v % (width + 1)).toDouble(),
    y: (top + v ~/ (width + 1)).toDouble(),
  );
  final contours = <List<CanvasPoint>>[];
  while (edges.isNotEmpty) {
    final contour = _walkContour(edges, edges.keys.first, width + 1, at);
    // ⚠️And once more AROUND the join. The walk starts wherever the edge
    // map happened to hand it a vertex, which is usually the middle of a
    // straight run, and the segment that closes the contour is implied
    // rather than stepped — so the first and last points can each sit in
    // the middle of a line the merge in the walk never saw the two halves
    // of. 🧪Without this a rectangle came back with five corners.
    while (contour.length > 3 &&
        _isStraight(
          contour[contour.length - 2],
          contour.last,
          contour.first,
        )) {
      contour.removeLast();
    }
    while (contour.length > 3 &&
        _isStraight(contour.last, contour.first, contour[1])) {
      contour.removeAt(0);
    }
    contours.add(contour);
  }
  return contours;
}

/// Every boundary edge of the pixels [rows] hold as vertex → vertex, keyed
/// by the vertex it starts at, in a box [width] pixels wide. Wound so that
/// the covered side is on the same hand throughout: a component runs one
/// way and a hole the other, which is what makes the outline's fill carve
/// rather than cover.
///
/// 🚨ROW BY ROW, NEVER A MASK (I-23). An inverse's box is the whole
/// pasteboard wall — about 35MB at a byte a pixel for a 2340×1654 canvas,
/// allocated and read on the paint thread before one ant was drawn. Only
/// a pixel with an edge is visited: a run's two ends, and where the row
/// above or below leaves it uncovered.
///
/// ⛔In exactly the order the pixel-by-pixel scan this replaced emitted
/// them — row-major, then top, right, bottom, left within a pixel — so
/// every contour starts where it always did and the dashes stay put.
Map<int, List<int>> _boundaryEdges(List<List<int>> rows, int width) {
  final edges = <int, List<int>>{};
  void edge(int x0, int y0, int x1, int y1) {
    edges
        .putIfAbsent(y0 * (width + 1) + x0, () => <int>[])
        .add(y1 * (width + 1) + x1);
  }

  for (var y = 0; y < rows.length; y += 1) {
    final above = _RunCursor(y > 0 ? rows[y - 1] : const []);
    final below = _RunCursor(y + 1 < rows.length ? rows[y + 1] : const []);
    final runs = rows[y];
    for (var r = 0; r + 1 < runs.length; r += 2) {
      final start = runs[r];
      final end = runs[r + 1];
      var x = start;
      while (x < end) {
        final up = above.covers(x);
        final down = below.covers(x);
        if (!up) edge(x, y, x + 1, y);
        if (x == end - 1) edge(x + 1, y, x + 1, y + 1);
        if (!down) edge(x + 1, y + 1, x, y + 1);
        if (x == start) edge(x, y + 1, x, y);
        if (up && down) {
          // Covered above and below, nothing has an edge until one of
          // the three runs ends.
          final next = math.min(math.min(above.end, below.end), end - 1);
          x = math.max(x + 1, next);
        } else {
          x += 1;
        }
      }
    }
  }
  return edges;
}

/// One closed contour of [edges], walked from [start] and consumed as it
/// goes — [stride] is a row of vertices, [at] a vertex's canvas point.
List<CanvasPoint> _walkContour(
  Map<int, List<int>> edges,
  int start,
  int stride,
  CanvasPoint Function(int vertex) at,
) {
  var current = start;
  final contour = <CanvasPoint>[at(start)];
  // ⚠️STRAIGHT RUNS COLLAPSE. The walk emits one vertex per pixel edge,
  // so a plain rectangle would arrive as four thousand-point sides and
  // be rebuilt into a `Path` on every animation tick. Merging while
  // walking makes an axis-aligned outline four points again; a true
  // staircase (a rotated or lassoed edge) keeps its steps, because
  // those steps ARE the answer.
  var lastDx = 0;
  var lastDy = 0;
  // ⚠️Bounded by the edge count rather than trusted to close: a
  // malformed walk must end, not hang the paint thread.
  var guard = edges.length * 4 + 8;
  while (guard-- > 0) {
    final outgoing = edges[current];
    if (outgoing == null || outgoing.isEmpty) {
      break;
    }
    final next = outgoing.removeLast();
    if (outgoing.isEmpty) {
      edges.remove(current);
    }
    if (next == start) {
      break;
    }
    final dx = next % stride - current % stride;
    final dy = next ~/ stride - current ~/ stride;
    if (dx == lastDx && dy == lastDy && contour.length > 1) {
      contour[contour.length - 1] = at(next);
    } else {
      contour.add(at(next));
    }
    lastDx = dx;
    lastDy = dy;
    current = next;
  }
  return contour;
}

/// Whether [b] sits on the straight line from [a] to [c] — the test the
/// contour merge asks at a join. Axis-aligned steps only, which is all a
/// pixel boundary ever has.
bool _isStraight(CanvasPoint a, CanvasPoint b, CanvasPoint c) =>
    (b.x - a.x) * (c.y - b.y) == (b.y - a.y) * (c.x - b.x);

/// One row's pixel runs, read left to right: asked about columns that never
/// go back, it answers in a single pass over the row.
final class _RunCursor {
  _RunCursor(this._runs);

  final List<int> _runs;
  int _at = 0;

  /// Whether a run covers column [x].
  bool covers(int x) {
    while (_at + 1 < _runs.length && _runs[_at + 1] <= x) {
      _at += 2;
    }
    return _at + 1 < _runs.length && _runs[_at] <= x;
  }

  /// Where the run [covers] last found ends — asked only after a yes.
  int get end => _runs[_at + 1];
}

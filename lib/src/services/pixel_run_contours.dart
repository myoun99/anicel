import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

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
  final laid = _boundaryEdges(rows, width);
  final edges = _EdgeTable.of(laid, width: width, lines: rows.length + 1);
  CanvasPoint at(int x, int y) =>
      CanvasPoint(x: (left + x).toDouble(), y: (top + y).toDouble());
  final contours = <List<CanvasPoint>>[];
  // Every vertex in the order its first edge was laid, walked from for as
  // long as it still has an edge — the very starts the walk always took,
  // in the same order. ↩️It used to ask the edge map for its first key
  // before each contour: a removed key kept its place in the map's order,
  // so every ask walked past every vertex already consumed — quadratic in
  // the outline (🔬I-160, a 4K range with 5000 small holes: 730 ms).
  for (var edge = 0; edge < laid.length; edge += 1) {
    final line = laid.ys[edge];
    final start = edges.placeFirstLaidBy(edge, line);
    if (start < 0) {
      continue;
    }
    while (edges.hasAt(start, line)) {
      contours.add(_closedContour(edges, laid.xs[edge], line, at));
    }
  }
  return contours;
}

/// The contour walked from vertex ([x], [y]) ([_walkContour]), its join
/// merged.
List<CanvasPoint> _closedContour(
  _EdgeTable edges,
  int x,
  int y,
  CanvasPoint Function(int x, int y) at,
) {
  final contour = _walkContour(edges, x, y, at);
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
  return contour;
}

/// Every boundary edge of the pixels [rows] hold, by the vertex it starts
/// at and the way it goes, in a box [width] pixels wide. Wound so that the
/// covered side is on the same hand throughout: a component runs one way
/// and a hole the other, which is what makes the outline's fill carve
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
///
/// A row's run is taken a STRETCH at a time — pixels the rows above and
/// below cover alike — and a stretch's top and bottom are laid an edge
/// each rather than a pixel's each: its top from its first pixel's corner,
/// as that pixel laid its own; its bottom as its first pixel laid its own,
/// then the rest from the stretch's end, as its last pixel laid its own.
/// So every vertex an edge still starts from is laid when the scan laid
/// it, beside the others there in the same order — where each contour
/// starts and which way a corner turns stay put; a vertex an edge now
/// passes over had the one boundary through it, and was laid after a
/// vertex on the same contour that stays.
/// ↩️A pixel's edge each, every pixel along a stretch a vertex: an
/// inverse's outline was some twenty thousand edges to lay and walk (L2e,
/// board `a-selection-mask-is-built-on-the-cpu-at-every-move`).
_LaidEdges _boundaryEdges(List<List<int>> rows, int width) {
  final edges = _LaidEdges();

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
        final to = math.min(
          end,
          math.min(above.changesAfter(x), below.changesAfter(x)),
        );
        if (!up) edges.add(x, y, _right, to - x);
        if (x == end - 1) edges.add(x + 1, y, _down, 1);
        if (!down) edges.add(x + 1, y + 1, _left, 1);
        if (x == start) edges.add(x, y + 1, _up, 1);
        if (to - 1 > x) {
          if (to == end) edges.add(to, y, _down, 1);
          if (!down) edges.add(to, y + 1, _left, to - 1 - x);
        }
        x = to;
      }
    }
  }
  return edges;
}

/// Test seam: how many edges [_boundaryEdges] lays for [rows].
@visibleForTesting
int debugBoundaryEdgeCount(List<List<int>> rows, int width) =>
    _boundaryEdges(rows, width).length;

/// The ways a boundary edge goes from the vertex it starts at.
const _right = 0;
const _down = 1;
const _left = 2;
const _up = 3;

/// How far an edge's every step moves its vertex, across and down, each
/// way ([_right], [_down], [_left], [_up]).
const _acrossBy = [1, 0, -1, 0];
const _downBy = [0, 1, 0, -1];

/// The boundary's edges in the order they were laid: the vertex each
/// starts from — its column and line — and its way and span.
final class _LaidEdges {
  Int32List xs = Int32List(1024);
  Int32List ys = Int32List(1024);

  /// The way in bits 0–1, the span — in vertices — above them.
  Int32List ways = Int32List(1024);

  /// How many edges were laid.
  int length = 0;

  void add(int x, int y, int way, int span) {
    if (length == xs.length) {
      xs = _grown(xs);
      ys = _grown(ys);
      ways = _grown(ways);
    }
    xs[length] = x;
    ys[length] = y;
    ways[length] = span << 2 | way;
    length += 1;
  }

  static Int32List _grown(Int32List list) =>
      Int32List(list.length * 2)..setRange(0, list.length, list);
}

/// The laid edges found by the vertex they start from: sorted by line, then
/// column, then the order they were laid — a counting sort each, so a
/// vertex's edges sit side by side, the last laid last, the first taken as
/// the walk always took them — and a vertex found in its line by halving.
/// A vertex of a pixel boundary has at most two edges out (two pixels
/// touching only at a corner).
///
/// ↩️A table hashed by vertex until L2e — I-160 had made it one flat table
/// of open addressing from a map of a list per vertex (🔬a 4K range with
/// 20000 small holes: 650–730 ms → 210–280) — and its lookups were three
/// quarters of laying a jagged outline (🔬a 12000-point lasso: 2.5 ms of
/// 10.4) and slowed as each slot grew to hold a span (board
/// `a-selection-mask-is-built-on-the-cpu-at-every-move`).
final class _EdgeTable {
  _EdgeTable._(this.length, this._lineStarts, this._xs, this._ways, this._at);

  factory _EdgeTable.of(
    _LaidEdges laid, {
    required int width,
    required int lines,
  }) {
    final length = laid.length;
    final (byColumn, _) = _sortedBy(laid.xs, length, width + 1, null);
    final (sorted, lineStarts) = _sortedBy(laid.ys, length, lines, byColumn);
    final xs = Int32List(length);
    final ways = Int32List(length);
    final at = Int32List(length);
    for (var place = 0; place < length; place += 1) {
      final edge = sorted[place];
      xs[place] = laid.xs[edge];
      ways[place] = laid.ways[edge];
      at[edge] = place;
    }
    return _EdgeTable._(length, lineStarts, xs, ways, at);
  }

  /// How many edges were laid.
  final int length;

  /// Where each line's places begin, and a line past the last ends them.
  final Int32List _lineStarts;

  /// Per place: the column its edge starts at, and its way and span
  /// ([_LaidEdges.ways]) — -1 once taken.
  final Int32List _xs;
  final Int32List _ways;

  /// Per laid edge, its place.
  final Int32List _at;

  /// [edge]'s place, when it is the first laid from its vertex on [line];
  /// -1 when one was laid from there before it.
  int placeFirstLaidBy(int edge, int line) {
    final place = _at[edge];
    return place == _lineStarts[line] || _xs[place - 1] != _xs[place]
        ? place
        : -1;
  }

  /// Whether an edge from the vertex whose first place is [place], on
  /// [line], is still untaken.
  bool hasAt(int place, int line) =>
      _ways[place] >= 0 || _paired(place, line) && _ways[place + 1] >= 0;

  /// Takes the last untaken edge laid from vertex ([x], [line]) — its way
  /// and span ([_LaidEdges.ways]) — or -1 when none is left.
  int take(int x, int line) {
    final place = _placeOf(x, line);
    if (place < 0) {
      return -1;
    }
    return _paired(place, line) && _ways[place + 1] >= 0
        ? _taken(place + 1)
        : _taken(place);
  }

  int _taken(int place) {
    final way = _ways[place];
    _ways[place] = -1;
    return way;
  }

  /// Whether the vertex whose first place is [place] has a second edge.
  bool _paired(int place, int line) =>
      place + 1 < _lineStarts[line + 1] && _xs[place + 1] == _xs[place];

  /// The first place of vertex ([x], [line]), or -1 when no edge starts
  /// there.
  int _placeOf(int x, int line) {
    final end = _lineStarts[line + 1];
    var low = _lineStarts[line];
    var high = end;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_xs[middle] < x) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low < end && _xs[low] == x ? low : -1;
  }
}

/// [order] — laid edges, or every one in the order laid when null — sorted
/// stably by their [keys], each below [range]: the edges sorted, and where
/// each key's begin, a key past the last ending them.
(Int32List, Int32List) _sortedBy(
  Int32List keys,
  int length,
  int range,
  Int32List? order,
) {
  final starts = Int32List(range + 1);
  for (var edge = 0; edge < length; edge += 1) {
    starts[keys[edge] + 1] += 1;
  }
  for (var key = 0; key < range; key += 1) {
    starts[key + 1] += starts[key];
  }
  final next = Int32List.fromList(starts);
  final sorted = Int32List(length);
  for (var place = 0; place < length; place += 1) {
    final edge = order == null ? place : order[place];
    final key = keys[edge];
    sorted[next[key]] = edge;
    next[key] += 1;
  }
  return (sorted, starts);
}

/// One closed contour of [edges], walked from vertex ([startX], [startY])
/// and consumed as it goes — [at] is a vertex's canvas point.
List<CanvasPoint> _walkContour(
  _EdgeTable edges,
  int startX,
  int startY,
  CanvasPoint Function(int x, int y) at,
) {
  var x = startX;
  var y = startY;
  final contour = <CanvasPoint>[at(x, y)];
  // ⚠️STRAIGHT RUNS COLLAPSE. The walk steps a side a pixel's edge at a
  // time, so a plain rectangle would arrive with thousand-point sides and
  // be rebuilt into a `Path` on every animation tick. Merging while
  // walking makes an axis-aligned outline four points again; a true
  // staircase (a rotated or lassoed edge) keeps its steps, because
  // those steps ARE the answer.
  // A run's end is made a point once, where the walk turns off it.
  // ↩️It was made again at every step along the run: an inverse's outline
  // was some twenty thousand points made for eight kept (L2e, board
  // `a-selection-mask-is-built-on-the-cpu-at-every-move`).
  var lastWay = -1;
  // Whether the contour's last point is behind (x, y) on a straight run.
  var behind = false;
  // ⚠️Bounded by the edge count rather than trusted to close: a
  // malformed walk must end, not hang the paint thread.
  var guard = edges.length + 8;
  while (guard-- > 0) {
    final taken = edges.take(x, y);
    if (taken < 0) {
      break;
    }
    final way = taken & 3;
    final nextX = x + _acrossBy[way] * (taken >> 2);
    final nextY = y + _downBy[way] * (taken >> 2);
    if (nextX == startX && nextY == startY) {
      break;
    }
    if (way == lastWay) {
      behind = true;
    } else {
      if (behind) {
        contour[contour.length - 1] = at(x, y);
        behind = false;
      }
      contour.add(at(nextX, nextY));
    }
    lastWay = way;
    x = nextX;
    y = nextY;
  }
  if (behind) {
    contour[contour.length - 1] = at(x, y);
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

  /// The first column past [x] that [covers] answers otherwise for than it
  /// just did for [x] — asked only right after it.
  int changesAfter(int x) {
    if (_at + 1 >= _runs.length) {
      return _never;
    }
    return _runs[_at] <= x ? _runs[_at + 1] : _runs[_at];
  }

  /// Past every column: no run is left to change [covers]' answer.
  static const _never = 0x7FFFFFFF;
}

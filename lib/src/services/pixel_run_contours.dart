import 'dart:math' as math;
import 'dart:typed_data';

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
  // Every vertex in the order its first edge was laid, walked from for as
  // long as it still has an edge — the very starts the walk always took,
  // in the same order. ↩️It used to ask the edge map for its first key
  // before each contour: a removed key kept its place in the map's order,
  // so every ask walked past every vertex already consumed — quadratic in
  // the outline (🔬I-160, a 4K range with 5000 small holes: 730 ms).
  for (final start in edges.starts) {
    while (edges.has(start)) {
      contours.add(_closedContour(edges, start, at));
    }
  }
  return contours;
}

/// The contour walked from [start] ([_walkContour]), its join merged.
List<CanvasPoint> _closedContour(
  _EdgeTable edges,
  int start,
  CanvasPoint Function(int vertex) at,
) {
  final contour = _walkContour(edges, start, at);
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
_EdgeTable _boundaryEdges(List<List<int>> rows, int width) {
  final edges = _EdgeTable(width + 1);
  void edge(int x, int y, int way, int span) =>
      edges.add(y * (width + 1) + x, way, span);

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
        if (!up) edge(x, y, _right, to - x);
        if (x == end - 1) edge(x + 1, y, _down, 1);
        if (!down) edge(x + 1, y + 1, _left, 1);
        if (x == start) edge(x, y + 1, _up, 1);
        if (to - 1 > x) {
          if (to == end) edge(to, y, _down, 1);
          if (!down) edge(to, y + 1, _left, to - 1 - x);
        }
        x = to;
      }
    }
  }
  return edges;
}

/// The ways a boundary edge goes from the vertex it starts at.
const _right = 0;
const _down = 1;
const _left = 2;
const _up = 3;

/// The boundary's edges in one flat table: per vertex, the ways its edges
/// go as a stack — the last laid is the first taken, as the walk always
/// took them — and the vertices in the order their first edge was laid
/// ([starts]). A vertex of a pixel boundary has at most two edges out (two
/// pixels touching only at a corner), so both fit beside it in its slot.
///
/// ↩️A map of a list per vertex until I-160 walked a fill's range with it:
/// 🔬a 4K range with 20000 small holes spent 650–730 ms on the outline
/// (now 210–280; 5000 holes, 95–165 → 26–42), most of it on where the
/// lookups landed rather than on the lists. So one
/// read finds a vertex and its edges, and a slot is found from the vertex
/// in blocks of sixteen along a row: a contour, whose vertices sit a pixel
/// apart, keeps landing in the slots it just used, and a long straight
/// edge still spreads over the table rather than piling into one run of
/// slots (🔬the vertex itself as the slot: a plain 4K range took 20 ms
/// instead of 2).
final class _EdgeTable {
  _EdgeTable(int stride) : steps = [1, stride, -1, -stride];

  /// How far each way ([_right], [_down], [_left], [_up]) moves a vertex.
  final List<int> steps;

  /// How many edges were laid.
  int length = 0;

  /// Open addressing by vertex: per slot, the vertex (-1 for none), then
  /// its untaken edges — the count in bits 4 and up, the first edge's way
  /// in bits 0–1 and the second's in bits 2–3 — then each one's span, in
  /// vertices.
  Int32List _slots = Int32List(4 << 10)..fillRange(0, 4 << 10, -1);
  int _bits = 10;
  int _used = 0;

  /// The vertices in the order their first edge was laid.
  final List<int> starts = [];

  void add(int from, int way, int span) {
    var slot = _slotOf(from);
    if (_slots[slot] < 0) {
      if ((_used + 1) * 2 > 1 << _bits) {
        _grow();
        slot = _slotOf(from);
      }
      _slots[slot] = from;
      _slots[slot + 1] = 0;
      _used += 1;
      starts.add(from);
    }
    final held = _slots[slot + 1];
    final count = held >> 4;
    // Two out is a corner two pixels share; a third would mean two runs
    // that touch, which [pixelRunContours]' rows never hold.
    assert(count < 2, 'a third edge out of vertex $from');
    _slots[slot + 1] = (count + 1) << 4 | (held & 15) | way << (count * 2);
    _slots[slot + 2 + count] = span;
    length += 1;
  }

  /// Whether an edge from [vertex] is still untaken.
  bool has(int vertex) {
    final slot = _slotOf(vertex);
    return _slots[slot] >= 0 && _slots[slot + 1] >> 4 > 0;
  }

  /// Takes the last untaken edge laid from [vertex] — the way it goes in
  /// bits 0–1 and its span above them, or -1 when none is left.
  int take(int vertex) {
    final slot = _slotOf(vertex);
    if (_slots[slot] < 0) {
      return -1;
    }
    final held = _slots[slot + 1];
    final count = held >> 4;
    if (count == 0) {
      return -1;
    }
    _slots[slot + 1] = (count - 1) << 4 | (held & 15);
    return _slots[slot + 1 + count] << 2 | held >> ((count - 1) * 2) & 3;
  }

  /// [vertex]'s slot (its index in [_slots]), or the empty slot it would
  /// take: its block of sixteen scattered by a multiplicative hash, its
  /// place in the block kept.
  int _slotOf(int vertex) {
    final mask = (1 << _bits) - 1;
    final block = ((vertex >> 4) * 0x9E3779B1 & 0xFFFFFFFF) >> (32 - _bits);
    var slot = (block ^ (vertex & 15)) & mask;
    while (true) {
      final there = _slots[slot * 4];
      if (there < 0 || there == vertex) {
        return slot * 4;
      }
      slot = (slot + 1) & mask;
    }
  }

  void _grow() {
    final slots = _slots;
    _bits += 1;
    _slots = Int32List(4 << _bits)..fillRange(0, 4 << _bits, -1);
    for (var slot = 0; slot < slots.length; slot += 4) {
      final vertex = slots[slot];
      if (vertex >= 0) {
        final into = _slotOf(vertex);
        _slots.setRange(into, into + 4, slots, slot);
      }
    }
  }
}

/// One closed contour of [edges], walked from [start] and consumed as it
/// goes — [at] is a vertex's canvas point.
List<CanvasPoint> _walkContour(
  _EdgeTable edges,
  int start,
  CanvasPoint Function(int vertex) at,
) {
  var current = start;
  final contour = <CanvasPoint>[at(start)];
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
  // Whether the contour's last point is behind [current] on a straight run.
  var behind = false;
  // ⚠️Bounded by the edge count rather than trusted to close: a
  // malformed walk must end, not hang the paint thread.
  var guard = edges.length + 8;
  while (guard-- > 0) {
    final taken = edges.take(current);
    if (taken < 0) {
      break;
    }
    final way = taken & 3;
    final next = current + edges.steps[way] * (taken >> 2);
    if (next == start) {
      break;
    }
    if (way == lastWay) {
      behind = true;
    } else {
      if (behind) {
        contour[contour.length - 1] = at(current);
        behind = false;
      }
      contour.add(at(next));
    }
    lastWay = way;
    current = next;
  }
  if (behind) {
    contour[contour.length - 1] = at(current);
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

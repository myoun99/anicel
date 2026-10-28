import 'dart:math' as math;
import 'dart:typed_data';

import 'timeline_visible_range.dart';

/// One drawn row's place along the rail: its own [extent]; the [room] that
/// follows it, which is no row; and whether it [joinsNext] — draws as one
/// with the row after it, as a graph's lanes do.
typedef TimelineRowSlot = ({double extent, double room, bool joinsNext});

/// Where every drawn row sits along the rail — the ONE answer the rail, the
/// cells, the sheet, the cursor and every gesture that turns a pointer into
/// a row read.
///
/// 🚨I-89 ③ (2026-10-11): rows stopped being one height when a group's
/// graph opened in their place. The graph is as tall as its grip says, and
/// what it stands taller than its lanes is ROOM after a row, not a row: no
/// stop, nothing selected, nothing stood on — the walk the user's drawing
/// makes has none. ↩️Twenty-odd places counted `index × row height`, each
/// its own copy of the law, so the first row of another height would have
/// put the rail and the cells in two places.
///
/// Rows that join are one UNIT: drawn as one on the frame side, never cut
/// by a window ([window]).
class TimelineRowEdges {
  /// The rows' slots, in draw order, and the most a graph stands among
  /// them ([graphMost]).
  factory TimelineRowEdges(
    List<TimelineRowSlot> slots, {
    double graphMost = double.infinity,
  }) {
    final count = slots.length;
    final starts = Float64List(count + 1);
    final extents = Float64List(count);
    final unitFirst = Int32List(count);
    final unitLast = Int32List(count);
    var at = 0.0;
    for (var index = 0; index < count; index += 1) {
      final slot = slots[index];
      starts[index] = at;
      extents[index] = slot.extent;
      at += slot.extent + slot.room;
      unitFirst[index] = index > 0 && slots[index - 1].joinsNext
          ? unitFirst[index - 1]
          : index;
    }
    starts[count] = at;
    for (var index = count - 1; index >= 0; index -= 1) {
      unitLast[index] = index < count - 1 && slots[index].joinsNext
          ? unitLast[index + 1]
          : index;
    }
    return TimelineRowEdges._(
      starts,
      extents,
      unitFirst,
      unitLast,
      graphMost,
    );
  }

  /// [count] rows of one [extent] each, with no room between them.
  factory TimelineRowEdges.uniform(int count, double extent) =>
      TimelineRowEdges([
        for (var index = 0; index < count; index += 1)
          (extent: extent, room: 0, joinsNext: false),
      ]);

  TimelineRowEdges._(
    this._starts,
    this._extents,
    this._unitFirst,
    this._unitLast,
    this.graphMost,
  );

  /// Where each row begins; one past the last is where the rows end.
  final Float64List _starts;
  final Float64List _extents;
  final Int32List _unitFirst;
  final Int32List _unitLast;

  /// The most a header graph stands among these rows — what the view they
  /// were laid along lets one (`laneGraphMostExtent`, I-89 ③D): what the
  /// enlarged graph stands, what caps every other, and the most a grip
  /// pulls one to, carried with the rows so the three cannot part.
  /// Unbounded for rows laid along no view.
  final double graphMost;

  int get count => _extents.length;

  /// How far the rows reach, the room after the last one included.
  double get total => _starts[count];

  /// Where row [index] begins. [count] is where the rows end.
  double startOf(int index) => _starts[index.clamp(0, count)];

  /// Row [index]'s own extent — its room left out.
  double extentOf(int index) => _extents[index];

  /// Where row [index] ends — its room left out.
  double endOf(int index) => _starts[index] + _extents[index];

  /// The room after row [index].
  double roomOf(int index) => _starts[index + 1] - endOf(index);

  /// The first and the last row of the unit row [index] draws in.
  ({int first, int last}) unitOf(int index) =>
      (first: _unitFirst[index], last: _unitLast[index]);

  /// Where the unit row [index] draws in begins, and how far it reaches —
  /// the room after its last row included.
  ({double start, double extent}) unitSpanOf(int index) {
    final start = _starts[_unitFirst[index]];
    return (start: start, extent: _starts[_unitLast[index] + 1] - start);
  }

  /// The units the rows from [from] up to [to] draw in, in order, each as
  /// its first and last row — a unit [to] cuts ends before it.
  Iterable<({int first, int last})> unitsIn(int from, int to) sync* {
    var index = from;
    while (index < to) {
      final last = math.min(_unitLast[index], to - 1);
      yield (first: index, last: last);
      index = last + 1;
    }
  }

  /// The row whose slot — its own extent and the room after it — holds
  /// [offset], clamped to the rows.
  int slotAt(double offset) => count == 0
      ? 0
      : math.min(math.max(_lastStartingAtOrBefore(offset), 0), count - 1);

  /// The row whose own extent holds [offset]; null where [offset] falls in
  /// a row's room, or past the rows.
  int? rowAt(double offset) {
    if (count == 0 || offset < 0) {
      return null;
    }
    final index = _lastStartingAtOrBefore(offset);
    return index < count && offset < endOf(index) ? index : null;
  }

  /// The row a pointer [crossOffset] from the start of row [anchor] stands
  /// over, clamped to the rows — and, from inside a row's room, the row on
  /// the anchor's side of it: a drag that ends in room reaches as far as it
  /// legibly can rather than collapsing to nothing, as one that ends on the
  /// storyboard's Audio strip does (`rowIndexForCrossOffset`, walked back
  /// over the slots nobody stands on).
  int rowFrom(int anchor, double crossOffset) {
    if (count == 0) {
      return 0;
    }
    final from = anchor.clamp(0, count - 1);
    final at = _starts[from] + crossOffset;
    final row = slotAt(at);
    if (at < endOf(row)) {
      return row;
    }
    return row >= from || row == count - 1 ? row : row + 1;
  }

  /// Where a pointer [crossOffset] from the start of row [anchor] stands,
  /// in rows from that start: fractional inside a row, and at the next
  /// row's edge anywhere in the room after one — room is no row, so across
  /// it the pointer stands at one gap. Past either end it carries on at the
  /// end row's extent, as a count in one row height did.
  double rowsAt(int anchor, double crossOffset) {
    if (count == 0) {
      return 0;
    }
    final from = anchor.clamp(0, count - 1);
    final at = _starts[from] + crossOffset;
    final double position;
    if (at < 0) {
      position = at / _pitchOf(0);
    } else if (at >= total) {
      position = count + (at - total) / _pitchOf(count - 1);
    } else {
      final row = slotAt(at);
      position = at < endOf(row)
          ? row + (at - _starts[row]) / _pitchOf(row)
          : row + 1.0;
    }
    return position - from;
  }

  /// Row [index]'s extent as a divisor — a row of none counts as one pixel.
  double _pitchOf(int index) =>
      _extents[index] > 0 ? _extents[index] : 1.0;

  /// The rows whose own extent meets the stretch between [from] and [to],
  /// ends included, as the first and last index — null when it meets none.
  /// The stretch's own order does not matter.
  ({int first, int last})? rowsIn(double from, double to) {
    if (count == 0) {
      return null;
    }
    final lo = math.min(from, to);
    final hi = math.max(from, to);
    var first = 0;
    var past = count;
    while (first < past) {
      final mid = (first + past) >> 1;
      if (endOf(mid) > lo) {
        past = mid;
      } else {
        first = mid + 1;
      }
    }
    final last = math.min(_lastStartingAtOrBefore(hi), count - 1);
    return first <= last ? (first: first, last: last) : null;
  }

  /// The rows a viewport of [viewportExtent] at [scrollOffset] shows, grown
  /// to whole units — for rows of one extent, exactly the uniform division
  /// ([calculateVisibleIndexRange]) with no rows past the viewport.
  ///
  /// 🪶No rows are built past the viewport (card frame-panels-build-in-one-
  /// frame, 2026-10-28): two more on each side were made again every time a
  /// tab opened — 412 of the timeline tab's 2,787 elements — for nobody to
  /// see. A row that scrolls in is built in the frame it arrives, as the
  /// rows past those two always were; a row a drag holds is kept apart
  /// (A5). ↩️The two came with the first range calculator (4524ab0c1,
  /// 2026-06-15) as its default and were carried here with it (d52e0df72);
  /// no decision is recorded for them.
  TimelineVisibleRange window({
    required double scrollOffset,
    required double viewportExtent,
  }) {
    if (count == 0) {
      return const TimelineVisibleRange(startIndex: 0, endIndexExclusive: 0);
    }
    final from = math.max(0.0, scrollOffset);
    final to = from + math.max(0.0, viewportExtent);
    var start = _lastStartingAtOrBefore(from).clamp(0, count);
    var end = _startingBefore(to).clamp(start, count);
    if (start < count) {
      start = _unitFirst[start];
    }
    if (end > 0) {
      end = math.max(end, _unitLast[end - 1] + 1);
    }
    return TimelineVisibleRange(startIndex: start, endIndexExclusive: end);
  }

  /// The last edge at or before [offset], the end of the rows counted as
  /// one: -1 before the first row, [count] at or past the end.
  int _lastStartingAtOrBefore(double offset) {
    var lo = -1;
    var hi = count;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_starts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// How many rows begin before [offset].
  int _startingBefore(double offset) {
    var lo = 0;
    var hi = count;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_starts[mid] < offset) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}

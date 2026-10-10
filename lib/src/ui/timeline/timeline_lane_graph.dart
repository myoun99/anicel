import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../models/key_mark.dart' show KeyMark;
import '../../models/timeline_row_address.dart';
import '../dashed_path.dart' show DashPattern, dashesAlong;
import 'axis_turn.dart' show acrossBox, extentAcross, offsetAlong;
import 'key_mark_glyph.dart' show paintKeyMark;
import 'lane_graph.dart';
import 'lane_graph_seats.dart'
    show LaneGraphLine, laneGraphDrawnLanes, laneGraphGuests;
import 'layer_label_controls.dart' show layerMarkColor;
import 'property_lane_model.dart';
import 'timeline_cells_row_facts.dart' show TimelineCellsRowGrid;
import 'timeline_frame_geometry.dart';
import 'timeline_frame_window.dart'
    show frameWindowContains, visibleFrameWindowFor;
import 'timeline_row_edges.dart';

/// Rows as a grid lays them: [rows] are its rows from [first] on, and
/// [edges] where every one of its rows sits.
typedef TimelineLaidRows = ({
  List<TimelineDisplayRow> rows,
  int first,
  TimelineRowEdges edges,
});

/// What [grid] lays on the frame side for [laid]: each row's own [cells],
/// and an open graph's lanes as ONE [TimelineLaneGraph] across their whole
/// unit (I-89 ③).
List<Widget> timelineFrameSide(
  TimelineLaidRows laid,
  TimelineCellsRowGrid grid, {
  required Widget Function(TimelineDisplayRow row) cells,
}) {
  final (:rows, :first, :edges) = laid;
  return [
    for (final unit in edges.unitsIn(first, first + rows.length))
      if (rows[unit.first - first].graph case final seat?)
        TimelineLaneGraph(
          key: ValueKey<String>(
            '${grid.keyPrefix}-lane-graph-${seat.groupKey}',
          ),
          seat: seat,
          lanes: rows.sublist(unit.first - first, unit.last - first + 1),
          grid: grid,
          crossExtent: edges.unitSpanOf(unit.first).extent,
        )
      else ...[
        cells(rows[unit.first - first]),
        if (edges.roomOf(unit.last) > 0)
          acrossBox(grid.axis, edges.roomOf(unit.last)),
      ],
  ];
}

/// An open graph on the frame side: ONE picture over its group's [lanes]
/// and the room after them, where their rows of cells would be (I-89 ③) —
/// the same widget on the timeline and, turned on its side, the sheet.
///
/// It draws the lanes its seat names as its own ([laneGraphDrawnLanes]),
/// read off where the rail stands, and every pin of another group's as a
/// guest ([laneGraphGuests]). Along the frames it is a row of cells: laid
/// out by the grid's live geometry ([TimelineFrameAxisBox]) and drawing
/// only its window, so a scroll or a zoom step repaints it and rebuilds
/// nothing.
class TimelineLaneGraph extends StatelessWidget {
  const TimelineLaneGraph({
    super.key,
    required this.seat,
    required this.lanes,
    required this.grid,
    required this.crossExtent,
  });

  final TimelineGraphSeat seat;

  /// The group's lanes as the rail draws them, in its order.
  final List<TimelineDisplayRow> lanes;

  /// The grid it is drawn in, read as its rows of cells read it.
  final TimelineCellsRowGrid grid;

  /// How far it reaches across the frames — its lanes and the room after
  /// them.
  final double crossExtent;

  @override
  Widget build(BuildContext context) {
    final standing = grid.hooks.currentRowHooks?.currentRow;
    return TimelineFrameAxisBox(
      geometry: grid.geometry,
      crossAxisExtent: crossExtent,
      axis: grid.axis,
      child: RepaintBoundary(
        child: standing == null
            ? _picture(null)
            : ValueListenableBuilder<TimelineRowAddress?>(
                valueListenable: standing,
                builder: (context, row, _) => _picture(row),
              ),
      ),
    );
  }

  Widget _picture(TimelineRowAddress? standing) {
    final drawn = laneGraphDrawnLanes(seat, standing);
    final hooks = grid.hooks;
    final lineOf = hooks.laneGraphLineOf;
    return CustomPaint(
      painter: TimelineLaneGraphPainter(
        own: [
          for (final row in lanes)
            if (drawn.contains(row.lane!.laneId))
              (layer: row.layer, lane: row.lane!),
        ],
        guests: [
          if (lineOf != null)
            for (final key in laneGraphGuests(seat, hooks.laneGraphs.pinned))
              ?lineOf(key),
        ],
        grid: grid,
      ),
    );
  }
}

/// The values a line is fitted to across its graph.
typedef LaneGraphRange = ({double low, double high});

/// What a graph keeps clear at either edge across it, in pixels (the
/// mock's, 5판).
const double _laneGraphPadding = 16;

/// How much of a line's span it is given spare beyond its lowest and its
/// highest value, on each side (the mock's, 5판).
const double _laneGraphSpare = 0.12;

/// A line's width, and a guest's dashes (the mock's, 5판).
const double _laneGraphStroke = 2;
const DashPattern _laneGraphGuestDashes = DashPattern(on: 6, off: 4);

/// A key's mark in a graph — larger than a lane's, the mock's (5판).
const double _laneGraphKeySize = 11;

/// How finely a line is read between two keys for its range, and between
/// two frames for its picture: no finer than every two pixels, nor than an
/// eighth of a frame.
const int _laneGraphRangeSteps = 8;
const double _laneGraphSampleSpacing = 2;
const int _laneGraphFrameSteps = 8;

/// Where [time] — a frame, or a time between two — stands along a graph
/// laid by [frames]: in the middle of its frame's cell, where a lane marks
/// its key.
double laneGraphAlong(double time, TimelineFrameGeometry frames) {
  double middle(int frame) =>
      (frames.edgeAt(frame) + frames.edgeAt(frame + 1)) / 2;
  final frame = time.floor();
  final from = middle(frame);
  return from + (time - frame) * (middle(frame + 1) - from);
}

/// The values [curve]'s [part] is fitted to (I-89 ③, 「곡선마다 제 범위로
/// 맞춰 겹침」 — AE's normalised view): from its lowest to its highest
/// between its [keyed] frames, with [_laneGraphSpare] of that span beyond
/// either; a line that never moves is given one either way first.
///
/// Read between the keys as well as on them: an eased stretch can pass
/// beyond the keys it runs between.
LaneGraphRange laneGraphRange(LaneCurve curve, List<int> keyed, int part) {
  var low = double.infinity;
  var high = double.negativeInfinity;
  void take(double time) {
    final value = curve.at(time)[part];
    low = math.min(low, value);
    high = math.max(high, value);
  }

  for (var index = 0; index < keyed.length; index += 1) {
    take(keyed[index].toDouble());
    if (index + 1 == keyed.length) {
      break;
    }
    final from = keyed[index];
    final to = keyed[index + 1];
    for (var step = 1; step < _laneGraphRangeSteps; step += 1) {
      take(from + (to - from) * step / _laneGraphRangeSteps);
    }
  }
  if (high - low < 1e-6) {
    low -= 1;
    high += 1;
  }
  final spare = (high - low) * _laneGraphSpare;
  return (low: low - spare, high: high + spare);
}

/// Where [value] stands across a graph [extent] deep, fitted to [range]
/// inside its padding: higher up the timeline's graph, and — the sheet
/// being the timeline turned a quarter clockwise, as its key marks are —
/// further right across the sheet's.
double laneGraphAcross(
  double value,
  LaneGraphRange range,
  double extent,
  Axis axis,
) {
  final share = (value - range.low) / (range.high - range.low);
  final room = extent - 2 * _laneGraphPadding;
  return axis == Axis.horizontal
      ? extent - _laneGraphPadding - share * room
      : _laneGraphPadding + share * room;
}

/// The times a line is read at across [window], its frames [cell] long:
/// from its first frame's leading edge to its last's trailing edge — but
/// never before frame 0 — at most [_laneGraphFrameSteps] to a frame and no
/// closer than [_laneGraphSampleSpacing] pixels, every frame among them,
/// where the keys stand.
Iterable<double> laneGraphTimes(
  ({int startIndex, int endIndexExclusive}) window,
  double cell,
) sync* {
  final (:startIndex, :endIndexExclusive) = window;
  if (endIndexExclusive <= startIndex) {
    return;
  }
  final steps = (cell / _laneGraphSampleSpacing).ceil().clamp(
    1,
    _laneGraphFrameSteps,
  );
  final from = math.max(0.0, startIndex - 0.5);
  final to = endIndexExclusive - 0.5;
  yield from;
  for (var frame = startIndex - 1; frame < endIndexExclusive; frame += 1) {
    for (var step = 0; step < steps; step += 1) {
      final time = frame + step / steps;
      if (time > from && time < to) {
        yield time;
      }
    }
  }
  yield to;
}

/// One paint of a graph: the [frames] its grid lays, the [window] of them
/// it draws, the [times] it reads each line at, and how far across it
/// reaches.
typedef _LaneGraphPass = ({
  Canvas canvas,
  TimelineFrameGeometry frames,
  ({int startIndex, int endIndexExclusive}) window,
  List<double> times,
  double extent,
});

/// A key's mark, held back until every line is drawn.
typedef _LaneGraphMark = ({Offset at, KeyMark mark, Color color});

/// A header graph's picture (I-89 ③): each line of [own] solid and each of
/// [guests] dashed, every number it holds in its own colour and fitted to
/// its own range, and a mark on every key — over the frames [grid] lays,
/// only those its window shows, as its rows of cells draw them
/// ([visibleFrameWindowFor]).
class TimelineLaneGraphPainter extends CustomPainter {
  TimelineLaneGraphPainter({
    required this.own,
    required this.guests,
    required this.grid,
  }) : super(repaint: Listenable.merge([grid.geometry, ?grid.windowBucket]));

  final List<LaneGraphLine> own;
  final List<LaneGraphLine> guests;
  final TimelineCellsRowGrid grid;

  Axis get axis => grid.axis;

  /// The frames [paint] draws — the probe surface for the window's tests,
  /// as the cells painter's is.
  ({int startIndex, int endIndexExclusive}) visibleFrameWindow() {
    final frames = grid.geometry.value;
    return visibleFrameWindowFor(
      bucket: grid.windowBucket,
      viewportMainExtent: grid.viewportMainExtent,
      cellExtent: frames.frameCellExtent,
      frameStartIndex: frames.frameStartIndex,
      frameEndIndexExclusive: frames.frameEndIndexExclusive,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final frames = grid.geometry.value;
    final window = visibleFrameWindow();
    final pass = (
      canvas: canvas,
      frames: frames,
      window: window,
      times: laneGraphTimes(window, frames.frameCellExtent).toList(),
      extent: extentAcross(axis, size),
    );
    // The marks go on last, over every line.
    final marks = [
      for (final line in own) ..._drawLine(pass, line, dashed: false),
      for (final line in guests) ..._drawLine(pass, line, dashed: true),
    ];
    for (final (:at, :mark, :color) in marks) {
      paintKeyMark(
        canvas,
        mark,
        center: at,
        size: _laneGraphKeySize,
        standing: axis == Axis.vertical,
        color: color,
      );
    }
  }

  /// Draws every number [line] holds through [pass], in dashes for a
  /// guest, and gives back the marks its keys in the window take.
  List<_LaneGraphMark> _drawLine(
    _LaneGraphPass pass,
    LaneGraphLine line, {
    required bool dashed,
  }) {
    final curve = line.lane.curve;
    final keyed = [...line.lane.keyedFrames]..sort();
    if (curve == null || keyed.isEmpty) {
      return const [];
    }
    final (:canvas, :frames, :window, :times, :extent) = pass;
    final marks = <_LaneGraphMark>[];
    for (var part = 0; part < curve.parts.length; part += 1) {
      final range = laneGraphRange(curve, keyed, part);
      Offset at(double time) => offsetAlong(
        axis,
        along: laneGraphAlong(time, frames),
        across: laneGraphAcross(curve.at(time)[part], range, extent, axis),
      );
      _stroke(
        canvas,
        Path()..addPolygon([for (final time in times) at(time)], false),
        curve.parts[part],
        dashed: dashed,
      );
      marks.addAll([
        for (final frame in keyed)
          if (frameWindowContains(window, frame))
            (
              at: at(frame.toDouble()),
              mark: line.lane.keyMarkAt(frame),
              color: layerMarkColor(line.layer.mark),
            ),
      ]);
    }
    return marks;
  }

  /// Strokes [path] in [color] — in dashes for a guest's.
  void _stroke(
    Canvas canvas,
    Path path,
    Color color, {
    required bool dashed,
  }) {
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _laneGraphStroke
      ..color = color;
    for (final piece
        in dashed ? dashesAlong(path, _laneGraphGuestDashes) : [path]) {
      canvas.drawPath(piece, ink);
    }
  }

  @override
  bool shouldRepaint(TimelineLaneGraphPainter oldDelegate) =>
      oldDelegate.own != own ||
      oldDelegate.guests != guests ||
      oldDelegate.grid != grid;
}

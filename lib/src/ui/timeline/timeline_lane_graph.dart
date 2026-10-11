import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../models/key_mark.dart' show KeyMark;
import '../../models/timeline_row_address.dart';
import '../dashed_path.dart' show DashPattern, dashesAlong;
import '../layout/device_grid_scroll_controller.dart' show ScrollStill;
import '../text/app_strings.dart' show AppText;
import '../theme/app_theme.dart' show AppColors, AppShapes;
import '../widgets/dock_edge_splitter.dart' show DockEdgeSplitter;
import '../widgets/pill_strip.dart' show PillItem, PillStrip;
import 'axis_turn.dart'
    show acrossBox, extentAcross, extentAlong, offsetAlong;
import 'key_mark_glyph.dart' show paintKeyMark;
import 'lane_graph.dart';
import 'lane_graph_seats.dart'
    show LaneGraphLine, laneGraphDrawnLanes, laneGraphGuests;
import 'layer_label_controls.dart' show layerMarkColor;
import 'property_lane_model.dart';
import 'timeline_cells_row_facts.dart' show TimelineCellsRowGrid;
import 'timeline_drag_preview.dart'
    show TimelineDragPreview, timelineDragPreviewLayerFor;
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
          lanesExtent:
              edges.unitSpanOf(unit.first).extent - edges.roomOf(unit.last),
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
/// guest ([laneGraphGuests]), named in the view's far corner
/// ([LaneGraphGuestTags]) — its tools in the near one ([LaneGraphTools]).
/// Along the frames it is a row of cells: laid out by the grid's live
/// geometry ([TimelineFrameAxisBox]) and drawing only its window, so a
/// scroll or a zoom step repaints it and rebuilds nothing.
class TimelineLaneGraph extends StatelessWidget {
  const TimelineLaneGraph({
    super.key,
    required this.seat,
    required this.lanes,
    required this.grid,
    required this.crossExtent,
    required this.lanesExtent,
  });

  final TimelineGraphSeat seat;

  /// The group's lanes as the rail draws them, in its order.
  final List<TimelineDisplayRow> lanes;

  /// The grid it is drawn in, read as its rows of cells read it.
  final TimelineCellsRowGrid grid;

  /// How far it reaches across the frames — its lanes and the room after
  /// them.
  final double crossExtent;

  /// How far its lanes alone reach across the frames: the least its grip
  /// makes it.
  final double lanesExtent;

  @override
  Widget build(BuildContext context) {
    final guests = _guests();
    final standing = grid.hooks.currentRowHooks?.currentRow;
    final preview = grid.hooks.dragPreview;
    final verbs = grid.hooks.laneGraphVerbs;
    return Stack(
      children: [
        TimelineFrameAxisBox(
          geometry: grid.geometry,
          crossAxisExtent: crossExtent,
          axis: grid.axis,
          child: RepaintBoundary(
            child: ListenableBuilder(
              listenable: Listenable.merge([standing, preview]),
              builder: (context, _) => _picture(
                standing?.value,
                preview?.value,
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: _standingInTheView(
            CustomMultiChildLayout(
              delegate: _LaneGraphCorners(grid.axis, grid.viewportMainExtent),
              children: [
                LayoutId(
                  id: _LaneGraphCorner.tools,
                  child: LaneGraphTools(
                    keyPrefix: grid.keyPrefix,
                    groupKey: seat.groupKey,
                    mode: seat.graph.mode,
                    onPlot: verbs == null
                        ? null
                        : (mode) => verbs.plot(seat.groupKey, mode),
                  ),
                ),
                if (guests.isNotEmpty)
                  LayoutId(
                    id: _LaneGraphCorner.guests,
                    child: LaneGraphGuestTags(
                      key: ValueKey<String>(
                        '${grid.keyPrefix}-lane-graph-guests-${seat.groupKey}',
                      ),
                      guests: guests,
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Its cross end: the timeline's bottom, the sheet's right.
        Positioned(
          left: grid.axis == Axis.horizontal ? 0 : null,
          top: grid.axis == Axis.horizontal ? null : 0,
          right: 0,
          bottom: 0,
          child: LaneGraphGrip(
            key: ValueKey<String>(
              '${grid.keyPrefix}-lane-graph-grip-${seat.groupKey}',
            ),
            axis: grid.axis,
            extent: crossExtent,
            least: lanesExtent,
            onResize: (extent) => verbs?.resize(seat.groupKey, extent),
          ),
        ),
      ],
    );
  }

  /// [corners] standing still in the view while the frames scroll under
  /// them ([ScrollStill]) — at the frames' start where the host scrolls
  /// none. Forward along the frames, as the scroll body they stand in
  /// lands (`TimelineScrollViewport`).
  Widget _standingInTheView(Widget corners) {
    final controller = grid.frameAxisController;
    return controller == null
        ? corners
        : ScrollStill(
            controller: controller,
            axisDirection: grid.axis == Axis.horizontal
                ? AxisDirection.right
                : AxisDirection.down,
            child: corners,
          );
  }

  /// Every pin of another group's, as the host finds it.
  List<LaneGraphLine> _guests() {
    final hooks = grid.hooks;
    final lineOf = hooks.laneGraphLineOf;
    return [
      if (lineOf != null)
        for (final key in laneGraphGuests(seat, hooks.laneGraphs.pinned))
          ?lineOf(key),
    ];
  }

  /// The picture as it stands with [standing] stood on and [preview] in
  /// flight: each of its own lanes as its row of cells would show it
  /// ([previewedLaneRow]), and every guest as the host reads it then.
  Widget _picture(TimelineRowAddress? standing, TimelineDragPreview? preview) {
    final drawn = laneGraphDrawnLanes(seat, standing);
    final lanesForLayer = grid.hooks.lanesForLayer;
    return CustomPaint(
      painter: TimelineLaneGraphPainter(
        own: [
          for (final row in lanes)
            if (drawn.contains(row.lane!.laneId))
              if (timelineDragPreviewLayerFor(preview, row.layer.id)
                  case final layer?)
                (
                  layer: layer,
                  lane: previewedLaneRow(
                    row: row,
                    previewLayer: layer,
                    lanesForLayer: (layer) =>
                        lanesForLayer?.call(layer) ?? const [],
                  ),
                )
              else
                (layer: row.layer, lane: row.lane!),
        ],
        guests: _guests(),
        grid: grid,
        mode: seat.graph.mode,
      ),
    );
  }
}

/// A graph's GRIP (I-89 ③, the mock's 5판): its cross end — the
/// timeline's bottom edge, the sheet's right — pulled to make it taller or
/// shorter, never shorter than its lanes. The app's one splitter
/// ([DockEdgeSplitter]): what it cannot use of the travel is the drag's
/// to pay back, and a pull that reaches the view's edge pans it.
class LaneGraphGrip extends StatefulWidget {
  const LaneGraphGrip({
    super.key,
    required this.axis,
    required this.extent,
    required this.least,
    required this.onResize,
  });

  /// The grid's frame axis: the graph stands across it.
  final Axis axis;

  /// How far the graph reaches across the frames now, and the least its
  /// grip makes it.
  final double extent;
  final double least;

  /// The extent a pull has reached.
  final ValueChanged<double> onResize;

  @override
  State<LaneGraphGrip> createState() => _LaneGraphGripState();
}

class _LaneGraphGripState extends State<LaneGraphGrip> {
  /// Where the pull has taken the graph — the drag's own, so a move that
  /// comes before the last one's rebuild goes on from where it reached.
  double _reached = 0;

  double _pull(double delta) {
    final next = math.max(widget.least, _reached + delta);
    final used = next - _reached;
    _reached = next;
    if (used != 0) {
      widget.onResize(next);
    }
    return used;
  }

  // The timeline's graph and the rows after it are stacked; the sheet's
  // stand side by side — the splitter's axis is the frames'.
  @override
  Widget build(BuildContext context) => DockEdgeSplitter(
    axis: widget.axis,
    edgePans: true,
    onDragStart: () => _reached = widget.extent,
    onDragDelta: _pull,
  );
}

/// What a graph's tools keep clear of the view's start along the frames
/// and of the graph's edge across them, and what their well keeps around
/// the pills (the mock's, 5판).
const double _graphToolsInset = 6;
const double _graphToolsPadding = 2;

/// A graph's own tools, at the view's start (I-89 ③, the mock's 5판): what
/// it plots — its values, or how fast they change.
class LaneGraphTools extends StatelessWidget {
  const LaneGraphTools({
    super.key,
    required this.keyPrefix,
    required this.groupKey,
    required this.mode,
    required this.onPlot,
  });

  /// The grid's key prefix and the graph's group, which its pills' keys
  /// are made of.
  final String keyPrefix;
  final String groupKey;

  final LaneGraphMode mode;

  /// Null where the host hands the graph no verbs: the pills keep their
  /// place and take no press.
  final ValueChanged<LaneGraphMode>? onPlot;

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    final onPlot = this.onPlot;
    PillItem pill(LaneGraphMode plotted, String label) => PillItem(
      keyValue: '$keyPrefix-lane-graph-plot-${plotted.name}-$groupKey',
      label: label,
      selected: mode == plotted,
      onTap: onPlot == null ? null : () => onPlot(plotted),
    );
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: AppColors.surface,
        shape: AppShapes.container(AppShapes.wellRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(_graphToolsPadding),
        child: PillStrip(
          items: [
            pill(LaneGraphMode.value, strings.laneGraphValue),
            pill(LaneGraphMode.speed, strings.laneGraphSpeed),
          ],
        ),
      ),
    );
  }
}

/// What the guest tags keep clear of the view's end along the frames, and
/// of the graph's edge across them (the mock's, 5판).
const double _guestTagsInsetAlong = 8;
const double _guestTagsInsetAcross = 6;

/// A guest tag's parts (the mock's, 5판): how long its dash runs, the gap
/// between its dash, name and pin, the pin's size, and what their well
/// keeps clear beside them and above and below.
const double _guestDashLength = 14;
const double _guestTagGap = 6;
const double _guestPinSize = 16;
const double _guestTagsSidePadding = 8;
const double _guestTagsTopPadding = 4;

/// The narrowest the tags are laid out: a tag's dash and pin with none of
/// its name between them — narrower, and its row overflows.
const double _guestTagsLeastWidth =
    2 * _guestTagsSidePadding +
    _guestDashLength +
    2 * _guestTagGap +
    _guestPinSize;

/// What stands in a graph's view over its picture.
enum _LaneGraphCorner { tools, guests }

/// Lays a graph's TOOLS at the frames' start of the VIEW and its GUEST
/// TAGS at their far end — the mock's top left and top right of the
/// timeline's graph (5판), and on the sheet, the timeline turned a quarter
/// clockwise, its top right and bottom right — reckoned from the graph's
/// start, which [ScrollStill] keeps at the view's while it scrolls: so
/// nothing here moves with the scroll, and a scroll lays nothing out.
///
/// The tags never stand before the tools' end: no wider than the room the
/// view leaves them on the timeline — the graph's on the sheet — so a long
/// name ends in an ellipsis; never narrower than a tag's dash and pin.
class _LaneGraphCorners extends MultiChildLayoutDelegate {
  _LaneGraphCorners(this.axis, this.viewportExtent);

  final Axis axis;

  /// The view's extent along the frames; nothing where the host says
  /// nothing, and the view is all of them.
  final double viewportExtent;

  /// How far the view reaches along a graph [size] big.
  double _view(Size size) {
    final length = extentAlong(axis, size);
    return viewportExtent > 0 ? math.min(viewportExtent, length) : length;
  }

  /// Where a child [childSize] big stands across a graph [size] big: off
  /// the timeline's top, and — the top turned a quarter clockwise — off
  /// the sheet's right.
  double _across(Size size, Size childSize, double inset) =>
      axis == Axis.horizontal
      ? inset
      : extentAcross(axis, size) - extentAcross(axis, childSize) - inset;

  @override
  void performLayout(Size size) {
    final view = _view(size);
    final tools = layoutChild(
      _LaneGraphCorner.tools,
      BoxConstraints(
        maxWidth: math.max(
          0,
          (axis == Axis.horizontal ? view : size.width) - 2 * _graphToolsInset,
        ),
        maxHeight: size.height,
      ),
    );
    positionChild(
      _LaneGraphCorner.tools,
      offsetAlong(
        axis,
        along: _graphToolsInset,
        across: _across(size, tools, _graphToolsInset),
      ),
    );
    if (!hasChild(_LaneGraphCorner.guests)) {
      return;
    }
    final after =
        _graphToolsInset + extentAlong(axis, tools) + _guestTagsInsetAlong;
    final room = axis == Axis.horizontal
        ? view - _guestTagsInsetAlong - after
        : size.width - 2 * _guestTagsInsetAcross;
    final tags = layoutChild(
      _LaneGraphCorner.guests,
      BoxConstraints(maxWidth: math.max(_guestTagsLeastWidth, room)),
    );
    positionChild(
      _LaneGraphCorner.guests,
      offsetAlong(
        axis,
        along: math.max(
          after,
          view - _guestTagsInsetAlong - extentAlong(axis, tags),
        ),
        across: _across(size, tags, _guestTagsInsetAcross),
      ),
    );
  }

  @override
  bool shouldRelayout(_LaneGraphCorners oldDelegate) =>
      oldDelegate.axis != axis || oldDelegate.viewportExtent != viewportExtent;
}

/// A graph's guests named over its picture (I-89 ③, the mock's 5판): each
/// line's dash in its first colour, 「layer · lane」 and the pin that put
/// it there.
///
/// The same tags upright on the sheet: a graph is as wide there as its
/// lanes' columns together, room for the names to read across, so only
/// where they stand is turned ([_LaneGraphCorners]) — 2026-10-11.
class LaneGraphGuestTags extends StatelessWidget {
  const LaneGraphGuestTags({super.key, required this.guests});

  final List<LaneGraphLine> guests;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: DecoratedBox(
      decoration: ShapeDecoration(
        color: AppColors.surface,
        shape: AppShapes.container(
          AppShapes.wellRadius,
          side: const BorderSide(color: AppColors.hairline),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _guestTagsSidePadding,
          vertical: _guestTagsTopPadding,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 3,
          children: [for (final guest in guests) _tag(guest)],
        ),
      ),
    ),
  );

  Widget _tag(LaneGraphLine guest) {
    final (:layer, :lane) = guest;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: _guestTagGap,
      children: [
        CustomPaint(
          size: const Size(_guestDashLength, _laneGraphStroke),
          painter: _GuestDashPainter(
            lane.curve?.parts.first ?? AppColors.textDim,
          ),
        ),
        Flexible(
          child: Text(
            '${layer.name} · ${lane.label}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AppColors.text),
          ),
        ),
        const Icon(
          Icons.push_pin,
          size: _guestPinSize,
          color: AppColors.textDim,
        ),
      ],
    );
  }
}

/// A guest's line in its tag: its dashes in its colour.
class _GuestDashPainter extends CustomPainter {
  const _GuestDashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final middle = size.height / 2;
    _strokeLaneGraphLine(
      canvas,
      Path()
        ..moveTo(0, middle)
        ..lineTo(size.width, middle),
      color,
      dashed: true,
    );
  }

  @override
  bool shouldRepaint(_GuestDashPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Strokes [path], a graph's line, in [color] — in dashes for a guest's.
void _strokeLaneGraphLine(
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

/// How far ahead of a time its speed is read, in frames.
const double _laneGraphSpeedStep = 1 / 64;

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

/// The values each number of [curve] is fitted to (I-89 ③, 「곡선마다 제
/// 범위로 맞춰 겹침」 — AE's normalised view), in the order of its parts:
/// from its lowest to its highest between its [keyed] frames, with
/// [_laneGraphSpare] of that span beyond either; a number that never moves
/// is given one either way first.
///
/// Read between the keys as well as on them: an eased stretch can pass
/// beyond the keys it runs between. Each time is read once for all its
/// numbers — a point's two are one pose.
List<LaneGraphRange> laneGraphRanges(LaneCurve curve, List<int> keyed) {
  final parts = curve.parts.length;
  final low = List.filled(parts, double.infinity);
  final high = List.filled(parts, double.negativeInfinity);
  void take(double time) {
    final numbers = curve.at(time);
    for (var part = 0; part < parts; part += 1) {
      low[part] = math.min(low[part], numbers[part]);
      high[part] = math.max(high[part], numbers[part]);
    }
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
  return [
    for (var part = 0; part < parts; part += 1)
      _spared(low[part], high[part]),
  ];
}

/// [low] to [high] with [_laneGraphSpare] of the span beyond either — one
/// either way first, where they meet.
LaneGraphRange _spared(double low, double high) {
  final (from, to) = high - low < 1e-6 ? (low - 1, high + 1) : (low, high);
  final spare = (to - from) * _laneGraphSpare;
  return (low: from - spare, high: to + spare);
}

/// How fast each number of [curve] changes at [time] — per frame, as AE's
/// speed graph plots it (I-89 ③ 속도) — read inside the stretch between
/// its keys on [from] and [to]: a step ahead, and never on [to] itself,
/// where a hold jumps.
List<double> laneGraphSpeedsAt(
  LaneCurve curve,
  double time, {
  required int from,
  required int to,
}) {
  final at = time.clamp(from.toDouble(), to - 2 * _laneGraphSpeedStep);
  final before = curve.at(at);
  final after = curve.at(at + _laneGraphSpeedStep);
  return [
    for (var part = 0; part < before.length; part += 1)
      (after[part] - before[part]).abs() / _laneGraphSpeedStep,
  ];
}

/// [curve] as a speed graph plots it through [times]: how fast each of its
/// numbers changes ([laneGraphSpeedsAt]) inside each stretch between two
/// of its [keyed] frames, and still before the first and after the last —
/// and on a key, the speeds it arrives at and then the ones it leaves at,
/// so the line steps where they differ.
Iterable<({double time, List<double> numbers})> laneGraphSpeeds(
  LaneCurve curve,
  List<int> keyed,
  Iterable<double> times,
) sync* {
  final still = List<double>.filled(curve.parts.length, 0);
  List<double> inStretch(int index, double time) =>
      index < 0 || index + 1 >= keyed.length
      ? still
      : laneGraphSpeedsAt(
          curve,
          time,
          from: keyed[index],
          to: keyed[index + 1],
        );
  var next = 0;
  for (final time in times) {
    while (next < keyed.length && keyed[next] < time) {
      next += 1;
    }
    yield (time: time, numbers: inStretch(next - 1, time));
    if (next < keyed.length && keyed[next] == time) {
      yield (time: time, numbers: inStretch(next, time));
    }
  }
}

/// The speeds each number of [curve] is fitted to across a speed graph,
/// in the order of its parts: from still — the timeline's foot, the
/// sheet's left — to the fastest it goes between its [keyed] frames, with
/// no spare either way (the mock's, 5판); read on both ends of every
/// stretch and [_laneGraphRangeSteps] times across it. A number that never
/// moves is given 0 to 1.
List<LaneGraphRange> laneGraphSpeedRanges(LaneCurve curve, List<int> keyed) {
  final high = List<double>.filled(curve.parts.length, 0);
  for (var index = 0; index + 1 < keyed.length; index += 1) {
    final from = keyed[index];
    final to = keyed[index + 1];
    for (var step = 0; step <= _laneGraphRangeSteps; step += 1) {
      final time = from + (to - from) * step / _laneGraphRangeSteps;
      final speeds = laneGraphSpeedsAt(curve, time, from: from, to: to);
      for (var part = 0; part < high.length; part += 1) {
        high[part] = math.max(high[part], speeds[part]);
      }
    }
  }
  return [
    for (final fastest in high) (low: 0, high: fastest < 1e-6 ? 1 : fastest),
  ];
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

/// A line as a painter plots it: in dashes or not, and what it is fitted
/// to — its keyed frames in order and each number's range — or null for a
/// line with nothing to draw.
typedef _LaneGraphPlot = ({
  LaneGraphLine line,
  bool dashed,
  ({List<int> keyed, List<LaneGraphRange> ranges})? fit,
});

/// A header graph's picture (I-89 ③): each line of [own] solid and each of
/// [guests] dashed, every number it holds in its own colour and fitted to
/// its own range, as [mode] plots it — its values, with a mark on every
/// key, or how fast they change — over the frames [grid] lays, only those
/// its window shows, as its rows of cells draw them
/// ([visibleFrameWindowFor]).
class TimelineLaneGraphPainter extends CustomPainter {
  TimelineLaneGraphPainter({
    required this.own,
    required this.guests,
    required this.grid,
    this.mode = LaneGraphMode.value,
  }) : super(repaint: Listenable.merge([grid.geometry, ?grid.windowBucket]));

  final List<LaneGraphLine> own;
  final List<LaneGraphLine> guests;
  final TimelineCellsRowGrid grid;
  final LaneGraphMode mode;

  Axis get axis => grid.axis;

  /// Each of [own]'s lines and [guests]', with what it is fitted to — read
  /// on the first paint and kept, since its lines are this painter's for
  /// as long as it lives and a scroll paints them again. 🔬Read on every
  /// paint, 200 keys cost 10.7ms a paint to the values and 19.8ms to the
  /// speeds (two lanes, the test VM).
  late final List<_LaneGraphPlot> _plots = [
    for (final line in own) (line: line, dashed: false, fit: _fitOf(line)),
    for (final line in guests) (line: line, dashed: true, fit: _fitOf(line)),
  ];

  ({List<int> keyed, List<LaneGraphRange> ranges})? _fitOf(
    LaneGraphLine line,
  ) {
    final curve = line.lane.curve;
    final keyed = [...line.lane.keyedFrames]..sort();
    if (curve == null || keyed.isEmpty) {
      return null;
    }
    return (
      keyed: keyed,
      ranges: switch (mode) {
        LaneGraphMode.value => laneGraphRanges(curve, keyed),
        LaneGraphMode.speed => laneGraphSpeedRanges(curve, keyed),
      },
    );
  }

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
    final marks = [for (final plot in _plots) ..._drawLine(pass, plot)];
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

  /// Draws every number [plot]'s line holds through [pass], in dashes for
  /// a guest, and gives back the marks its keys in the window take — none
  /// in a speed graph (the mock's, 5판).
  List<_LaneGraphMark> _drawLine(_LaneGraphPass pass, _LaneGraphPlot plot) {
    final (:line, :dashed, :fit) = plot;
    final curve = line.lane.curve;
    if (curve == null || fit == null) {
      return const [];
    }
    final (:keyed, :ranges) = fit;
    final (:canvas, :frames, :window, :times, :extent) = pass;
    Offset at(double time, double number, int part) => offsetAlong(
      axis,
      along: laneGraphAlong(time, frames),
      across: laneGraphAcross(number, ranges[part], extent, axis),
    );
    // Each time read once, for all its numbers.
    final readings = switch (mode) {
      LaneGraphMode.value => [
        for (final time in times) (time: time, numbers: curve.at(time)),
      ],
      LaneGraphMode.speed => laneGraphSpeeds(curve, keyed, times).toList(),
    };
    for (var part = 0; part < curve.parts.length; part += 1) {
      _strokeLaneGraphLine(
        canvas,
        Path()..addPolygon([
          for (final (:time, :numbers) in readings)
            at(time, numbers[part], part),
        ], false),
        curve.parts[part],
        dashed: dashed,
      );
    }
    if (mode == LaneGraphMode.speed) {
      return const [];
    }
    final color = layerMarkColor(line.layer.mark);
    return [
      for (final frame in keyed)
        if (frameWindowContains(window, frame))
          for (final (part, number) in curve.at(frame.toDouble()).indexed)
            (
              at: at(frame.toDouble(), number, part),
              mark: line.lane.keyMarkAt(frame),
              color: color,
            ),
    ];
  }

  @override
  bool shouldRepaint(TimelineLaneGraphPainter oldDelegate) =>
      oldDelegate.own != own ||
      oldDelegate.guests != guests ||
      oldDelegate.grid != grid ||
      oldDelegate.mode != mode;
}

import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show DragGestureRecognizer, DragStartBehavior;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../models/key_mark.dart' show KeyMark;
import '../../models/key_side.dart'
    show EaseSide, KeySideEdit, KeySidesEdit, keyHandleAt, keyHandlePoint;
import '../../models/timeline_row_address.dart';
import '../dashed_path.dart' show DashPattern, dashesAlong;
import '../input/hit_gate.dart' show HitGate;
import '../layout/device_grid_scroll_controller.dart' show ScrollStill;
import '../text/app_strings.dart' show AppText;
import '../theme/app_theme.dart' show AppColors, AppShapes;
import '../widgets/dock_edge_splitter.dart' show DockEdgeSplitter;
import '../widgets/owning_axis_grip.dart' show OwningAxisGrip;
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
        Positioned.fill(child: _standingInTheView(_corners(verbs))),
        _grip(verbs),
      ],
    );
  }

  /// Its tools and its guests' tags, each in its corner of the view.
  Widget _corners(LaneGraphVerbs? verbs) {
    final guests = _guests();
    return CustomMultiChildLayout(
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
    );
  }

  /// Its grip along its cross end: the timeline's bottom, the sheet's
  /// right.
  Widget _grip(LaneGraphVerbs? verbs) => Positioned(
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
  );

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
    return LaneGraphPicture(
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
    );
  }
}

/// A header graph's picture ([TimelineLaneGraphPainter]) and its HANDLES
/// pulled (I-89 ③): a press on a handle takes it — anywhere else it falls
/// to what lies under ([HitGate]) — and owns the gesture, as every grip's
/// press does ([OwningAxisGrip]); the pull is shown while it lasts and
/// written where it is let go, through the lane edits the rows take
/// ([PropertyLaneEditCallbacks.onSetKeySides]) — the key window's write.
///
/// While a handle is in hand the picture is held to what its lines were
/// fitted to when it was taken ([TimelineLaneGraphPainter.held]).
class LaneGraphPicture extends StatefulWidget {
  const LaneGraphPicture({
    super.key,
    required this.own,
    required this.guests,
    required this.grid,
    required this.mode,
  });

  final List<LaneGraphLine> own;
  final List<LaneGraphLine> guests;
  final TimelineCellsRowGrid grid;
  final LaneGraphMode mode;

  @override
  State<LaneGraphPicture> createState() => _LaneGraphPictureState();
}

/// A handle in hand: the press that took it, what the picture is held to
/// meanwhile, and what the pull writes so far — none until it moves.
class _HandleInHand {
  _HandleInHand(this.handle, this.press, this.fits);

  final LaneGraphHandle handle;
  final Offset press;
  final Map<String, LaneGraphFit> fits;
  KeySidesEdit? edit;
}

class _LaneGraphPictureState extends State<LaneGraphPicture> {
  _HandleInHand? _inHand;

  /// The painter the last build drew with — what a press is asked of.
  late TimelineLaneGraphPainter _painter;

  PropertyLaneEditCallbacks? get _edits => widget.grid.hooks.laneEdit;

  @override
  Widget build(BuildContext context) {
    final painter = _painter = TimelineLaneGraphPainter(
      own: widget.own,
      guests: widget.guests,
      grid: widget.grid,
      mode: widget.mode,
      held: _inHand?.fits ?? const {},
    );
    return HitGate(
      admits: (position) => painter.handleAt(position, context.size!) != null,
      child: OwningAxisGrip(
        axis: null,
        configure: _configure,
        child: CustomPaint(painter: painter, child: const SizedBox.expand()),
      ),
    );
  }

  // A drag the platform cancels once it has started ends as a release does
  // — the recogniser's own rule, and every drag's here (a lane's scrub, a
  // canvas box): what it showed is written.
  void _configure(DragGestureRecognizer recognizer) {
    recognizer
      // A handle is small: it is the one the press went down on.
      ..dragStartBehavior = DragStartBehavior.down
      ..onStart = _take
      ..onUpdate = _pull
      ..onEnd = (_) => _drop();
  }

  void _take(DragStartDetails details) {
    final handle = _painter.handleAt(details.localPosition, context.size!);
    if (handle != null) {
      setState(
        () => _inHand = _HandleInHand(
          handle,
          details.localPosition,
          _painter.fits,
        ),
      );
    }
  }

  /// The handle follows the hand by as far as the hand has gone.
  void _pull(DragUpdateDetails details) {
    final inHand = _inHand;
    if (inHand == null) {
      return;
    }
    final handle = inHand.handle;
    final edit = inHand.edit = laneGraphPull(
      handle,
      handle.at + details.localPosition - inHand.press,
      frames: widget.grid.geometry.value,
      axis: widget.grid.axis,
    );
    _edits?.onPreviewKeySides?.call(
      handle.line.layer,
      handle.line.lane,
      handle.frame,
      edit,
    );
  }

  /// Let go of: written where it was pulled to — nothing, where it never
  /// moved.
  void _drop() {
    final inHand = _inHand;
    if (inHand == null) {
      return;
    }
    setState(() => _inHand = null);
    final edit = inHand.edit;
    if (edit != null) {
      final line = inHand.handle.line;
      _edits?.onSetKeySides?.call(
        line.layer,
        line.lane,
        inHand.handle.frame,
        edit,
      );
    }
  }

  @override
  void dispose() {
    // A picture taken away with a handle in hand never sees its release:
    // what it was showing is dropped once the tree settles — a notifier
    // fired while the tree is torn down would be too soon.
    final end = _edits?.onEndPreview;
    if (_inHand?.edit != null && end != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => end());
    }
    super.dispose();
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

/// A handle's circle and its ink, and its stem's width (the mock's, 5판).
const double _laneGraphHandleRadius = 4.5;
const double _laneGraphHandleStroke = 1.6;
const double _laneGraphStemStroke = 1;

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
  final frame = time.floor();
  final from = _laneGraphMiddle(frame, frames);
  return from + (time - frame) * (_laneGraphMiddle(frame + 1, frames) - from);
}

/// [laneGraphAlong] read back: the time that stands at [along] on a graph
/// laid by [frames] — what a handle is pulled to (I-89 ③). It lives beside
/// it so the two cannot drift.
double laneGraphTimeAt(double along, TimelineFrameGeometry frames) {
  final cell = frames.frameCellExtent;
  if (cell <= 0) {
    return 0;
  }
  // A middle stands within a pixel of a cell on from frame 0's, so this is
  // at most a frame off either way.
  var frame = ((along - _laneGraphMiddle(0, frames)) / cell).floor();
  while (_laneGraphMiddle(frame + 1, frames) <= along) {
    frame += 1;
  }
  while (_laneGraphMiddle(frame, frames) > along) {
    frame -= 1;
  }
  final from = _laneGraphMiddle(frame, frames);
  return frame +
      (along - from) / (_laneGraphMiddle(frame + 1, frames) - from);
}

/// The middle of [frame]'s cell, where a lane marks its key.
double _laneGraphMiddle(int frame, TimelineFrameGeometry frames) =>
    (frames.edgeAt(frame) + frames.edgeAt(frame + 1)) / 2;

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

/// What a line is fitted to across its graph: its keyed frames in order
/// and each number's range.
typedef LaneGraphFit = ({List<int> keyed, List<LaneGraphRange> ranges});

/// A line as a painter plots it: in dashes or not, and what it is fitted
/// to — or null for a line with nothing to draw.
typedef _LaneGraphPlot = ({LaneGraphLine line, bool dashed, LaneGraphFit? fit});

/// A HANDLE a header graph draws (I-89 ③): the side of [line]'s key on
/// [frame] it pulls — [leaving] the key, or arriving at it — drawn [at],
/// its stem from the key's mark at [key]; and the segment it bends, from
/// the key on [frames]' `from` to the next: where the two keys stand across
/// the graph.
typedef LaneGraphHandle = ({
  LaneGraphLine line,
  int frame,
  bool leaving,
  Offset at,
  Offset key,
  ({int from, int to}) frames,
  ({double from, double to}) across,
});

/// What pulling [handle] to [position] writes (I-89 ③): its side's
/// influence and its speed, read back off the segment's square as the
/// graph — laid along by [frames] — draws it ([keyHandleAt], the reading
/// [keyHandlePoint] draws the handle by).
///
/// A segment whose two keys stand level across the graph has no height to
/// read a speed off, so it takes the influence alone.
KeySidesEdit laneGraphPull(
  LaneGraphHandle handle,
  Offset position, {
  required TimelineFrameGeometry frames,
  required Axis axis,
}) {
  final (along, across) = axis == Axis.horizontal
      ? (position.dx, position.dy)
      : (position.dy, position.dx);
  final span = handle.frames;
  final x =
      (laneGraphTimeAt(along, frames) - span.from) / (span.to - span.from);
  final rise = handle.across.to - handle.across.from;
  final level = rise == 0;
  final (:influence, :speed) = keyHandleAt(
    x,
    level ? 0 : (across - handle.across.from) / rise,
    leaving: handle.leaving,
  );
  final rate = level ? null : speed;
  return handle.leaving
      ? KeySidesEdit(
          outgoing: KeySideEdit(influence: influence, speed: rate),
        )
      : KeySidesEdit(
          incoming: KeySideEdit(influence: influence, speed: rate),
        );
}

/// A header graph's picture (I-89 ③): each line of [own] solid and each of
/// [guests] dashed, every number it holds in its own colour and fitted to
/// its own range, as [mode] plots it — its values, with a mark on every
/// key, or how fast they change — over the frames [grid] lays, only those
/// its window shows, as its rows of cells draw them
/// ([visibleFrameWindowFor]); and over them, its handles.
class TimelineLaneGraphPainter extends CustomPainter {
  TimelineLaneGraphPainter({
    required this.own,
    required this.guests,
    required this.grid,
    this.mode = LaneGraphMode.value,
    this.held = const {},
  }) : super(repaint: Listenable.merge([grid.geometry, ?grid.windowBucket]));

  final List<LaneGraphLine> own;
  final List<LaneGraphLine> guests;
  final TimelineCellsRowGrid grid;
  final LaneGraphMode mode;

  /// What a handle in hand holds its lines to, by line ([laneGroupKey]):
  /// what they were fitted to when it was taken ([fits]).
  final Map<String, LaneGraphFit> held;

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

  /// What each line is fitted to, by line — what a handle taken holds the
  /// picture to ([held]): refitted to the curve its pull bends, a line
  /// would slide out from under the hand.
  Map<String, LaneGraphFit> get fits => {
    for (final (:line, dashed: _, :fit) in _plots) _lineKey(line): ?fit,
  };

  static String _lineKey(LaneGraphLine line) =>
      laneGroupKey(line.layer.id, line.lane.laneId);

  /// The handles [handlesIn] last read, and where they were read for.
  ({
    Size size,
    TimelineFrameGeometry frames,
    ({int startIndex, int endIndexExclusive}) window,
    List<LaneGraphHandle> handles,
  })?
  _handled;

  LaneGraphFit? _fitOf(LaneGraphLine line) {
    if (held[_lineKey(line)] case final fit?) {
      return fit;
    }
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
    // A pull bends a line past what it was fitted to, and a handle stands
    // off its line: the picture stays inside its own box.
    canvas.clipRect(Offset.zero & size);
    // The marks go on last, over every line and the handles' stems — and
    // the handles over them (the mock's, 5판).
    final marks = [for (final plot in _plots) ..._drawLine(pass, plot)];
    final handles = handlesIn(size);
    final stem = Paint()
      ..strokeWidth = _laneGraphStemStroke
      ..color = AppColors.textDim;
    for (final handle in handles) {
      canvas.drawLine(handle.key, handle.at, stem);
    }
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
    final fill = Paint()..color = AppColors.surface;
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _laneGraphHandleStroke
      ..color = AppColors.accent;
    for (final handle in handles) {
      canvas
        ..drawCircle(handle.at, _laneGraphHandleRadius, fill)
        ..drawCircle(handle.at, _laneGraphHandleRadius, ink);
    }
  }

  /// The handle a press at [position] takes on a picture [size] big: the
  /// one drawn last over it, on what is drawn of it — its circle and its
  /// ink — and nowhere round it (F-262: 「보이는 만큼 존재하도록」). Null
  /// where there is none.
  LaneGraphHandle? handleAt(Offset position, Size size) {
    const reach = _laneGraphHandleRadius + _laneGraphHandleStroke / 2;
    for (final handle in handlesIn(size).reversed) {
      if ((handle.at - position).distance <= reach) {
        return handle;
      }
    }
    return null;
  }

  /// Every handle a picture [size] big shows, in the order they are drawn —
  /// read once for where the grid lays its window, since a mouse asks
  /// [handleAt] on every move it makes over the picture. The probe surface
  /// for the handles' tests, as [visibleFrameWindow] is for the window's.
  List<LaneGraphHandle> handlesIn(Size size) {
    final frames = grid.geometry.value;
    final window = visibleFrameWindow();
    if (_handled case final last?
        when last.size == size &&
            last.frames == frames &&
            last.window == window) {
      return last.handles;
    }
    final extent = extentAcross(axis, size);
    final handles = [
      for (final plot in _plots) ..._handlesOf(plot, frames, window, extent),
    ];
    _handled = (size: size, frames: frames, window: window, handles: handles);
    return handles;
  }

  /// The handles [plot]'s line takes (the mock's, 5판): in a value graph,
  /// on a line of one number, one on each side of a key that eases toward
  /// the key beside it — where that side bends their segment
  /// ([keyHandlePoint]) — on every segment [window] shows some of.
  Iterable<LaneGraphHandle> _handlesOf(
    _LaneGraphPlot plot,
    TimelineFrameGeometry frames,
    ({int startIndex, int endIndexExclusive}) window,
    double extent,
  ) sync* {
    final (:line, dashed: _, :fit) = plot;
    final curve = line.lane.curve;
    if (mode != LaneGraphMode.value ||
        curve == null ||
        fit == null ||
        curve.parts.length != 1) {
      return;
    }
    final (:keyed, :ranges) = fit;
    double across(double value) =>
        laneGraphAcross(value, ranges.single, extent, axis);
    for (var index = 0; index + 1 < keyed.length; index += 1) {
      final span = (from: keyed[index], to: keyed[index + 1]);
      if (span.to < window.startIndex ||
          span.from >= window.endIndexExclusive) {
        continue;
      }
      final eases = _easesToward(curve, span);
      if (eases.isEmpty) {
        continue;
      }
      final values = (
        from: curve.at(span.from.toDouble()).single,
        to: curve.at(span.to.toDouble()).single,
      );
      final ends = (from: across(values.from), to: across(values.to));
      for (final (:side, :leaving) in eases) {
        final (:x, :y) = keyHandlePoint(
          (influence: side.influence, speed: side.speed),
          leaving: leaving,
        );
        final frame = leaving ? span.from : span.to;
        yield (
          line: line,
          frame: frame,
          leaving: leaving,
          at: offsetAlong(
            axis,
            along: laneGraphAlong(
              span.from + x * (span.to - span.from),
              frames,
            ),
            across: across(values.from + y * (values.to - values.from)),
          ),
          key: offsetAlong(
            axis,
            along: laneGraphAlong(frame.toDouble(), frames),
            across: leaving ? ends.from : ends.to,
          ),
          frames: span,
          across: ends,
        );
      }
    }
  }

  /// The sides of [span]'s two keys that ease toward each other — the
  /// first's leaving and the last's arriving, each where it is an ease.
  static List<({EaseSide side, bool leaving})> _easesToward(
    LaneCurve curve,
    ({int from, int to}) span,
  ) => [
    if (curve.sides[span.from]?.outgoing case final EaseSide side)
      (side: side, leaving: true),
    if (curve.sides[span.to]?.incoming case final EaseSide side)
      (side: side, leaving: false),
  ];

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
      oldDelegate.mode != mode ||
      oldDelegate.held != held;
}

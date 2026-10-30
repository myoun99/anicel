import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable, listEquals;
import 'package:flutter/gestures.dart'
    show DragDownDetails, DragGestureRecognizer, DragStartBehavior;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../core/neighbour_pairs.dart';
import '../../models/key_mark.dart' show KeyMark;
import '../../models/key_side.dart'
    show
        EaseSide,
        KeySideEdit,
        KeySidesEdit,
        keyHandleAt,
        keyHandleInfluenceAt,
        keyHandlePoint;
import '../../models/timeline_frame_range.dart' show TimelineLaneSelection;
import '../../models/timeline_row_address.dart'
    show LaneRowAddress, TimelineRowAddress;
import '../../core/segment_share.dart' show nearestOnSegment;
import '../../services/input/modifier_keys.dart' show ModifierKeys;
import '../dashed_path.dart'
    show
        DashPattern,
        antsColour,
        antsDashes,
        dashesAlong,
        paintDashedOutline;
import '../input/hit_gate.dart' show HitGate;
import '../input/timeline_edit_pan.dart';
import '../layout/device_grid_scroll_controller.dart' show ScrollStill;
import '../text/app_strings.dart' show AppStrings, AppText;
import '../theme/app_theme.dart' show AppColors, AppShapes;
import '../widgets/app_icon_button.dart'
    show AppIconButton, AppIconButtonSize;
import '../widgets/dock_edge_splitter.dart' show DockEdgeSplitter;
import '../widgets/owning_axis_grip.dart' show OwningAxisGrip;
import '../widgets/pill_strip.dart' show PillItem, PillStrip;
import 'axis_turn.dart'
    show
        acrossBox,
        extentAcross,
        extentAlong,
        offsetAlong,
        partAcross,
        partAlong,
        stripAcross;
import 'key_mark_glyph.dart' show paintKeyMark;
import 'lane_graph.dart';
import 'lane_graph_box_stretch.dart';
import 'lane_graph_seats.dart'
    show LaneGraphLine, laneGraphDrawnLanes, laneGraphGuests;
import 'lane_graph_snap.dart'
    show
        LaneGraphCarry,
        LaneGraphSnap,
        LaneGraphSnapKey,
        LaneGraphSnapLine,
        laneGraphUnsnapped;
import 'layer_label_controls.dart' show layerMarkColor;
import 'property_lane_model.dart';
import 'timeline_cells_row_facts.dart' show TimelineCellsRowGrid;
import 'timeline_drag_preview.dart' show timelineDragPreviewLayerFor;
import 'timeline_edge_auto_pan.dart' show edgeAutoPanApply;
import 'timeline_frame_geometry.dart';
import 'timeline_frame_range_gesture.dart'
    show
        TimelineLaneRangeCallbacks,
        reportRangeDragFinished,
        retireRangeDragOnUnmount;
import 'timeline_frame_window.dart'
    show frameWindowContains, visibleFrameWindowFor;
import 'timeline_grid_hooks.dart' show TimelineGridHooks;
import 'timeline_lane_rows.dart'
    show selectedLaneKeyRing, timelineLaneKeyMarkerSize;
import 'timeline_row_edges.dart';
import 'transform_lane_policy.dart' show laneSelectionPicksKey;

/// What keeps a row a grid lays on the frame side while only its window
/// moves ([WindowMoveKeep.row]): the row kept for [key], else [build]'s.
typedef TimelineRowKeep =
    Widget Function(Object key, Widget Function() build);

/// A row built now and kept by nothing — the frame side of a grid whose
/// window does not move.
Widget timelineRowBuiltNow(Object key, Widget Function() build) => build();

/// Rows as a grid lays them: [rows] are its rows from [first] on, [edges]
/// where every one of its rows sits, and [kept] what keeps them while only
/// the grid's window moves.
typedef TimelineLaidRows = ({
  List<TimelineDisplayRow> rows,
  int first,
  TimelineRowEdges edges,
  TimelineRowKeep kept,
});

/// What [grid] lays on the frame side for [laid] ([laneGraphFrameSide]),
/// its graphs drawing what its hooks tell ([timelineLaneGraphLines]).
List<Widget> timelineFrameSide(
  TimelineLaidRows laid,
  TimelineCellsRowGrid grid, {
  required Widget Function(TimelineDisplayRow row) cells,
  required TimelineLaneRangeCallbacks? laneRange,
}) => laneGraphFrameSide(
  laid,
  laneGraphGridOf(grid, laneRange: laneRange),
  lines: (seat, lanes) => timelineLaneGraphLines(seat, lanes, grid.hooks),
  cells: cells,
);

/// What a rail lays on the frame side for [laid]: each row's own [cells],
/// and an open graph's lanes as ONE [TimelineLaneGraph] across their whole
/// unit (I-89 ③), drawn in [grid] with the [lines] its seat and its lanes
/// draw — or, folded by the enlarged one, as its empty strip. The
/// timeline's and the sheet's grids lay theirs so, and the storyboard's
/// rail its own (I-89 ①).
List<Widget> laneGraphFrameSide(
  TimelineLaidRows laid,
  LaneGraphGrid grid, {
  required LaneGraphLines Function(
    TimelineGraphSeat seat,
    List<TimelineDisplayRow> lanes,
  )
  lines,
  required Widget Function(TimelineDisplayRow row) cells,
}) {
  final (:rows, :first, :edges, :kept) = laid;
  final axis = grid.frameAxis.axis;
  return [
    for (final unit in edges.unitsIn(first, first + rows.length))
      // The mock's 5판 draws nothing in a folded graph's strip.
      if (rows[unit.first - first] case TimelineDisplayRow(
        graph: _?,
        folded: true,
      ))
        acrossBox(axis, edges.unitSpanOf(unit.first).extent)
      else if (rows[unit.first - first].graph case final seat?)
        kept(
          ('lane-graph', seat.groupKey),
          () => TimelineLaneGraph(
            key: ValueKey<String>(
              '${grid.keyPrefix}-lane-graph-${seat.groupKey}',
            ),
            seat: seat,
            lines: lines(
              seat,
              rows.sublist(unit.first - first, unit.last - first + 1),
            ),
            grid: grid,
            crossExtent: edges.unitSpanOf(unit.first).extent,
            lanesExtent:
                edges.unitSpanOf(unit.first).extent - edges.roomOf(unit.last),
            mostExtent: edges.graphMost,
          ),
        )
      else ...[
        cells(rows[unit.first - first]),
        if (edges.roomOf(unit.last) > 0)
          acrossBox(axis, edges.roomOf(unit.last)),
      ],
  ];
}

/// The frames a header graph is drawn over (I-89 ③), as the grid's rows of
/// cells lay them: the grid's live geometry (the view's extent along them
/// with it), the window over it and which way they run — what its picture and
/// its handles read — and how far a lane's row of them reaches across: the
/// room its keys are marked in, which a graph's are marked in too
/// (F-367-Q3). And what a key carried snaps to along them besides the keys
/// (graph-key-drag-snaps, AE's snap): the frame the grid's [playhead]
/// stands on — none where it keeps none — and their end, [frameCount]
/// frames on from frame 0 — none where it is 0.
typedef LaneGraphFrames = ({
  ValueNotifier<TimelineFrameGeometry> geometry,
  ValueListenable<int>? windowBucket,
  Axis axis,
  double laneExtent,
  ValueListenable<int?>? playhead,
  int frameCount,
});

/// What a header graph reads of the grid it is drawn in (I-89 ③): its
/// [LaneGraphFrames], the scrollable its corners stand still in, its key
/// prefix, the lane edits its handles write through, the buttons its
/// tools and its grip tell, and the lane selection its keys are picked
/// and carried by — the one its lanes' rows take (I-3).
///
/// ⛔Not the grid's whole hook bundle ([TimelineCellsRowGrid]): a graph
/// reads these and nothing else of it. The timeline's and the sheet's
/// grids hand it theirs ([laneGraphGridOf]); a rail that lays no cells
/// row hands it its own.
typedef LaneGraphGrid = ({
  LaneGraphFrames frameAxis,
  ScrollController? frameAxisController,
  String keyPrefix,
  LaneGraphVerbs? verbs,
  PropertyLaneEditCallbacks? laneEdit,
  TimelineLaneRangeCallbacks? laneRange,
});

/// [grid] as a header graph drawn in it reads it, its keys picked and
/// carried by [laneRange] — what the grid's lane rows take.
LaneGraphGrid laneGraphGridOf(
  TimelineCellsRowGrid grid, {
  required TimelineLaneRangeCallbacks? laneRange,
}) => (
  frameAxis: (
    geometry: grid.geometry,
    windowBucket: grid.windowBucket,
    axis: grid.axis,
    laneExtent: grid.metrics.layerRowHeight,
    playhead: grid.hooks.frameCursor,
    frameCount: grid.hooks.playbackFrameCount,
  ),
  frameAxisController: grid.frameAxisController,
  keyPrefix: grid.keyPrefix,
  verbs: grid.hooks.laneGraphVerbs,
  laneEdit: grid.hooks.laneEdit,
  laneRange: laneRange,
);

/// What a header graph draws (I-89 ③): its own lines and its guests as
/// they stand, read again whenever [changes] says they moved.
typedef LaneGraphLines = ({
  Listenable changes,
  List<LaneGraphLine> Function() own,
  List<LaneGraphLine> Function() guests,
});

/// What [seat]'s graph draws on a grid [hooks] tells ([laneGraphLines]):
/// each of its lanes as a drag in flight shows its row
/// ([previewedLaneRow]), and every pin as the host finds it.
LaneGraphLines timelineLaneGraphLines(
  TimelineGraphSeat seat,
  List<TimelineDisplayRow> lanes,
  TimelineGridHooks hooks,
) {
  final preview = hooks.dragPreview;
  final lanesForLayer = hooks.lanesForLayer;
  final lineOf = hooks.laneGraphLineOf;
  return laneGraphLines(seat, lanes, (
    standing: hooks.currentRowHooks?.currentRow,
    moves: preview,
    linesOf: (row) => [
      if (timelineDragPreviewLayerFor(preview?.value, row.layer.id)
          case final layer?)
        (
          layer: layer,
          lane: previewedLaneRow(
            row: row,
            previewLayer: layer,
            lanesForLayer: (layer) => lanesForLayer?.call(layer) ?? const [],
          ),
          reach: null,
        )
      else
        (layer: row.layer, lane: row.lane!, reach: null),
    ],
    pinned: hooks.laneGraphs.pinned,
    guestsOf: (key) => [?lineOf?.call(key)],
  ));
}

/// Where a grid's header graphs read their lines (I-89 ①): the row its
/// rail stands on and what says a drag moved — when to read again — each
/// lane's lines as its row reads now, and the pins with the lines each
/// names. The timeline's hooks hand theirs ([timelineLaneGraphLines]); the
/// storyboard's rail its own.
typedef LaneGraphSources = ({
  ValueListenable<TimelineRowAddress?>? standing,
  Listenable? moves,
  Iterable<LaneGraphLine> Function(TimelineDisplayRow row) linesOf,
  Set<String> pinned,
  Iterable<LaneGraphLine> Function(String key) guestsOf,
});

/// What [seat]'s graph draws (I-89 ③): of [lanes] — the group's lanes as
/// the rail draws them, in its order — the ones it draws as its own
/// ([laneGraphDrawnLanes]), read off where the rail stands, each as
/// [sources] reads its row now; and every pin of another group's as a
/// guest ([laneGraphGuests]), as [sources] finds it. A lane a storyboard's
/// projection row draws is a line a cut. Read again whenever the rail
/// stands elsewhere or a drag moves.
LaneGraphLines laneGraphLines(
  TimelineGraphSeat seat,
  List<TimelineDisplayRow> lanes,
  LaneGraphSources sources,
) {
  final (:standing, :moves, :linesOf, :pinned, :guestsOf) = sources;
  return (
    changes: Listenable.merge([standing, moves]),
    own: () {
      final drawn = laneGraphDrawnLanes(seat, standing?.value);
      return [
        for (final row in lanes)
          if (drawn.contains(row.lane!.laneId)) ...linesOf(row),
      ];
    },
    guests: () => [
      for (final key in laneGraphGuests(seat, pinned)) ...guestsOf(key),
    ],
  );
}

/// An open graph on the frame side: ONE picture over its group's lanes and
/// the room after them, where their rows of cells would be (I-89 ③) — the
/// same widget on the timeline and, turned on its side, the sheet.
///
/// It draws its [lines]: its own, and every pin of another group's as a
/// guest, named in the view's far corner ([LaneGraphGuestTags]) — its
/// tools in the near one ([LaneGraphTools]). Along the frames it is a row
/// of cells: laid out by the grid's live geometry ([TimelineFrameAxisBox])
/// and drawing only its window, so a scroll or a zoom step repaints it and
/// rebuilds nothing.
class TimelineLaneGraph extends StatelessWidget {
  const TimelineLaneGraph({
    super.key,
    required this.seat,
    required this.lines,
    required this.grid,
    required this.crossExtent,
    required this.lanesExtent,
    required this.mostExtent,
  });

  final TimelineGraphSeat seat;

  /// What it draws, as it stands.
  final LaneGraphLines lines;

  /// The grid it is drawn in, as a graph reads it.
  final LaneGraphGrid grid;

  /// How far it reaches across the frames — its lanes and the room after
  /// them.
  final double crossExtent;

  /// How far its lanes alone reach across the frames: the least its grip
  /// makes it.
  final double lanesExtent;

  /// The most its grip makes it — what an enlarged graph stands
  /// ([TimelineRowEdges.graphMost]).
  final double mostExtent;

  Axis get _axis => grid.frameAxis.axis;

  @override
  Widget build(BuildContext context) {
    final verbs = grid.verbs;
    return Stack(
      children: [
        TimelineFrameAxisBox(
          geometry: grid.frameAxis.geometry,
          crossAxisExtent: crossExtent,
          axis: _axis,
          child: RepaintBoundary(
            child: ListenableBuilder(
              listenable: lines.changes,
              builder: (context, _) => LaneGraphPicture(
                own: lines.own(),
                guests: lines.guests(),
                frameAxis: grid.frameAxis,
                edits: grid.laneEdit,
                lanes: grid.laneRange,
                mode: seat.graph.mode,
                pen: seat.graph.pen,
                transformBox: seat.graph.transformBox,
                snap: seat.graph.snap,
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
    final guests = lines.guests();
    return CustomMultiChildLayout(
      delegate: _LaneGraphCorners(
        _axis,
        grid.frameAxis.geometry,
      ),
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
            enlarged: seat.graph.enlarged,
            onEnlarge: verbs == null
                ? null
                : () => verbs.enlarge(seat.groupKey),
            pen: seat.graph.pen,
            onPen: verbs == null ? null : () => verbs.pen(seat.groupKey),
            transformBox: seat.graph.transformBox,
            onTransformBox: verbs == null
                ? null
                : () => verbs.transformBox(seat.groupKey),
            snap: seat.graph.snap,
            onSnap: verbs == null ? null : () => verbs.snap(seat.groupKey),
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
  Widget _grip(LaneGraphVerbs? verbs) => stripAcross(
    _axis,
    across: 0,
    fromEnd: true,
    child: LaneGraphGrip(
      key: ValueKey<String>(
        '${grid.keyPrefix}-lane-graph-grip-${seat.groupKey}',
      ),
      axis: _axis,
      extent: crossExtent,
      least: lanesExtent,
      most: mostExtent,
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
            axisDirection: _axis == Axis.horizontal
                ? AxisDirection.right
                : AxisDirection.down,
            child: corners,
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
/// And its KEYS (I-3, AE's graph editor): a press on one picks it in the
/// lane selection its lanes' rows take, and a drag carries the selection
/// along the frames by their move ([TimelineLaneRangeCallbacks]) — the
/// lanes' own law (2026-08-08: a key is moved by moving the selection that
/// holds it), so a key carried here lands where its row would have put it.
///
/// And its PEN (I-3 ④, AE's pen in the graph editor): with it up, or Ctrl
/// held (⌘ on a Mac), a press on a line puts a key there, the value it
/// holds kept — through the ＋ its lanes' rows take, on the cell pressed.
///
/// And its BOX (I-3 ⑤, AE's graph editor): a drag on its ground — where
/// none of those takes the press — draws a box, and what it holds is
/// picked as it is drawn: the frames it spans across the lanes of the
/// keys inside it ([TimelineLaneRangeCallbacks.onSelectRows]). A tap there
/// lets every key go, as a tap on a lane's band does.
///
/// And its SNAP (graph-key-drag-snaps, AE's snap in its graph editor): with
/// it on — or off, with Ctrl held (⌘ on a Mac) for as long as it is held —
/// a key carried snaps to the keys about it, the playhead and the frames'
/// ends, a line drawn where it does ([LaneGraphCarry]). A box's handle
/// pulled stretches unsnapped: Ctrl says something else there.
///
/// While a handle or a key is in hand the picture is held to what its
/// lines were fitted to when it was taken ([TimelineLaneGraphPainter.held]).
class LaneGraphPicture extends StatefulWidget {
  const LaneGraphPicture({
    super.key,
    required this.own,
    required this.guests,
    required this.frameAxis,
    required this.edits,
    required this.lanes,
    required this.mode,
    this.pen = false,
    this.transformBox = true,
    this.snap = false,
  });

  final List<LaneGraphLine> own;
  final List<LaneGraphLine> guests;

  /// The frames it is drawn over.
  final LaneGraphFrames frameAxis;

  /// What a handle let go of writes through; null where the host takes no
  /// lane edits, and a pull shows and writes nothing.
  final PropertyLaneEditCallbacks? edits;

  /// The lane selection its keys are picked and carried by — its lanes'
  /// rows'; null where the host takes none, and a key takes no press.
  final TimelineLaneRangeCallbacks? lanes;
  final LaneGraphMode mode;

  /// Whether its graph's pen is up ([LaneGraph.pen]).
  final bool pen;

  /// Whether its graph's transform box is shown ([LaneGraph.transformBox]).
  final bool transformBox;

  /// Whether its graph's snap is on ([LaneGraph.snap]).
  final bool snap;

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

/// A key the hand lifts with the one in hand (I-3 ②): its lane, its frame
/// and its numbers as they stood, which of them the hand raises, and the
/// range its line was fitted to across the graph.
typedef _KeyLifted = ({
  String laneId,
  int frame,
  List<double> numbers,
  int part,
  LaneGraphRange range,
});

/// A KEY in hand (I-3): the key the press went down on, where, what the
/// picture is held to meanwhile, and how far the selection's move has
/// carried it — none until the hand moves, and none where there was
/// nothing to move.
class _KeyInHand {
  _KeyInHand(
    this.key,
    this.press,
    this.fits, {
    this.box,
    this.marks = const [],
  });

  final LaneGraphKey key;
  final Offset press;
  final Map<String, LaneGraphFit> fits;

  /// The handle of the box round the keys picked the press took, and what
  /// they stood at (I-3 ⑥) — null where it took a key: the hand stretches
  /// the keys picked rather than carrying them, with [key] the one picked
  /// nearest the handle.
  final LaneGraphBoxHeld? box;

  /// The marks a stretch raises across a value graph, as they stood when
  /// the handle was taken, and where each stood — at what time on the
  /// graph's frames, and how far across it ([_LaneGraphLift.marksOf]).
  final List<({_KeyLifted lifted, double time, double across})> marks;
  bool moving = false;
  int frames = 0;

  /// How far across the graph the hand has gone, in pixels — what a value
  /// graph raises the keys by (I-3 ②).
  double rise = 0;

  /// The keys it lifts, as they stood when the move began — none until it
  /// does ([_LaneGraphLift.keysOf]).
  List<_KeyLifted> lifted = const [];

  /// How the hand carries it, and what it snaps to — none until the move
  /// begins ([_LaneGraphLift.carryOf]) — and where it has snapped.
  LaneGraphCarry? carry;
  LaneGraphSnap snap = laneGraphUnsnapped;

  /// The line it draws where it has snapped ([LaneGraphSnapLine]) — none
  /// until the move begins.
  CustomPainter? get snapLine => switch (carry) {
    final carry? => LaneGraphSnapLine(carry, snap),
    null => null,
  };

  /// The row the key is on — what a grid holds built while it is carried.
  TimelineRowAddress get row =>
      LaneRowAddress(key.line.layer.id, key.line.lane.laneId);
}

/// A BOX in hand (I-3 ⑤): where the press that drew it went down, where
/// the hand is now, and what it picked last — none until it picks.
class _BoxInHand {
  _BoxInHand(this.press) : now = press;

  final Offset press;
  Offset now;
  List<LaneRowAddress>? rows;
  int anchor = 0;
  int head = 0;

  Rect get rect => Rect.fromPoints(press, now);
}

class _LaneGraphPictureState extends State<LaneGraphPicture> {
  _HandleInHand? _inHand;
  _KeyInHand? _keyInHand;
  _BoxInHand? _box;

  /// The ANCHOR POINT of the box round the keys picked where the hand has
  /// put it (graph-box-handles-more ⓓ) — null where it stands in the
  /// middle, as on keys picked anew ([_pickedAnew]).
  LaneGraphBoxPoint? _pivot;

  /// How far off the anchor point the hand holding it holds it — null where
  /// the press under way did not take it ([_pick] asks anew at every one).
  Offset? _pivotGrab;

  @override
  void initState() {
    super.initState();
    widget.lanes?.selection.addListener(_pickedAnew);
  }

  @override
  void didUpdateWidget(LaneGraphPicture oldWidget) {
    super.didUpdateWidget(oldWidget);
    final was = oldWidget.lanes?.selection;
    final now = widget.lanes?.selection;
    if (was != now) {
      was?.removeListener(_pickedAnew);
      now?.addListener(_pickedAnew);
    }
  }

  /// The keys picked anew: the anchor point back in the middle, as AE's on
  /// a new box. A carry's selection riding with its keys is the same keys
  /// picked, and keeps it — and its landing leaves the selection where the
  /// ride put it.
  void _pickedAnew() {
    if (_pivot == null || (_keyInHand?.moving ?? false)) {
      return;
    }
    setState(() => _pivot = null);
  }

  /// The painter the last build drew with — what a press is asked of.
  late TimelineLaneGraphPainter _painter;

  PropertyLaneEditCallbacks? get _edits => widget.edits;

  /// What its hand lifts of its lines, on the picture as it is laid out.
  _LaneGraphLift get _lift => _LaneGraphLift(widget, context.size!);

  /// What a press picks on its lines.
  _LaneGraphPicks get _picks => _LaneGraphPicks(widget);

  @override
  Widget build(BuildContext context) {
    final painter = _painter = TimelineLaneGraphPainter(
      own: widget.own,
      guests: widget.guests,
      frameAxis: widget.frameAxis,
      mode: widget.mode,
      selection: widget.lanes?.selection,
      held: _inHand?.fits ?? _keyInHand?.fits ?? const {},
      box: _box?.rect,
      transformBox: widget.transformBox,
      pivot: _pivot ?? laneGraphBoxMiddle,
    );
    final picture = HitGate(
      admits: _takesPressAt,
      child: OwningAxisGrip(
        axis: null,
        configure: _configure,
        child: CustomPaint(
          painter: painter,
          foregroundPainter: _keyInHand?.snapLine,
          child: const SizedBox.expand(),
        ),
      ),
    );
    final lanes = widget.lanes;
    if (lanes == null || lanes.onSelectRows == null) {
      return picture;
    }
    return Stack(fit: StackFit.expand, children: [_ground(lanes), picture]);
  }

  /// Its GROUND, under the picture: wherever no handle, key, line or the
  /// box round the keys picked ([LaneGraphPicked.box])
  /// takes the press, a drag draws a box (I-3 ⑤) — with the devices a lane's
  /// band selects with, a finger scrolling where they do not — and a tap
  /// lets every key go, as a tap on the band does (H18).
  Widget _ground(TimelineLaneRangeCallbacks lanes) => GestureDetector(
    key: const ValueKey<String>('lane-graph-ground'),
    behavior: HitTestBehavior.opaque,
    onTap: lanes.onTapClear,
    child: TimelineEditPan(
      debugOwner: this,
      firstStepAt: _boxSteppedAt,
      draggedAStep: () => _box != null,
      onStart: (details) => _openBox(details.localPosition),
      onUpdate: _drawBox,
      onEnd: _closeBox,
      // Nothing to close: the recogniser cancels only a press it never
      // accepted, before [_openBox] — a pointer cancelled after it ends the
      // drag through onEnd.
      onCancel: () {},
    ),
  );

  /// Whether a box pressed at [down] has taken its first step at [now]: the
  /// hand has left the box it pressed — its frame's cell, and the row of a
  /// lane's extent it is in across the graph — as every select's does
  /// (F-138-Q1 「누른 상자 벗어나면 시작」).
  bool _boxSteppedAt(Offset down, Offset now) {
    final axis = widget.frameAxis.axis;
    final frames = widget.frameAxis.geometry.value;
    final lane = widget.frameAxis.laneExtent;
    int rowAt(Offset at) => (partAcross(axis, at) / lane).floor();
    return frames.cellAt(partAlong(axis, down)) !=
            frames.cellAt(partAlong(axis, now)) ||
        rowAt(down) != rowAt(now);
  }

  void _openBox(Offset at) => setState(() => _box = _BoxInHand(at));

  /// The box drawn on to where the hand is — and the view panned where the
  /// hand reaches its edge, as under a key carried.
  void _drawBox(DragUpdateDetails details) {
    final box = _box;
    if (box == null) {
      return;
    }
    edgeAutoPanApply(
      context: context,
      globalPosition: details.globalPosition,
      axis: widget.frameAxis.axis,
    );
    setState(() => box.now = details.localPosition);
    _picks.heldBy(box, _painter.keysIn(context.size!));
  }

  /// Let go of: the box goes, and what it picked stays picked.
  void _closeBox() => setState(() => _box = null);

  /// Whether a press at [position] is the picture's: on a handle, on a
  /// key where a key takes a press, or on a line where the pen puts a key
  /// or Alt picks its keys.
  bool _takesPressAt(Offset position) {
    final size = context.size!;
    return _painter.handleAt(position, size) != null ||
        (widget.lanes != null &&
            (_painter.pickedIn(size).handleAt(position) != null ||
                _pivotTakenAt(position) != null ||
                _keyTakenAt(position) != null ||
                _lineTakenAt(position) != null)) ||
        _penAt(position) != null;
  }

  /// The key a press at [position] takes in hand: the one it is on — or,
  /// off every key and off a line the pen puts one on ([_penAt]) or Alt
  /// picks whole ([_lineTakenAt]), inside the box round the keys picked,
  /// the picked key nearest it (I-3 ⑤b).
  LaneGraphKey? _keyTakenAt(Offset position) {
    final size = context.size!;
    return _painter.keyAt(position, size) ??
        (_penAt(position) == null && _lineTakenAt(position) == null
            ? _painter.pickedIn(size).nearest(position)
            : null);
  }

  /// Where the box's anchor point stands, where a press at [position] takes
  /// it — off a line the pen puts a key on ([_penAt]) or Alt picks whole
  /// ([_lineTakenAt]), as a key is taken inside the box ([_keyTakenAt]).
  Offset? _pivotTakenAt(Offset position) =>
      _penAt(position) == null && _lineTakenAt(position) == null
      ? _painter.pickedIn(context.size!).pivotPressedAt(position)
      : null;

  /// The line whose keys a press at [position] picks, every one — with Alt
  /// held (⌥ on a Mac), on its stroke as drawn: AE's Alt-click between two
  /// keys of a line (graph-key-pick-rest ⓑ). Null off every line, and on
  /// one with no key.
  LaneGraphLine? _lineTakenAt(Offset position) {
    if (widget.lanes?.onSelectRows == null || !ModifierKeys.isAltPressed) {
      return null;
    }
    final line = _painter.curveAt(position, context.size!)?.line;
    return line == null || line.lane.keyedFrames.isEmpty ? null : line;
  }

  /// Where a press at [position] puts a key (I-3 ④): the line it lands on
  /// and the frame of its own pressed — with the pen up or Ctrl held (⌘ on
  /// a Mac), where the host takes the ＋; null anywhere else.
  ({LaneGraphLine line, int frame})? _penAt(Offset position) {
    if (widget.lanes?.onCreateKeys == null ||
        !(widget.pen || ModifierKeys.isControlOrCommandPressed)) {
      return null;
    }
    return _painter.curveAt(position, context.size!);
  }

  // A drag the platform cancels once it has started ends as a release does
  // — the recogniser's own rule, and every drag's here (a lane's scrub, a
  // canvas box): what it showed is written.
  void _configure(DragGestureRecognizer recognizer) {
    recognizer
      // A handle is small: it is the one the press went down on.
      ..dragStartBehavior = DragStartBehavior.down
      ..onDown = _pick
      ..onStart = _take
      ..onUpdate = _pull
      ..onCancel = _cancelled
      ..onEnd = (_) => _drop();
  }

  /// Let go of before it moved: a key picked stays picked, as AE's click
  /// leaves it.
  void _cancelled() => _letTheKeyGo(widget.lanes?.onMoveCancel);

  /// A press on a key PICKS it (I-3, AE's graph editor: a click selects the
  /// key) — the key's cell, as the lane selection its row's band makes —
  /// unless the selection holds it already: then it stands, and the drag
  /// carries all of it, as a drag begun inside a band's selection does. A
  /// press inside the box round the keys picked takes one of them so
  /// ([_keyTakenAt]); one on its anchor point takes that.
  ///
  /// ⚠️Mine: the press does not stand the playhead on the key, as a press
  /// on a band does. AE's click on a key leaves the current time where it
  /// is — and a lane stood on is what a graph draws when its group has
  /// none picked ([laneGraphDrawnLanes]): the lines beside it would go.
  void _pick(DragDownDetails details) {
    final lanes = widget.lanes;
    final position = details.localPosition;
    final size = context.size!;
    _pivotGrab = null;
    if (lanes == null || _painter.handleAt(position, size) != null) {
      return;
    }
    if (_painter.pickedIn(size).handleAt(position) case final handle?) {
      setState(() => _keyInHand = _boxTaken(handle, position, size));
      return;
    }
    if (_pivotTakenAt(position) case final pivot?) {
      _pivotGrab = pivot - position;
      return;
    }
    final key = _keyTakenAt(position);
    if (key == null) {
      if (_lineTakenAt(position) case final line?) {
        _picks.everyKeyOf(line);
      } else {
        _putKeyAt(position, lanes);
      }
      return;
    }
    final (:line, :frame, part: _, at: _, mark: _) = key;
    if (ModifierKeys.isShiftPressed) {
      _picks.onTo(line, frame);
    } else if (!laneSelectionPicksKey(
      lanes.selection.value,
      line.layer.id,
      line.lane.laneId,
      frame,
    )) {
      _picks.cellOf(line, frame);
    }
    setState(() => _keyInHand = _KeyInHand(key, position, _painter.fits));
  }

  /// A press on a line where the pen puts a key ([_penAt]) PUTS ONE THERE
  /// (I-3 ④) — the cell pressed picked, as a press on a key picks its own,
  /// and the ＋ pressed on it: the key the button would make there, the
  /// value the line holds kept, and none where one stands already.
  ///
  /// 🗣️I-3-Q2 (유저 2026-10-21): 「곡선 선 위만 (AE · 보이는 만큼)」 — the
  /// mouse's Ctrl+click and the pen's tap alike, on the line as drawn.
  void _putKeyAt(Offset position, TimelineLaneRangeCallbacks lanes) {
    if (_penAt(position) case (:final line, :final frame)) {
      _picks.cellOf(line, frame);
      lanes.onCreateKeys!();
    }
  }

  /// A press on a handle of the box round the keys picked TAKES IT (I-3 ⑥,
  /// AE's transform box): the times of the keys picked and their marks
  /// across the graph held for the stretch — the selection standing as it
  /// is — with the first of them in hand: what holds its row, and says how
  /// far its line's own frames stand from the graph's.
  _KeyInHand _boxTaken(LaneGraphBoxHandle handle, Offset position, Size size) {
    final picked = _painter.pickedIn(size);
    final times = picked.keys.map(
      (key) => TimelineLaneGraphPainter._timeOf(key.line, key.frame).toDouble(),
    );
    final fits = _painter.fits;
    return _KeyInHand(
      picked.keys.first,
      position,
      fits,
      box: (
        handle: handle,
        times: (low: times.reduce(math.min), high: times.reduce(math.max)),
        across: picked.acrossSpan,
        pivot: _pivot ?? laneGraphBoxMiddle,
      ),
      marks: _lift.marksOf(picked.keys, fits),
    );
  }

  /// The hand moved off the key it picked: the selection's move begins —
  /// nothing, where the selection holds nothing to move.
  void _carry(_KeyInHand inHand) {
    final lanes = widget.lanes!;
    if (!lanes.onMoveBegin()) {
      return;
    }
    inHand.moving = true;
    inHand.lifted = _lift.keysOf(inHand);
    inHand.carry = _lift.carryOf(inHand, _painter);
    lanes.onGripTaken?.call(inHand.row);
  }

  /// The selection goes along the frames as far as the hand has, by whole
  /// frames, and the view pans where the hand reaches its edge, as under a
  /// band's drag (D42). Across, its keys' values go as far as the hand
  /// ([_valuesRaised]). With Shift held, one of the two alone; with the
  /// snap on — or off, with Ctrl held — snapped ([LaneGraphCarry]). Both
  /// keys are read at every move, as the canvas reads its modifier: held
  /// before the press and pressed during the drag are one question.
  void _carryTo(_KeyInHand inHand, DragUpdateDetails details) {
    if (!inHand.moving) {
      return;
    }
    if (inHand.box case final box?) {
      _stretchTo(inHand, box, details);
      return;
    }
    edgeAutoPanApply(
      context: context,
      globalPosition: details.globalPosition,
      axis: widget.frameAxis.axis,
    );
    final (:frames, :rise, :snap) = inHand.carry!.carriedBy(
      details.localPosition - inHand.press,
      oneWay: ModifierKeys.isShiftPressed,
      snapping: widget.snap != ModifierKeys.isControlOrCommandPressed,
    );
    if (snap != inHand.snap) {
      setState(() => inHand.snap = snap);
    }
    if (frames == inHand.frames && rise == inHand.rise) {
      return;
    }
    inHand.frames = frames;
    inHand.rise = rise;
    widget.lanes!.onMoveUpdate(frames, values: _valuesRaised(inHand));
  }

  /// The keys the box holds STRETCHED as far as its handle in hand has
  /// been pulled (I-3 ⑥, AE's transform box): along the frames about the
  /// box's other end — its anchor point with Ctrl held (⌘ on a Mac) — and
  /// across a value graph; a corner with Shift held keeps the box's shape,
  /// and one with Ctrl and Alt held (⌥) tapers its side, or with Shift too
  /// moves it (graph-box-handles-more ⓑ ⓒ), and one with Alt alone goes
  /// alone, each key along the frames as far as the one of its marks that
  /// goes the furthest (ⓐ, [laneGraphBoxLandings]) — each mark going where
  /// the box pulled puts it ([laneGraphBoxAcrossOf]). The view pans where
  /// the hand reaches its edge, as under a key carried.
  void _stretchTo(
    _KeyInHand inHand,
    LaneGraphBoxHeld held,
    DragUpdateDetails details,
  ) {
    final axis = widget.frameAxis.axis;
    final frames = widget.frameAxis.geometry.value;
    edgeAutoPanApply(
      context: context,
      globalPosition: details.globalPosition,
      axis: axis,
    );
    final moved = details.localPosition - inHand.press;
    final (:handle, :times, :across, pivot: _) = held;
    final edge = handle.along > 0 ? times.high : times.low;
    final pull = laneGraphBoxPulled(
      held,
      (
        time: laneGraphTimeAt(
          laneGraphAlong(edge, frames) + partAlong(axis, moved),
          frames,
        ),
        across:
            (handle.across > 0 ? across.high : across.low) +
            partAcross(axis, moved),
      ),
      (
        control: ModifierKeys.isControlOrCommandPressed,
        alt: ModifierKeys.isAltPressed,
        shift: ModifierKeys.isShiftPressed,
      ),
    );
    final (:anchor, :factor) = pull.time;
    final shift = TimelineLaneGraphPainter._shiftOf(inHand.key.line);
    widget.lanes!.onMoveUpdate(
      0,
      stretch: pull.alone == null
          ? (anchor: anchor - shift, factor: factor)
          : null,
      landings: pull.alone == null
          ? null
          : laneGraphBoxLandings(held, pull, [
              for (final (:lifted, :time, :across) in inHand.marks)
                (
                  laneId: lifted.laneId,
                  frame: lifted.frame,
                  time: time,
                  across: across,
                ),
            ]),
      values: _lift.valuesOf([
        for (final (:lifted, :time, across: at) in inHand.marks)
          (
            lifted: lifted,
            rise: laneGraphBoxAcrossOf(held, pull, time: time, across: at) - at,
          ),
      ]),
    );
  }

  /// What [inHand]'s lifted keys say once the hand has gone
  /// [_KeyInHand.rise] across the graph — each as far as the hand on its
  /// own range — null where it has not, or lifts none.
  LaneKeyValues? _valuesRaised(_KeyInHand inHand) => inHand.rise == 0
      ? null
      : _lift.valuesOf([
          for (final lifted in inHand.lifted)
            (lifted: lifted, rise: inHand.rise),
        ]);

  /// The key let go of: the move it carried ends by [finished] — landed on
  /// a release, put back on a cancel — and the row it held is let go.
  void _letTheKeyGo(VoidCallback? finished) {
    final inHand = _keyInHand;
    final lanes = widget.lanes;
    if (inHand == null) {
      return;
    }
    setState(() => _keyInHand = null);
    if (lanes == null || finished == null) {
      return;
    }
    reportRangeDragFinished(
      dragging: inHand.moving,
      moving: inHand.moving,
      onMoveFinished: finished,
      releaseGrip: () => lanes.onGripReleased?.call(inHand.row),
    );
  }

  void _take(DragStartDetails details) {
    final key = _keyInHand;
    if (key != null) {
      _carry(key);
      return;
    }
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

  /// The handle follows the hand by as far as the hand has gone — and a key
  /// in hand carries the selection that far, and the box's anchor point in
  /// hand goes where the hand has (graph-box-handles-more ⓓ).
  void _pull(DragUpdateDetails details) {
    if (_pivotGrab case final grab?) {
      final picked = _painter.pickedIn(context.size!);
      setState(() => _pivot = picked.pointOf(details.localPosition + grab));
      return;
    }
    final key = _keyInHand;
    if (key != null) {
      _carryTo(key, details);
      return;
    }
    final inHand = _inHand;
    if (inHand == null) {
      return;
    }
    final handle = inHand.handle;
    final edit = inHand.edit = laneGraphPull(
      handle,
      handle.at + details.localPosition - inHand.press,
      frames: widget.frameAxis.geometry.value,
      axis: widget.frameAxis.axis,
    );
    _edits?.onPreviewKeySides?.call(
      handle.line.layer,
      handle.line.lane,
      handle.frame,
      edit,
    );
  }

  /// Let go of: written where it was pulled to — nothing, where it never
  /// moved; a key's move lands where it was carried.
  void _drop() {
    if (_keyInHand != null) {
      _letTheKeyGo(widget.lanes?.onMoveEnd);
      return;
    }
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
    widget.lanes?.selection.removeListener(_pickedAnew);
    // A picture taken away with a handle in hand never sees its release:
    // what it was showing is dropped once the tree settles — a notifier
    // fired while the tree is torn down would be too soon.
    final end = _edits?.onEndPreview;
    if (_inHand?.edit != null && end != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => end());
    }
    // A key carried lands as a band's drag does when its row is taken
    // away — the move it carried is never left open.
    final key = _keyInHand;
    final lanes = widget.lanes;
    if (key != null && lanes != null) {
      retireRangeDragOnUnmount(
        dragging: key.moving,
        moving: key.moving,
        onMoveEnd: lanes.onMoveEnd,
        releaseGrip: () => lanes.onGripReleased?.call(key.row),
      );
    }
    super.dispose();
  }
}

/// WHAT A PRESS PICKS on a header graph's lines (I-3): the lane selection
/// a key's cell makes, a key picked on to what is picked, a line's every
/// key, and what a box drawn holds — told to the [picture]'s lanes.
class _LaneGraphPicks {
  const _LaneGraphPicks(this.picture);

  final LaneGraphPicture picture;

  /// [line]'s cell on [frame] picked — the lane selection its row's band
  /// makes there.
  void cellOf(LaneGraphLine line, int frame) => picture.lanes!.onSelectUpdate(
    line.layer.id,
    line.lane.laneId,
    frame,
    frame,
    0,
  );

  /// [line]'s key on [frame] picked ON TO what is picked, with Shift held
  /// (🗣️graph-key-pick-rest-Q1, 유저 2026-10-22: 「사각형을 그 키까지
  /// 넓힌다」): the lane selection widened to the key's cell — its frames
  /// to the key's, its lanes to the key's, as the box picks rows
  /// ([heldBy]) — a key picked already staying picked. With nothing
  /// picked, the key's cell alone.
  void onTo(LaneGraphLine line, int frame) {
    final lanes = picture.lanes!;
    final picked = lanes.selection.value;
    if (picked == null || lanes.onSelectRows == null) {
      cellOf(line, frame);
      return;
    }
    final anchor = [...picture.own, ...picture.guests]
        .where(
          (each) =>
              each.layer.id == picked.layerId &&
              each.lane.laneId == picked.laneId,
        )
        .firstOrNull;
    final drawn = TimelineLaneGraphPainter._timeOf(line, frame);
    final at = anchor == null ? drawn : _ownFrameOf(anchor, drawn);
    lanes.onSelectRows!(
      {
        for (final lane in picked.spanLaneIds)
          LaneRowAddress(picked.layerId, lane),
        LaneRowAddress(line.layer.id, line.lane.laneId),
      }.toList(),
      math.min(picked.startIndex, at),
      math.max(picked.endIndexExclusive - 1, at),
    );
  }

  /// Every key of [line] picked: its lane's cells from its first key to its
  /// last, the way the box picks the keys it holds ([heldBy]).
  void everyKeyOf(LaneGraphLine line) {
    final keyed = line.lane.keyedFrames;
    picture.lanes!.onSelectRows!(
      [LaneRowAddress(line.layer.id, line.lane.laneId)],
      keyed.reduce(math.min),
      keyed.reduce(math.max),
    );
  }

  /// What [box] holds, picked: the frames it spans, across the lanes of the
  /// keys inside it — and the selection let go of where it holds none. Of
  /// the lines a cut, the keys of the one cut it began in, in that cut's
  /// own frames: a sweep on a projection row's lane picks so.
  ///
  /// 🗣️I-3-Q3 (유저 2026-10-21): 「레인 칸 선택으로 (상자가 걸친 프레임 ×
  /// 안에 든 키의 레인)」. 🗣️I-3-Q4 (유저 2026-10-22): 「레인 행을 끌 때와
  /// 똑같이」 — the lanes of two layers, or two cuts, picked as a lane drag
  /// across them picks.
  void heldBy(_BoxInHand box, List<LaneGraphKey> keys) {
    final lanes = picture.lanes!;
    final axis = picture.frameAxis.axis;
    final frames = picture.frameAxis.geometry.value;
    final pressed = frames.frameIndexAt(partAlong(axis, box.press));
    final rect = box.rect;
    final held = [
      for (final key in keys)
        if (rect.contains(key.at) &&
            TimelineLaneGraphPainter._reaches(
              key.line,
              pressed - TimelineLaneGraphPainter._shiftOf(key.line),
            ))
          key.line,
    ];
    final rows = {
      for (final line in held) LaneRowAddress(line.layer.id, line.lane.laneId),
    }.toList();
    final anchor = held.isEmpty ? 0 : _ownFrameOf(held.first, pressed);
    final head = held.isEmpty
        ? 0
        : _ownFrameOf(
            held.first,
            frames.frameIndexAt(partAlong(axis, box.now)),
          );
    if (listEquals(rows, box.rows) &&
        anchor == box.anchor &&
        head == box.head) {
      return;
    }
    box
      ..rows = rows
      ..anchor = anchor
      ..head = head;
    if (rows.isEmpty) {
      lanes.onTapClear();
      return;
    }
    lanes.onSelectRows!(rows, anchor, head);
  }

  /// The graph's frame [frame] as one of [line]'s own — held to them, as a
  /// sweep on a cut's lane is held to the cut (`CameraRowReach.ownFrameAt`).
  static int _ownFrameOf(LaneGraphLine line, int frame) =>
      switch (line.reach) {
        null => frame,
        (:final start, :final end) =>
          math.max(start, math.min(frame, end - 1)) - start,
      };
}

/// WHAT A HAND LIFTS of a header graph's own lines (I-3): the keys it
/// picks as they stand, and what they say once raised across the picture
/// [size] big — read off the [picture]'s lines, written as its lanes'
/// value editor writes each.
class _LaneGraphLift {
  const _LaneGraphLift(this.picture, this.size);

  final LaneGraphPicture picture;
  final Size size;

  /// The keys the selection holds on this graph's own lines, as they stand
  /// when [inHand]'s move begins — what the hand raises them from: the
  /// lines draw the move in flight, so they are read before it.
  ///
  /// 🗣️I-3-Q1 B (유저 2026-10-21): 「고른 키 전부 (AE)」 — every key picked
  /// goes as far as the hand on the screen, each line by its own range: the
  /// one it was fitted to when the key was taken. Of a line of two numbers
  /// (a position, a Scale), the one the key in hand is on — 「한 번에 숫자
  /// 하나」, the value scrub's law (10-10).
  ///
  /// ⚠️Mine: a line of one number answers for the key in hand's either way,
  /// and a line of two the first of its own where the key in hand is on a
  /// line of one. A key the graph does not draw — another group's — goes
  /// along the frames alone: it has no range to go across by.
  List<_KeyLifted> keysOf(_KeyInHand inHand) {
    final selection = picture.lanes!.selection.value;
    if (selection == null) {
      return const [];
    }
    return [
      for (final line in picture.own)
        if ((
              line.lane.curve,
              inHand.fits[laneGroupKey(line.layer.id, line.lane.laneId)],
            )
            case (final curve?, final fit?))
          for (final frame in line.lane.keyedFrames)
            if (laneSelectionPicksKey(
              selection,
              line.layer.id,
              line.lane.laneId,
              frame,
            ))
              (
                laneId: line.lane.laneId,
                frame: frame,
                numbers: curve.at(frame.toDouble()),
                part: math.min(inHand.key.part, fit.ranges.length - 1),
                range: fit.ranges[math.min(
                  inHand.key.part,
                  fit.ranges.length - 1,
                )],
              ),
    ];
  }

  /// How the hand carries [inHand]'s key ([LaneGraphCarry]), snapping it
  /// (graph-key-drag-snaps) to every key [painter] marks that the
  /// selection does not carry — read when the move begins, as [keysOf]
  /// reads them — and to the playhead and the ends of the picture's frames.
  LaneGraphCarry carryOf(
    _KeyInHand inHand,
    TimelineLaneGraphPainter painter,
  ) {
    final frameAxis = picture.frameAxis;
    LaneGraphSnapKey snappedBy(LaneGraphKey key) => (
      time: TimelineLaneGraphPainter._timeOf(key.line, key.frame),
      across: partAcross(frameAxis.axis, key.at),
    );
    return LaneGraphCarry(
      axis: frameAxis.axis,
      frames: frameAxis.geometry,
      alongOf: laneGraphAlong,
      key: snappedBy(inHand.key),
      keys: [
        for (final key in painter.keysIn(size))
          if (!painter._picks(key)) snappedBy(key),
      ],
      playhead: frameAxis.playhead,
      frameCount: frameAxis.frameCount,
    );
  }

  /// The marks of [picked] a stretch raises across the graph (I-3 ⑥), each
  /// with its key's numbers and the range its line is fitted to. A speed
  /// graph marks no key, so it boxes none to stretch.
  ///
  /// 🗣️graph-box-handles-scale-keys-Q1 (유저 2026-10-22): 「둘 다 (AE
  /// 그대로)」 — a line of two numbers (a position, a Scale) is stretched
  /// mark by mark, each number on its own range, though a carry moves the
  /// one number in hand (「한 번에 숫자 하나」).
  List<({_KeyLifted lifted, double time, double across})> marksOf(
    List<LaneGraphKey> picked,
    Map<String, LaneGraphFit> fits,
  ) {
    final axis = picture.frameAxis.axis;
    return [
      for (final key in picked)
        if ((
              key.line.lane.curve,
              fits[laneGroupKey(key.line.layer.id, key.line.lane.laneId)],
            )
            case (final curve?, final fit?))
          (
            lifted: (
              laneId: key.line.lane.laneId,
              frame: key.frame,
              numbers: curve.at(key.frame.toDouble()),
              part: key.part,
              range: fit.ranges[key.part],
            ),
            time: TimelineLaneGraphPainter._timeOf(
              key.line,
              key.frame,
            ).toDouble(),
            across: partAcross(axis, key.at),
          ),
    ];
  }

  /// What each of [raised]'s keys says once raised its rise in pixels
  /// across the graph, each on its own range — a carry's all as far, a
  /// stretch's each as far as its mark goes (I-3 ⑥) — null where it raises
  /// none.
  LaneKeyValues? valuesOf(List<({_KeyLifted lifted, double rise})> raised) {
    if (raised.isEmpty) {
      return null;
    }
    final axis = picture.frameAxis.axis;
    final extent = extentAcross(axis, size);
    final values = <String, Map<int, List<double>>>{};
    for (final (
          lifted: (:laneId, :frame, :numbers, :part, :range),
          :rise,
        )
        in raised) {
      // A key's two marks a stretch raises each — a position's x and y —
      // write ONE value between them.
      final value = (values[laneId] ??= {})[frame] ??= [...numbers];
      value[part] += laneGraphValueRise(rise, range, extent, axis);
    }
    return (
      inputs: {
        for (final MapEntry(key: laneId, value: frames) in values.entries)
          laneId: {
            for (final MapEntry(key: frame, :value) in frames.entries)
              frame: value.join(', '),
          },
      },
      scaleLinked: picture.edits?.valueLink?.isOn() ?? false,
    );
  }
}

/// A graph's GRIP (I-89 ③, the mock's 5판): its cross end — the
/// timeline's bottom edge, the sheet's right — pulled to make it taller or
/// shorter, never shorter than its lanes nor taller than an enlarged graph
/// stands (`Math.max(lanes × 28, Math.min(360, …))`). The app's one
/// splitter ([DockEdgeSplitter]): what it cannot use of the travel is the
/// drag's to pay back, and a pull that reaches the view's edge pans it.
class LaneGraphGrip extends StatefulWidget {
  const LaneGraphGrip({
    super.key,
    required this.axis,
    required this.extent,
    required this.least,
    required this.most,
    required this.onResize,
  });

  /// The grid's frame axis: the graph stands across it.
  final Axis axis;

  /// How far the graph reaches across the frames now, and the least and
  /// the most its grip makes it — the least winning where the two cross.
  final double extent;
  final double least;
  final double most;

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
    final next = math.max(
      widget.least,
      math.min(widget.most, _reached + delta),
    );
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
/// and of the graph's edge across them, what their well keeps around the
/// pills, and what stands between the pills and each button (the mock's,
/// 5판).
const double _graphToolsInset = 6;
const double _graphToolsPadding = 2;
const double _graphToolsGap = 6;

/// A graph's own tools, at the view's start (I-89 ③, the mock's 5판): what
/// it plots — its values, or how fast they change — its pen (I-3 ④), its
/// transform box shown or hidden (AE's 「Show Transform Box」), its snap
/// (AE's 「Snap」, graph-key-drag-snaps), and the button that enlarges it
/// over every other row or lets it back (③D).
class LaneGraphTools extends StatelessWidget {
  const LaneGraphTools({
    super.key,
    required this.keyPrefix,
    required this.groupKey,
    required this.mode,
    required this.onPlot,
    required this.enlarged,
    required this.onEnlarge,
    this.pen = false,
    this.onPen,
    this.transformBox = true,
    this.onTransformBox,
    this.snap = false,
    this.onSnap,
  });

  /// The grid's key prefix and the graph's group, which its pills' keys
  /// are made of.
  final String keyPrefix;
  final String groupKey;

  final LaneGraphMode mode;

  /// Null where the host hands the graph no verbs: the pills keep their
  /// place and take no press.
  final ValueChanged<LaneGraphMode>? onPlot;

  /// Whether the graph is the enlarged one — its button on, wearing the
  /// glyph that lets it back, as the mock's does.
  final bool enlarged;

  /// Null where the host hands the graph no verbs, as [onPlot].
  final VoidCallback? onEnlarge;

  /// Whether the graph's pen is up — its button on ([LaneGraph.pen]).
  final bool pen;

  /// Null where the host hands the graph no verbs, as [onPlot].
  final VoidCallback? onPen;

  /// Whether the graph's transform box is shown — its button on
  /// ([LaneGraph.transformBox]).
  final bool transformBox;

  /// Null where the host hands the graph no verbs, as [onPlot].
  final VoidCallback? onTransformBox;

  /// Whether the graph's snap is on — its button on ([LaneGraph.snap]).
  final bool snap;

  /// Null where the host hands the graph no verbs, as [onPlot].
  final VoidCallback? onSnap;

  /// The pills, the pen, the box and the snap are laid out in the room
  /// they are given, but never in less than the three buttons' own.
  static BoxConstraints _roomForTheButtons(BoxConstraints room) =>
      room.copyWith(
        maxWidth: math.max(
          room.maxWidth,
          3 * (_graphToolsGap + AppIconButtonSize.strip.maxWidth),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: AppColors.surface,
        shape: AppShapes.container(AppShapes.wellRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(_graphToolsPadding),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ⚠️Mine: in a view too narrow for every button, the pen, the
            // box and the snap give their width up after the pills — cut
            // where their room ends — and the enlarge button keeps all of
            // its own, as it did before the pen stood beside it.
            Flexible(
              child: ConstraintsTransformBox(
                alignment: AlignmentDirectional.centerStart,
                clipBehavior: Clip.hardEdge,
                constraintsTransform: _roomForTheButtons,
                child: _pillsAndSwitches(strings),
              ),
            ),
            const SizedBox(width: _graphToolsGap),
            AppIconButton(
              keyValue: '$keyPrefix-lane-graph-enlarge-$groupKey',
              tooltip: enlarged
                  ? strings.laneGraphEnlargeOn
                  : strings.laneGraphEnlarge,
              size: AppIconButtonSize.strip,
              isSelected: enlarged,
              icon: Icon(
                enlarged ? Icons.close_fullscreen : Icons.open_in_full,
              ),
              onPressed: onEnlarge,
            ),
          ],
        ),
      ),
    );
  }

  /// The plot's two pills, and the pen, the box and the snap beside them.
  Widget _pillsAndSwitches(AppStrings strings) {
    final onPlot = this.onPlot;
    PillItem pill(LaneGraphMode plotted, String label) => PillItem(
      keyValue: '$keyPrefix-lane-graph-plot-${plotted.name}-$groupKey',
      label: label,
      selected: mode == plotted,
      onTap: onPlot == null ? null : () => onPlot(plotted),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: PillStrip(
            items: [
              pill(LaneGraphMode.value, strings.laneGraphValue),
              pill(LaneGraphMode.speed, strings.laneGraphSpeed),
            ],
          ),
        ),
        const SizedBox(width: _graphToolsGap),
        // ⚠️Mine: Material draws no pen nib (AE's glyph); this one is a pen
        // drawing its line.
        AppIconButton(
          keyValue: '$keyPrefix-lane-graph-pen-$groupKey',
          tooltip: pen ? strings.laneGraphPenOn : strings.laneGraphPen,
          size: AppIconButtonSize.strip,
          isSelected: pen,
          icon: const Icon(Icons.draw),
          onPressed: onPen,
        ),
        const SizedBox(width: _graphToolsGap),
        // ⚠️Mine: AE's glyph is a box with its handles; Material's nearest
        // is the corners of a frame.
        AppIconButton(
          keyValue: '$keyPrefix-lane-graph-box-$groupKey',
          tooltip: transformBox
              ? strings.laneGraphTransformBoxOn
              : strings.laneGraphTransformBox,
          size: AppIconButtonSize.strip,
          isSelected: transformBox,
          icon: const Icon(Icons.crop_free),
          onPressed: onTransformBox,
        ),
        const SizedBox(width: _graphToolsGap),
        // ⚠️Mine: AE's glyph is a magnet, which Material does not draw; this
        // one is two arrows drawn to a line — what a key carried does where
        // it snaps.
        AppIconButton(
          keyValue: '$keyPrefix-lane-graph-snap-$groupKey',
          tooltip: snap ? strings.laneGraphSnapOn : strings.laneGraphSnap,
          size: AppIconButtonSize.strip,
          isSelected: snap,
          icon: const Icon(Icons.vertical_align_center),
          onPressed: onSnap,
        ),
      ],
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
/// The tools are no wider than the view, their pills giving width up
/// first. ⛔No floor of their own for the button: the view never runs
/// narrower than the frame area's two cells (`layerRailFrameReserveExtent`)
/// nor a graph across than its two lanes at least, which leave it whole —
/// a floor here was never reached, and a narrower view is the narrow
/// view's test to catch.
///
/// The tags never stand before the tools' end: no wider than the room the
/// view leaves them on the timeline — the graph's on the sheet — so a long
/// name ends in an ellipsis; never narrower than a tag's dash and pin.
class _LaneGraphCorners extends MultiChildLayoutDelegate {
  _LaneGraphCorners(this.axis, this.geometry) : super(relayout: geometry);

  final Axis axis;

  /// The live geometry the graph is drawn over — read where the corners are
  /// laid, so a widened view moves them without the graph building again
  /// ([TimelineFrameGeometry.viewExtentPx]).
  final ValueListenable<TimelineFrameGeometry> geometry;

  /// The view's extent along the frames; nothing where the host says
  /// nothing, and the view is all of them.
  double get viewportExtent => geometry.value.viewExtentPx;

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
        maxWidth:
            (axis == Axis.horizontal ? view : size.width) -
            2 * _graphToolsInset,
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
      oldDelegate.axis != axis || !identical(oldDelegate.geometry, geometry);
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
          side: BorderSide(color: AppColors.hairline),
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
    final (:layer, :lane, reach: _) = guest;
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
            style: TextStyle(fontSize: 11, color: AppColors.text),
          ),
        ),
        Icon(
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

/// A handle's circle and its ink, and its stem's width (the mock's, 5판).
const double _laneGraphHandleRadius = 4.5;
const double _laneGraphHandleStroke = 1.6;

/// How wide a handle of the box round the keys picked is drawn (I-3 ⑥):
/// as wide as a key's handle.
const double _laneGraphBoxHandleSide = 2 * _laneGraphHandleRadius;
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

/// How fast [curve] moves at [time] — per frame, as AE's speed graph plots
/// it (I-89 ③ 속도) — read inside the stretch between its keys on [from]
/// and [to]: a step ahead, and never on [to] itself, where a hold jumps.
/// Its numbers move as one: at the speed of the point they make, a
/// position's along its path (I-89-Q5 B — AE's one line for a point).
double laneGraphSpeedAt(
  LaneCurve curve,
  double time, {
  required int from,
  required int to,
}) {
  final at = time.clamp(from.toDouble(), to - 2 * _laneGraphSpeedStep);
  return _laneGraphApart(curve.at(at), curve.at(at + _laneGraphSpeedStep)) /
      _laneGraphSpeedStep;
}

/// How far apart two readings of a line stand ([LaneCurve.at]): the
/// distance between the points their numbers make.
double _laneGraphApart(List<double> from, List<double> to) {
  var squares = 0.0;
  for (var part = 0; part < from.length; part += 1) {
    final gap = to[part] - from[part];
    squares += gap * gap;
  }
  return math.sqrt(squares);
}

/// [curve] as a speed graph plots it through [times]: how fast it moves
/// ([laneGraphSpeedAt]) inside each stretch between two of its [keyed]
/// frames, and still before the first and after the last — and on a key,
/// the speed it arrives at and then the one it leaves at, so the line
/// steps where they differ.
Iterable<({double time, double speed})> laneGraphSpeeds(
  LaneCurve curve,
  List<int> keyed,
  Iterable<double> times,
) sync* {
  double inStretch(int index, double time) =>
      index < 0 || index + 1 >= keyed.length
      ? 0
      : laneGraphSpeedAt(
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
    yield (time: time, speed: inStretch(next - 1, time));
    if (next < keyed.length && keyed[next] == time) {
      yield (time: time, speed: inStretch(next, time));
    }
  }
}

/// The speeds [curve] is fitted to across a speed graph: from still — the
/// timeline's foot, the sheet's left — to the fastest it goes between its
/// [keyed] frames, with no spare either way (the mock's, 5판); read on
/// both ends of every stretch and [_laneGraphRangeSteps] times across it.
/// A line that never moves is given 0 to 1.
LaneGraphRange laneGraphSpeedRange(LaneCurve curve, List<int> keyed) {
  var fastest = 0.0;
  for (final (from, to) in neighbourPairs(keyed)) {
    for (var step = 0; step <= _laneGraphRangeSteps; step += 1) {
      final time = from + (to - from) * step / _laneGraphRangeSteps;
      fastest = math.max(
        fastest,
        laneGraphSpeedAt(curve, time, from: from, to: to),
      );
    }
  }
  return (low: 0, high: fastest < 1e-6 ? 1 : fastest);
}

/// Where [value] stands across a graph [extent] deep, fitted to [range]
/// inside its padding: higher up the timeline's graph, and — the sheet
/// being the timeline turned a quarter clockwise, as its key marks are —
/// further right across the sheet's.
///
/// The padding is at most a quarter of the depth (I-89 ③D): the mock's
/// own 16 turned the values over in a graph shallower than 32 — a one-lane
/// group's, gripped down to its lane.
double laneGraphAcross(
  double value,
  LaneGraphRange range,
  double extent,
  Axis axis,
) {
  final share = (value - range.low) / (range.high - range.low);
  final (:padding, :room) = _laneGraphRoom(extent);
  return axis == Axis.horizontal
      ? extent - padding - share * room
      : padding + share * room;
}

/// How far a value fitted to [range] moves for a hand gone [rise] pixels
/// across a graph [extent] deep — [laneGraphAcross] the other way: up the
/// timeline's graph, and right across the sheet's.
double laneGraphValueRise(
  double rise,
  LaneGraphRange range,
  double extent,
  Axis axis,
) {
  final by = rise / _laneGraphRoom(extent).room * (range.high - range.low);
  return axis == Axis.horizontal ? -by : by;
}

/// What a graph [extent] deep keeps clear at either edge across it, and
/// the room between that its values are fitted to.
({double padding, double room}) _laneGraphRoom(double extent) {
  final padding = math.min(_laneGraphPadding, extent / 4);
  return (padding: padding, room: extent - 2 * padding);
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

/// One STROKE of a graph's line (I-3 ④): [line]'s number — in a speed
/// graph, the one speed its numbers move at — through [points], in
/// [color], in dashes for a guest's. What is painted, and so what a pen
/// press is asked against.
typedef _LaneGraphStroke = ({
  LaneGraphLine line,
  List<Offset> points,
  Color color,
  bool dashed,
});

/// Whether [position] is on [stroke] as it is drawn: within half its
/// width of the line through its points — and, a guest's, on one of its
/// dashes ([DashPattern.dashesAt]).
bool _laneGraphStrokeHolds(_LaneGraphStroke stroke, Offset position) {
  final (line: _, :points, color: _, :dashed) = stroke;
  var along = 0.0;
  for (final (from, to) in neighbourPairs(points)) {
    final nearest = nearestOnSegment(position, from, to);
    if ((nearest - position).distance <= _laneGraphStroke / 2 &&
        (!dashed ||
            _laneGraphGuestDashes.dashesAt(
              along + (nearest - from).distance,
            ))) {
      return true;
    }
    along += (to - from).distance;
  }
  return false;
}

/// A KEY a value graph marks (I-89 ③), and a press picks (I-3): [line]'s
/// key on [frame] — the line's own — marked [at] on the line of its
/// [part]-th number, as [mark] says it is.
typedef LaneGraphKey = ({
  LaneGraphLine line,
  int frame,
  int part,
  Offset at,
  KeyMark mark,
});

/// What a line is fitted to across its graph: its keyed frames in order
/// and each number's range — in a speed graph its one speed's.
typedef LaneGraphFit = ({List<int> keyed, List<LaneGraphRange> ranges});

/// A line as a painter plots it: in dashes or not, and what it is fitted
/// to — or null for a line with nothing to draw.
typedef _LaneGraphPlot = ({LaneGraphLine line, bool dashed, LaneGraphFit? fit});

/// A HANDLE a header graph draws (I-89 ③): the [side] of [line]'s key on
/// [frame] — the line's own, where the pull is written — it pulls —
/// [leaving] the key, or arriving at it — drawn [at], its stem from where
/// the key stands at [key]; and the segment it bends, from the key on
/// [frames]' `from` to the next that keeps its time, on the frames the
/// graph is laid along ([LaneGraphLine.reach]), as [mode] plots it: where
/// its 0 and its 1 stand [across] the graph — the two keys' values in a
/// value graph, still and the segment's average speed in a speed graph
/// (I-89-Q5 B).
typedef LaneGraphHandle = ({
  LaneGraphLine line,
  LaneGraphMode mode,
  EaseSide side,
  int frame,
  bool leaving,
  Offset at,
  Offset key,
  ({int from, int to}) frames,
  ({double from, double to}) across,
});

/// What pulling [handle] to [position] writes (I-89 ③): its side's
/// influence and its speed, read back off the segment as the graph — laid
/// along by [frames] — draws it. A value graph reads them off the
/// segment's square ([keyHandleAt], the reading [keyHandlePoint] draws the
/// handle by); a speed graph's speed is as high as the hand, never slower
/// than still, and the way the side went — a speed graph shows how fast,
/// not which way (I-89-Q5 B, AE's).
///
/// A segment with no height to read a speed off — its two keys level
/// across a value graph, a way of no length in a speed graph — takes the
/// influence alone.
KeySidesEdit laneGraphPull(
  LaneGraphHandle handle,
  Offset position, {
  required TimelineFrameGeometry frames,
  required Axis axis,
}) {
  final along = partAlong(axis, position);
  final across = partAcross(axis, position);
  final span = handle.frames;
  final x =
      (laneGraphTimeAt(along, frames) - span.from) / (span.to - span.from);
  final rise = handle.across.to - handle.across.from;
  final level = rise == 0;
  final y = level ? 0.0 : (across - handle.across.from) / rise;
  final leaving = handle.leaving;
  final (:influence, :speed) = switch (handle.mode) {
    LaneGraphMode.value => keyHandleAt(x, y, leaving: leaving),
    LaneGraphMode.speed => (
      influence: keyHandleInfluenceAt(x, leaving: leaving),
      speed: math.max(0.0, y) * (handle.side.speed < 0 ? -1 : 1),
    ),
  };
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
/// key, or how fast they change — over the frames its grid lays, only
/// those its window shows, as its rows of cells draw them
/// ([visibleFrameWindowFor]); and over them, its handles. A key the lane
/// [selection] picks wears its ring, as on its lane's row.
class TimelineLaneGraphPainter extends CustomPainter {
  TimelineLaneGraphPainter({
    required this.own,
    required this.guests,
    required this.frameAxis,
    this.mode = LaneGraphMode.value,
    this.selection,
    this.held = const {},
    this.box,
    this.transformBox = true,
    this.pivot = laneGraphBoxMiddle,
  }) : super(
         repaint: Listenable.merge([
           frameAxis.geometry,
           ?frameAxis.windowBucket,
           ?selection,
         ]),
       );

  final List<LaneGraphLine> own;
  final List<LaneGraphLine> guests;

  /// The frames it draws over.
  final LaneGraphFrames frameAxis;
  final LaneGraphMode mode;

  /// The live lane selection its keys are picked by — null where none is
  /// kept, and no key wears a ring.
  final ValueListenable<TimelineLaneSelection?>? selection;

  /// What a handle or a key in hand holds its lines to, by line
  /// ([laneGroupKey]): the ranges they were fitted to when it was taken
  /// ([fits]). Their keys are read as they stand — a key carried moves
  /// under the hand that carries it.
  final Map<String, LaneGraphFit> held;

  /// The box a drag on the graph's ground is drawing (I-3 ⑤) — in the
  /// ants, standing still ([antsColour]) — or null.
  final Rect? box;

  /// Whether the box round the keys picked stands — drawn, its handles and
  /// the inside of it taking a press ([LaneGraph.transformBox]).
  final bool transformBox;

  /// Where the box's anchor point stands between the keys picked
  /// ([LaneGraphPicked.pivotAt]).
  final LaneGraphBoxPoint pivot;

  Axis get axis => frameAxis.axis;

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

  /// The strokes, the handles and the keys [_readIn] last read, and where
  /// they were read for.
  ({
    Size size,
    TimelineFrameGeometry frames,
    ({int startIndex, int endIndexExclusive}) window,
    List<_LaneGraphStroke> strokes,
    List<LaneGraphHandle> handles,
    List<LaneGraphKey> keys,
  })?
  _read;

  /// How far [line]'s own frames stand from the frames its graph is laid
  /// along: a cut's lane's on its track's ([LaneGraphReach]), none for a
  /// lane on the axis its own frames are counted on.
  static int _shiftOf(LaneGraphLine line) => line.reach?.start ?? 0;

  /// Where [line]'s own [frame] stands on the frames its graph is laid
  /// along ([_shiftOf]).
  static int _timeOf(LaneGraphLine line, int frame) => frame + _shiftOf(line);

  /// Whether [line] is drawn at [time], one of its own: everywhere on the
  /// axis its own frames are counted on — on a track's, a cut's lane from
  /// its first frame of its own to its last, and nowhere past them.
  static bool _reaches(LaneGraphLine line, num time) => switch (line.reach) {
    null => true,
    (:final start, :final end) => time >= 0 && time <= end - start - 1,
  };

  LaneGraphFit? _fitOf(LaneGraphLine line) {
    final curve = line.lane.curve;
    final keyed = [...line.lane.keyedFrames]..sort();
    if (curve == null || keyed.isEmpty) {
      return null;
    }
    return (
      keyed: keyed,
      ranges: held[_lineKey(line)]?.ranges ?? _rangesOf(line, curve, keyed),
    );
  }

  /// Each number's range [line] is fitted to across its graph, read off
  /// its [keyed] frames as they stand.
  List<LaneGraphRange> _rangesOf(
    LaneGraphLine line,
    LaneCurve curve,
    List<int> keyed,
  ) {
    final drawn = _fittedFramesOf(line, keyed);
    return switch (mode) {
      LaneGraphMode.value => laneGraphRanges(curve, drawn),
      LaneGraphMode.speed => [laneGraphSpeedRange(curve, drawn)],
    };
  }

  /// The frames [line]'s fit is read between ([laneGraphRanges]): its
  /// [keyed] frames — a cut's lane's, those among its own frames, and the
  /// last of them where a key past it still bends the line up to there:
  /// fitted to what is drawn of it (「컷 클램핑만 되도록」).
  static List<int> _fittedFramesOf(LaneGraphLine line, List<int> keyed) =>
      switch (line.reach) {
        null => keyed,
        (:final start, :final end) => {
          for (final frame in keyed)
            if (_reaches(line, frame)) frame,
          if (keyed.last > end - start - 1) end - start - 1,
        }.toList(),
      };

  /// The frames [paint] draws — the probe surface for the window's tests,
  /// as the cells painter's is.
  ({int startIndex, int endIndexExclusive}) visibleFrameWindow() {
    final frames = frameAxis.geometry.value;
    return visibleFrameWindowFor(
      bucket: frameAxis.windowBucket,
      viewportMainExtent: frames.viewExtentPx,
      cellExtent: frames.frameCellExtent,
      frameStartIndex: frames.frameStartIndex,
      frameEndIndexExclusive: frames.frameEndIndexExclusive,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    // A pull bends a line past what it was fitted to, and a handle stands
    // off its line: the picture stays inside its own box.
    canvas.clipRect(Offset.zero & size);
    final (:strokes, :handles, :keys) = _readIn(size);
    // The marks go on last, over every line and the handles' stems — and
    // the handles over them (the mock's, 5판).
    for (final (line: _, :points, :color, :dashed) in strokes) {
      _strokeLaneGraphLine(
        canvas,
        Path()..addPolygon(points, false),
        color,
        dashed: dashed,
      );
    }
    final stem = Paint()
      ..strokeWidth = _laneGraphStemStroke
      ..color = AppColors.textDim;
    for (final handle in handles) {
      canvas.drawLine(handle.key, handle.at, stem);
    }
    final ring = selectedLaneKeyRing;
    pickedIn(size).paint(canvas);
    for (final key in keys) {
      paintKeyMark(
        canvas,
        key.mark,
        center: key.at,
        box: _keySizeOf(key),
        standing: axis == Axis.vertical,
        color: layerMarkColor(key.line.layer.mark),
        ring: _picks(key) ? ring : null,
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
    if (box case final box?) {
      paintDashedOutline(
        canvas,
        Path()..addRect(box),
        color: antsColour,
        dashes: antsDashes,
      );
    }
  }

  /// The handle a press at [position] takes on a picture [size] big — on
  /// its circle and its ink ([_drawnLastAt]).
  LaneGraphHandle? handleAt(Offset position, Size size) {
    const reach = _laneGraphHandleRadius + _laneGraphHandleStroke / 2;
    return _drawnLastAt(
      handlesIn(size),
      (handle) => (handle.at - position).distance <= reach,
    );
  }

  /// The key a press at [position] picks on a picture [size] big (I-3) —
  /// in the box its mark is drawn in, stood a quarter turn on the X-sheet
  /// as [paintKeyMark] stands it ([_drawnLastAt]).
  LaneGraphKey? keyAt(Offset position, Size size) =>
      _drawnLastAt(keysIn(size), (key) => _markOf(key).contains(position));

  /// The box [key]'s mark is drawn in.
  Rect _markOf(LaneGraphKey key) {
    final size = _keySizeOf(key);
    final box = axis == Axis.vertical ? size.flipped : size;
    return Rect.fromCenter(
      center: key.at,
      width: box.width,
      height: box.height,
    );
  }

  /// Whether [selection] picks [key] — the key wears its ring.
  bool _picks(LaneGraphKey key) => laneSelectionPicksKey(
    selection?.value,
    key.line.layer.id,
    key.line.lane.laneId,
    key.frame,
  );

  /// The keys [selection] picks of those a picture [size] big marks, and
  /// the box round them.
  LaneGraphPicked pickedIn(Size size) => LaneGraphPicked._(
    keysIn(size).where(_picks).toList(),
    markOf: _markOf,
    axis: axis,
    boxed: transformBox,
    pivot: pivot,
  );

  /// Where a pen press at [position] puts a key on a picture [size] big
  /// (I-3 ④, AE's pen): the line it lands on — on its stroke as drawn and
  /// nowhere round it ([_drawnLastAt], [_laneGraphStrokeHolds]) — and the
  /// frame of the line's own whose cell it is in. Null off every line, and
  /// off the frames the line has.
  ({LaneGraphLine line, int frame})? curveAt(Offset position, Size size) {
    final stroke = _drawnLastAt(
      _readIn(size).strokes,
      (stroke) => _laneGraphStrokeHolds(stroke, position),
    );
    if (stroke == null) {
      return null;
    }
    final frames = frameAxis.geometry.value;
    final cell = frames.cellAt(partAlong(axis, position));
    final line = stroke.line;
    final frame = cell - _shiftOf(line);
    return frames.contains(cell) && _reaches(line, frame)
        ? (line: line, frame: frame)
        : null;
  }

  /// Of [marks], in the order they are drawn, the one drawn last that a
  /// press [hits] — on what is drawn of it, and nowhere round it (F-262:
  /// 「보이는 만큼 존재하도록」). Null where there is none.
  static T? _drawnLastAt<T>(List<T> marks, bool Function(T mark) hits) =>
      marks.reversed.where(hits).firstOrNull;

  /// How big [key]'s mark is: its member lane's — every line is one, its
  /// frame's cell as the axis lays it and a lane's row wide (🗣️F-367-Q3,
  /// 유저 2026-10-17: 「레인 멤버 키와 같은 크기」), as the lane's band asks
  /// it. ↩️The mock's 11px (5판), drawn larger than a lane's were then, and
  /// the smaller once a lane's filled its cell (F-367); then the zoom's
  /// cell, until a lane's key read the cell between its two boundaries
  /// (F-403 opens a cut at 19.2, where a cell is 19 or 20).
  Size _keySizeOf(LaneGraphKey key) {
    final frames = frameAxis.geometry.value;
    return timelineLaneKeyMarkerSize(
      frameAxis.laneExtent,
      frameCellExtent: frames.edgeAt(key.frame + 1) - frames.edgeAt(key.frame),
    );
  }

  /// Every handle a picture [size] big shows, in the order they are drawn.
  /// The probe surface for the handles' tests, as [visibleFrameWindow] is
  /// for the window's.
  List<LaneGraphHandle> handlesIn(Size size) => _readIn(size).handles;

  /// Every key a picture [size] big marks, in the order they are marked —
  /// none in a speed graph (the mock's, 5판). The probe surface for the
  /// keys' tests.
  List<LaneGraphKey> keysIn(Size size) => _readIn(size).keys;

  /// The strokes, the handles and the keys a picture [size] big shows —
  /// read once for where the grid lays its window, since a mouse asks
  /// [handleAt], [keyAt] and [curveAt] on every move it makes over the
  /// picture, and what a press is asked against is what was painted.
  ({
    List<_LaneGraphStroke> strokes,
    List<LaneGraphHandle> handles,
    List<LaneGraphKey> keys,
  })
  _readIn(Size size) {
    final frames = frameAxis.geometry.value;
    final window = visibleFrameWindow();
    if (_read case final last?
        when last.size == size &&
            last.frames == frames &&
            last.window == window) {
      return (strokes: last.strokes, handles: last.handles, keys: last.keys);
    }
    final extent = extentAcross(axis, size);
    final times = laneGraphTimes(window, frames.frameCellExtent).toList();
    final strokes = [
      for (final plot in _plots) ..._strokesOf(plot, frames, times, extent),
    ];
    final handles = [
      for (final plot in _plots) ..._handlesOf(plot, frames, window, extent),
    ];
    final keys = [
      for (final plot in _plots) ..._keysOf(plot, frames, window, extent),
    ];
    _read = (
      size: size,
      frames: frames,
      window: window,
      strokes: strokes,
      handles: handles,
      keys: keys,
    );
    return (strokes: strokes, handles: handles, keys: keys);
  }

  /// The handles [plot]'s line takes (the mock's, 5판): one on each side of
  /// a key that eases toward the key beside it, on every segment [window]
  /// shows some of — in a value graph on a line of one number, where that
  /// side bends their segment ([keyHandlePoint]); in a speed graph on every
  /// line, as far along as the side reaches and as high as the speed it
  /// moves at by its key, a stem's length from it (I-89-Q5 B, AE's speed
  /// graph).
  Iterable<LaneGraphHandle> _handlesOf(
    _LaneGraphPlot plot,
    TimelineFrameGeometry frames,
    ({int startIndex, int endIndexExclusive}) window,
    double extent,
  ) sync* {
    final (:line, dashed: _, :fit) = plot;
    final curve = line.lane.curve;
    if (curve == null ||
        fit == null ||
        (mode == LaneGraphMode.value && curve.parts.length != 1)) {
      return;
    }
    final (:keyed, :ranges) = fit;
    final shift = _shiftOf(line);
    double across(double value) =>
        laneGraphAcross(value, ranges.single, extent, axis);
    for (final span in _laneGraphSegmentsOf(curve, keyed)) {
      if (span.to + shift < window.startIndex ||
          span.from + shift >= window.endIndexExclusive) {
        continue;
      }
      final eases = _laneGraphEasesToward(curve, span);
      if (eases.isEmpty) {
        continue;
      }
      final unit = _unitOf(curve, span);
      final laid = (from: span.from + shift, to: span.to + shift);
      Offset place(double x, double y) => offsetAlong(
        axis,
        along: laneGraphAlong(laid.from + x * (laid.to - laid.from), frames),
        across: across(unit.from + y * (unit.to - unit.from)),
      );
      for (final (:side, :leaving) in eases) {
        final point = keyHandlePoint(
          (influence: side.influence, speed: side.speed),
          leaving: leaving,
        );
        final frame = leaving ? span.from : span.to;
        if (!_takesHandle(line, span, frame, point.x)) {
          continue;
        }
        final end = leaving ? 0.0 : 1.0;
        final (handle, key) = switch (mode) {
          LaneGraphMode.value => (point.y, end),
          LaneGraphMode.speed => (side.speed.abs(), side.speed.abs()),
        };
        yield (
          line: line,
          mode: mode,
          side: side,
          frame: frame,
          leaving: leaving,
          at: place(point.x, handle),
          key: place(end, key),
          frames: laid,
          across: (from: across(unit.from), to: across(unit.to)),
        );
      }
    }
  }

  /// What a handle's height on [span] is measured in, bottom to top: in a
  /// value graph the numbers its two keys hold, a handle's height a share
  /// of the way between them ([keyHandlePoint]); in a speed graph from
  /// standing still to the speed it averages, a side's speed a multiple of
  /// it ([EaseSide.speed]).
  ({double from, double to}) _unitOf(
    LaneCurve curve,
    ({int from, int to}) span,
  ) => switch (mode) {
    LaneGraphMode.value => (
      from: curve.at(span.from.toDouble()).single,
      to: curve.at(span.to.toDouble()).single,
    ),
    LaneGraphMode.speed => (from: 0.0, to: _laneGraphAverageSpeed(curve, span)),
  };

  /// Whether [line] takes the handle of its key at [frame] that bends
  /// [span] as far as [x] of the way along it.
  ///
  /// ⚠️Mine (I-89 ①), read off 「컷 클램핑만 되도록」: a cut's lane takes a
  /// handle where its key is drawn — a handle is its key's — and where it
  /// stands on the cut's own frames, past which nothing of the cut is
  /// drawn.
  static bool _takesHandle(
    LaneGraphLine line,
    ({int from, int to}) span,
    int frame,
    double x,
  ) =>
      _reaches(line, frame) &&
      _reaches(line, span.from + x * (span.to - span.from));

  /// Where [line]'s numbers stand on a graph [extent] across, laid along
  /// [frames] and fitted to [ranges]: its [part]-th number at its own
  /// [time] — laid where the graph's frames put it.
  Offset Function(double time, double number, int part) _placerOf(
    LaneGraphLine line,
    List<LaneGraphRange> ranges,
    TimelineFrameGeometry frames,
    double extent,
  ) {
    final shift = _shiftOf(line);
    return (time, number, part) => offsetAlong(
      axis,
      along: laneGraphAlong(time + shift, frames),
      across: laneGraphAcross(number, ranges[part], extent, axis),
    );
  }

  /// The keys [plot]'s line marks in [window] on a graph [extent] across —
  /// a mark on each of its numbers' lines at every key it draws; none in a
  /// speed graph (the mock's, 5판).
  Iterable<LaneGraphKey> _keysOf(
    _LaneGraphPlot plot,
    TimelineFrameGeometry frames,
    ({int startIndex, int endIndexExclusive}) window,
    double extent,
  ) sync* {
    final (:line, dashed: _, :fit) = plot;
    final curve = line.lane.curve;
    if (curve == null || fit == null || mode == LaneGraphMode.speed) {
      return;
    }
    final at = _placerOf(line, fit.ranges, frames, extent);
    final shift = _shiftOf(line);
    for (final frame in fit.keyed) {
      if (!_reaches(line, frame) ||
          !frameWindowContains(window, frame + shift)) {
        continue;
      }
      for (final (part, number) in curve.at(frame.toDouble()).indexed) {
        yield (
          line: line,
          frame: frame,
          part: part,
          at: at(frame.toDouble(), number, part),
          mark: line.lane.keyMarkAt(frame),
        );
      }
    }
  }

  /// [plot]'s line as it is stroked over [frames], read at [times] on a
  /// graph [extent] across — every number it holds, or in a speed graph the
  /// one speed they move at (I-89-Q5 B) — in dashes for a guest.
  Iterable<_LaneGraphStroke> _strokesOf(
    _LaneGraphPlot plot,
    TimelineFrameGeometry frames,
    List<double> times,
    double extent,
  ) sync* {
    final (:line, :dashed, :fit) = plot;
    final curve = line.lane.curve;
    if (curve == null || fit == null) {
      return;
    }
    final (:keyed, :ranges) = fit;
    final shift = _shiftOf(line);
    final at = _placerOf(line, ranges, frames, extent);
    // The times it is drawn at, its own.
    final own = [
      for (final time in times)
        if (_reaches(line, time - shift)) time - shift,
    ];
    // Each time read once, for all its numbers.
    final readings = switch (mode) {
      LaneGraphMode.value => [
        for (final time in own) (time: time, numbers: curve.at(time)),
      ],
      LaneGraphMode.speed => [
        for (final (:time, :speed) in laneGraphSpeeds(curve, keyed, own))
          (time: time, numbers: [speed]),
      ],
    };
    // A stroke to each range the line is fitted to. ⚠️A speed graph's one
    // takes its first number's colour — mine (I-89-Q5 B): the mock drew a
    // point's speed as two lines, and AE's one line has no colour of ours.
    for (var part = 0; part < ranges.length; part += 1) {
      yield (
        line: line,
        points: [
          for (final (:time, :numbers) in readings)
            at(time, numbers[part], part),
        ],
        color: curve.parts[part],
        dashed: dashed,
      );
    }
  }

  @override
  bool shouldRepaint(TimelineLaneGraphPainter oldDelegate) =>
      oldDelegate.own != own ||
      oldDelegate.guests != guests ||
      oldDelegate.frameAxis != frameAxis ||
      oldDelegate.mode != mode ||
      oldDelegate.selection != selection ||
      oldDelegate.held != held ||
      oldDelegate.box != box ||
      oldDelegate.transformBox != transformBox ||
      oldDelegate.pivot != pivot;
}

/// The segments [curve]'s handles bend, in order: from each of its
/// [keyed] frames to the next — where it walks a path, from each that
/// keeps its time to the next that does ([LaneCurve.way]), the roving
/// ones between passed at the pace those two set.
Iterable<({int from, int to})> _laneGraphSegmentsOf(
  LaneCurve curve,
  List<int> keyed,
) sync* {
  final way = curve.way;
  if (way == null) {
    for (final (from, to) in neighbourPairs(keyed)) {
      yield (from: from, to: to);
    }
    return;
  }
  for (int? from = keyed.first; from != null;) {
    final to = way(from)?.to;
    if (to != null) {
      yield (from: from, to: to);
    }
    from = to;
  }
}

/// How fast [curve] moves over [span] on average — as far as it goes,
/// along its way where it walks one, over the frames it takes: what a
/// side's speed is a multiple of ([EaseSide.speed]).
double _laneGraphAverageSpeed(LaneCurve curve, ({int from, int to}) span) {
  final length =
      curve.way?.call(span.from)?.length ??
      _laneGraphApart(
        curve.at(span.from.toDouble()),
        curve.at(span.to.toDouble()),
      );
  return length / (span.to - span.from);
}

/// The sides of [span]'s two keys that ease toward each other — the
/// first's leaving and the last's arriving, each where it is an ease.
List<({EaseSide side, bool leaving})> _laneGraphEasesToward(
  LaneCurve curve,
  ({int from, int to}) span,
) => [
  if (curve.sides[span.from]?.outgoing case final EaseSide side)
    (side: side, leaving: true),
  if (curve.sides[span.to]?.incoming case final EaseSide side)
    (side: side, leaving: false),
];

/// The keys a lane selection picks on a header graph's picture, in the
/// order they are marked, and the BOX ROUND them (I-3 ⑤b, AE's transform
/// box) — their marks' bounds, where it picks two or more — with its eight
/// handles on it (I-3 ⑥) and its anchor point (graph-box-handles-more ⓓ).
/// A drag begun inside the box carries the keys ([nearest]); one begun on
/// a handle stretches them, one on the anchor point moves it.
///
/// 🗣️I-3-Q5 (유저 2026-10-22): 「경계 상자를 둔다 (AE 변형 상자)」.
class LaneGraphPicked {
  LaneGraphPicked._(
    this.keys, {
    required Rect Function(LaneGraphKey key) markOf,
    required Axis axis,
    required bool boxed,
    required LaneGraphBoxPoint pivot,
  }) : _markOf = markOf,
       _axis = axis,
       _boxed = boxed,
       _pivot = pivot;

  final List<LaneGraphKey> keys;

  /// The box each key's mark is drawn in.
  final Rect Function(LaneGraphKey key) _markOf;
  final Axis _axis;

  /// Whether the graph's transform box is shown ([LaneGraph.transformBox]).
  final bool _boxed;

  /// Where the box's anchor point stands between [keys].
  final LaneGraphBoxPoint _pivot;

  /// How far along the frames the keys stand, the lowest and the highest.
  late final LaneGraphSpan alongSpan = _spanOf(
    (key) => partAlong(_axis, key.at),
  );

  /// How far across the graph the keys stand, the lowest and the highest.
  late final LaneGraphSpan acrossSpan = _spanOf(
    (key) => partAcross(_axis, key.at),
  );

  LaneGraphSpan _spanOf(double Function(LaneGraphKey key) of) {
    final all = keys.map(of);
    return (low: all.reduce(math.min), high: all.reduce(math.max));
  }

  /// The box's ANCHOR POINT (graph-box-handles-more ⓓ, AE's): [_pivot] of
  /// the way between the keys each way — null where there is no box.
  late final Offset? pivotAt = box == null
      ? null
      : offsetAlong(
          _axis,
          along: laneGraphSpanAt(alongSpan, _pivot.along),
          across: laneGraphSpanAt(acrossSpan, _pivot.across),
        );

  /// [at] as a point between the keys — [pivotAt] read back. A way the
  /// keys do not spread, it stands where the anchor point does.
  LaneGraphBoxPoint pointOf(Offset at) => (
    along: laneGraphSpanOf(alongSpan, partAlong(_axis, at)) ?? _pivot.along,
    across:
        laneGraphSpanOf(acrossSpan, partAcross(_axis, at)) ?? _pivot.across,
  );

  /// Where the anchor point stands, where a press at [position] takes it —
  /// on the ring drawn of it; null off it, and where there is no box.
  Offset? pivotPressedAt(Offset position) {
    final at = pivotAt;
    return at != null && _pivotRect(at).contains(position) ? at : null;
  }

  /// The square the anchor point standing [at] is drawn in — a handle's.
  static Rect _pivotRect(Offset at) => Rect.fromCenter(
    center: at,
    width: _laneGraphBoxHandleSide,
    height: _laneGraphBoxHandleSide,
  );

  /// The box round [keys] — null for fewer than two keys: a key of two
  /// numbers is marked twice and is one key — and where the graph's
  /// transform box is hidden.
  late final Rect? box = _boxed ? _boxRound() : null;

  Rect? _boxRound() {
    final distinct = {
      for (final key in keys)
        (key.line.layer.id, key.line.lane.laneId, key.frame),
    };
    return distinct.length < 2
        ? null
        : keys
              .map(_markOf)
              .reduce((round, mark) => round.expandToInclude(mark));
  }

  /// The [box] in the rings' ink, its eight handles on it — filled in the
  /// same ink (I-3 ⑥, AE's transform box) — and its anchor point.
  void paint(Canvas canvas) {
    final round = box;
    if (round == null) {
      return;
    }
    final ring = selectedLaneKeyRing;
    canvas.drawRect(
      round,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ring.width
        ..color = ring.color,
    );
    final ink = Paint()..color = ring.color;
    for (final handle in laneGraphBoxHandles) {
      canvas.drawRect(_handleRect(handle, round), ink);
    }
    // ⚠️Mine: AE's anchor point is a ring crossed by two lines; this one is
    // drawn so, in the ring's ink, as wide as a handle.
    final pivot = _pivotRect(pivotAt!);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ring.width
      ..color = ring.color;
    canvas
      ..drawCircle(pivot.center, pivot.width / 2, stroke)
      ..drawLine(pivot.centerLeft, pivot.centerRight, stroke)
      ..drawLine(pivot.topCenter, pivot.bottomCenter, stroke);
  }

  /// The handle of the [box] a press at [position] takes (I-3 ⑥) — on the
  /// square drawn of it ([TimelineLaneGraphPainter._drawnLastAt]); null off
  /// them, and where there is no box.
  LaneGraphBoxHandle? handleAt(Offset position) {
    final round = box;
    if (round == null) {
      return null;
    }
    return TimelineLaneGraphPainter._drawnLastAt(
      laneGraphBoxHandles,
      (handle) => _handleRect(handle, round).contains(position),
    );
  }

  /// The square [handle] is drawn in on the box [round].
  Rect _handleRect(LaneGraphBoxHandle handle, Rect round) => Rect.fromCenter(
    center: laneGraphBoxHandleAt(handle, round, _axis),
    width: _laneGraphBoxHandleSide,
    height: _laneGraphBoxHandleSide,
  );

  /// The key picked nearest [position] where it is inside the [box] — what
  /// a press there takes in hand: of a line of two numbers, the number
  /// marked nearest it (I-3-Q5). Null outside the box, and where there is
  /// none.
  LaneGraphKey? nearest(Offset position) {
    if (!(box?.contains(position) ?? false)) {
      return null;
    }
    double away(LaneGraphKey key) => (key.at - position).distance;
    return keys.reduce(
      (nearest, key) => away(key) < away(nearest) ? key : nearest,
    );
  }
}

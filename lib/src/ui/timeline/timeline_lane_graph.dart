import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart'
    show DragDownDetails, DragGestureRecognizer, DragStartBehavior;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

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
import '../../services/input/modifier_keys.dart' show ModifierKeys;
import '../dashed_path.dart' show DashPattern, dashesAlong;
import '../input/hit_gate.dart' show HitGate;
import '../layout/device_grid_scroll_controller.dart' show ScrollStill;
import '../text/app_strings.dart' show AppText;
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
import 'lane_graph_seats.dart'
    show LaneGraphLine, laneGraphDrawnLanes, laneGraphGuests;
import 'layer_label_controls.dart' show layerMarkColor;
import 'property_lane_model.dart';
import 'timeline_cells_row_facts.dart' show TimelineCellsRowGrid;
import 'timeline_drag_preview.dart' show timelineDragPreviewLayerFor;
import 'timeline_edge_auto_pan.dart' show edgeAutoPanApply;
import 'timeline_exposure_comma_drag_policy.dart' show commaDragFrameDelta;
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

/// Rows as a grid lays them: [rows] are its rows from [first] on, and
/// [edges] where every one of its rows sits.
typedef TimelineLaidRows = ({
  List<TimelineDisplayRow> rows,
  int first,
  TimelineRowEdges edges,
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
  final (:rows, :first, :edges) = laid;
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
        TimelineLaneGraph(
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
        )
      else ...[
        cells(rows[unit.first - first]),
        if (edges.roomOf(unit.last) > 0)
          acrossBox(axis, edges.roomOf(unit.last)),
      ],
  ];
}

/// The frames a header graph is drawn over (I-89 ③), as the grid's rows of
/// cells lay them: the grid's live geometry, the window over it, the
/// view's extent along them and which way they run — what its picture and
/// its handles read — and how far a lane's row of them reaches across: the
/// room its keys are marked in, which a graph's are marked in too
/// (F-367-Q3).
typedef LaneGraphFrames = ({
  ValueNotifier<TimelineFrameGeometry> geometry,
  ValueListenable<int>? windowBucket,
  double viewportMainExtent,
  Axis axis,
  double laneExtent,
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
    viewportMainExtent: grid.viewportMainExtent,
    axis: grid.axis,
    laneExtent: grid.metrics.layerRowHeight,
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
        grid.frameAxis.viewportMainExtent,
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
  _KeyInHand(this.key, this.press, this.fits);

  final LaneGraphKey key;
  final Offset press;
  final Map<String, LaneGraphFit> fits;
  bool moving = false;
  int frames = 0;

  /// How far across the graph the hand has gone, in pixels — what a value
  /// graph raises the keys by (I-3 ②).
  double rise = 0;

  /// The keys it lifts, as they stood when the move began — none until it
  /// does ([_LaneGraphPictureState._liftedBy]).
  List<_KeyLifted> lifted = const [];

  /// The row the key is on — what a grid holds built while it is carried.
  TimelineRowAddress get row =>
      LaneRowAddress(key.line.layer.id, key.line.lane.laneId);
}

class _LaneGraphPictureState extends State<LaneGraphPicture> {
  _HandleInHand? _inHand;
  _KeyInHand? _keyInHand;

  /// The painter the last build drew with — what a press is asked of.
  late TimelineLaneGraphPainter _painter;

  PropertyLaneEditCallbacks? get _edits => widget.edits;

  @override
  Widget build(BuildContext context) {
    final painter = _painter = TimelineLaneGraphPainter(
      own: widget.own,
      guests: widget.guests,
      frameAxis: widget.frameAxis,
      mode: widget.mode,
      selection: widget.lanes?.selection,
      held: _inHand?.fits ?? _keyInHand?.fits ?? const {},
    );
    return HitGate(
      admits: _takesPressAt,
      child: OwningAxisGrip(
        axis: null,
        configure: _configure,
        child: CustomPaint(painter: painter, child: const SizedBox.expand()),
      ),
    );
  }

  /// Whether a press at [position] is the picture's: on a handle, or on a
  /// key where a key takes a press.
  bool _takesPressAt(Offset position) {
    final size = context.size!;
    return _painter.handleAt(position, size) != null ||
        (widget.lanes != null && _painter.keyAt(position, size) != null);
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
  /// carries all of it, as a drag begun inside a band's selection does.
  ///
  /// ⚠️Mine: the press does not stand the playhead on the key, as a press
  /// on a band does. AE's click on a key leaves the current time where it
  /// is — and a lane stood on is what a graph draws when its group has
  /// none picked ([laneGraphDrawnLanes]): the lines beside it would go.
  void _pick(DragDownDetails details) {
    final lanes = widget.lanes;
    final position = details.localPosition;
    final size = context.size!;
    final key = lanes == null || _painter.handleAt(position, size) != null
        ? null
        : _painter.keyAt(position, size);
    if (lanes == null || key == null) {
      return;
    }
    final (:line, :frame, part: _, at: _, mark: _) = key;
    if (!laneSelectionPicksKey(
      lanes.selection.value,
      line.layer.id,
      line.lane.laneId,
      frame,
    )) {
      lanes.onSelectUpdate(line.layer.id, line.lane.laneId, frame, frame, 0);
    }
    setState(() => _keyInHand = _KeyInHand(key, position, _painter.fits));
  }

  /// The hand moved off the key it picked: the selection's move begins —
  /// nothing, where the selection holds nothing to move.
  void _carry(_KeyInHand inHand) {
    final lanes = widget.lanes!;
    if (!lanes.onMoveBegin()) {
      return;
    }
    inHand.moving = true;
    inHand.lifted = _liftedBy(inHand);
    lanes.onGripTaken?.call(inHand.row);
  }

  /// The selection goes along the frames as far as the hand has, by whole
  /// frames — the band's own step ([commaDragFrameDelta]) — and the view
  /// pans where the hand reaches its edge, as under a band's drag (D42).
  /// Across, its keys' values go as far as the hand ([_valuesRaised]).
  /// With Shift held, one of the two alone ([_keptToOneWay]).
  void _carryTo(_KeyInHand inHand, DragUpdateDetails details) {
    if (!inHand.moving) {
      return;
    }
    final axis = widget.frameAxis.axis;
    edgeAutoPanApply(
      context: context,
      globalPosition: details.globalPosition,
      axis: axis,
    );
    final moved = _keptToOneWay(details.localPosition - inHand.press);
    final frames = commaDragFrameDelta(
      accumulatedDelta: partAlong(axis, moved),
      frameCellExtent: widget.frameAxis.geometry.value.frameCellExtent,
    );
    final rise = partAcross(axis, moved);
    if (frames == inHand.frames && rise == inHand.rise) {
      return;
    }
    inHand.frames = frames;
    inHand.rise = rise;
    widget.lanes!.onMoveUpdate(frames, values: _valuesRaised(inHand));
  }

  /// [moved] as a carry takes it: with Shift held, the one way it has gone
  /// further alone — along the frames or across the graph (I-3 ③, AE's
  /// Shift-drag in its graph editor). Read at every move, as the canvas
  /// reads its modifier: held before the press and pressed during the drag
  /// are one question.
  Offset _keptToOneWay(Offset moved) {
    if (!ModifierKeys.isShiftPressed) {
      return moved;
    }
    final axis = widget.frameAxis.axis;
    final along = partAlong(axis, moved);
    final across = partAcross(axis, moved);
    return along.abs() >= across.abs()
        ? offsetAlong(axis, along: along, across: 0)
        : offsetAlong(axis, along: 0, across: across);
  }

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
  List<_KeyLifted> _liftedBy(_KeyInHand inHand) {
    final selection = widget.lanes!.selection.value;
    if (selection == null) {
      return const [];
    }
    return [
      for (final line in widget.own)
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

  /// What [inHand]'s lifted keys say once the hand has gone
  /// [_KeyInHand.rise] across the graph — each as far as the hand on its
  /// own range — null where it has not, or lifts none.
  LaneKeyValues? _valuesRaised(_KeyInHand inHand) {
    if (inHand.rise == 0 || inHand.lifted.isEmpty) {
      return null;
    }
    final axis = widget.frameAxis.axis;
    final extent = extentAcross(axis, context.size!);
    final inputs = <String, Map<int, String>>{};
    for (final (:laneId, :frame, :numbers, :part, :range) in inHand.lifted) {
      final raised = [...numbers];
      raised[part] += laneGraphValueRise(inHand.rise, range, extent, axis);
      (inputs[laneId] ??= {})[frame] = raised.join(', ');
    }
    return (
      inputs: inputs,
      scaleLinked: widget.edits?.valueLink?.isOn() ?? false,
    );
  }

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
  /// in hand carries the selection that far.
  void _pull(DragUpdateDetails details) {
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
/// pills, and what stands between the pills and the enlarge button (the
/// mock's, 5판).
const double _graphToolsInset = 6;
const double _graphToolsPadding = 2;
const double _graphToolsGap = 6;

/// A graph's own tools, at the view's start (I-89 ③, the mock's 5판): what
/// it plots — its values, or how fast they change — and the button that
/// enlarges it over every other row or lets it back (③D).
class LaneGraphTools extends StatelessWidget {
  const LaneGraphTools({
    super.key,
    required this.keyPrefix,
    required this.groupKey,
    required this.mode,
    required this.onPlot,
    required this.enlarged,
    required this.onEnlarge,
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
        child: Row(
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
  for (var index = 0; index + 1 < keyed.length; index += 1) {
    final from = keyed[index];
    final to = keyed[index + 1];
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

  /// The handles and the keys [_readIn] last read, and where they were
  /// read for.
  ({
    Size size,
    TimelineFrameGeometry frames,
    ({int startIndex, int endIndexExclusive}) window,
    List<LaneGraphHandle> handles,
    List<LaneGraphKey> keys,
  })?
  _read;

  /// How far [line]'s own frames stand from the frames its graph is laid
  /// along: a cut's lane's on its track's ([LaneGraphReach]), none for a
  /// lane on the axis its own frames are counted on.
  static int _shiftOf(LaneGraphLine line) => line.reach?.start ?? 0;

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
      viewportMainExtent: frameAxis.viewportMainExtent,
      cellExtent: frames.frameCellExtent,
      frameStartIndex: frames.frameStartIndex,
      frameEndIndexExclusive: frames.frameEndIndexExclusive,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final frames = frameAxis.geometry.value;
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
    for (final plot in _plots) {
      _drawLine(pass, plot);
    }
    final (:handles, :keys) = _readIn(size);
    final stem = Paint()
      ..strokeWidth = _laneGraphStemStroke
      ..color = AppColors.textDim;
    for (final handle in handles) {
      canvas.drawLine(handle.key, handle.at, stem);
    }
    final picked = selection?.value;
    for (final (:line, :frame, part: _, :at, :mark) in keys) {
      paintKeyMark(
        canvas,
        mark,
        center: at,
        box: _keySize,
        standing: axis == Axis.vertical,
        color: layerMarkColor(line.layer.mark),
        ring:
            laneSelectionPicksKey(
              picked,
              line.layer.id,
              line.lane.laneId,
              frame,
            )
            ? selectedLaneKeyRing
            : null,
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
  LaneGraphKey? keyAt(Offset position, Size size) {
    final box = axis == Axis.vertical ? _keySize.flipped : _keySize;
    return _drawnLastAt(
      keysIn(size),
      (key) => Rect.fromCenter(
        center: key.at,
        width: box.width,
        height: box.height,
      ).contains(position),
    );
  }

  /// Of [marks], in the order they are drawn, the one drawn last that a
  /// press [hits] — on what is drawn of it, and nowhere round it (F-262:
  /// 「보이는 만큼 존재하도록」). Null where there is none.
  static T? _drawnLastAt<T>(List<T> marks, bool Function(T mark) hits) =>
      marks.reversed.where(hits).firstOrNull;

  /// How big a key's mark is: its member lane's — every line is one, a cell
  /// and a lane's row wide at this zoom (🗣️F-367-Q3, 유저 2026-10-17: 「레인
  /// 멤버 키와 같은 크기」). ↩️The mock's 11px (5판), drawn larger than a
  /// lane's were then, and the smaller once a lane's filled its cell
  /// (F-367).
  Size get _keySize => timelineLaneKeyMarkerSize(
    frameAxis.laneExtent,
    frameCellExtent: frameAxis.geometry.value.frameCellExtent,
  );

  /// Every handle a picture [size] big shows, in the order they are drawn.
  /// The probe surface for the handles' tests, as [visibleFrameWindow] is
  /// for the window's.
  List<LaneGraphHandle> handlesIn(Size size) => _readIn(size).handles;

  /// Every key a picture [size] big marks, in the order they are marked —
  /// none in a speed graph (the mock's, 5판). The probe surface for the
  /// keys' tests.
  List<LaneGraphKey> keysIn(Size size) => _readIn(size).keys;

  /// The handles and the keys a picture [size] big shows — read once for
  /// where the grid lays its window, since a mouse asks [handleAt] and
  /// [keyAt] on every move it makes over the picture.
  ({List<LaneGraphHandle> handles, List<LaneGraphKey> keys}) _readIn(
    Size size,
  ) {
    final frames = frameAxis.geometry.value;
    final window = visibleFrameWindow();
    if (_read case final last?
        when last.size == size &&
            last.frames == frames &&
            last.window == window) {
      return (handles: last.handles, keys: last.keys);
    }
    final extent = extentAcross(axis, size);
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
      handles: handles,
      keys: keys,
    );
    return (handles: handles, keys: keys);
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
    for (final span in _segmentsOf(curve, keyed)) {
      if (span.to + shift < window.startIndex ||
          span.from + shift >= window.endIndexExclusive) {
        continue;
      }
      final eases = _easesToward(curve, span);
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
    LaneGraphMode.speed => (from: 0.0, to: _averageSpeed(curve, span)),
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

  /// The segments [curve]'s handles bend, in order: from each of its
  /// [keyed] frames to the next — where it walks a path, from each that
  /// keeps its time to the next that does ([LaneCurve.way]), the roving
  /// ones between passed at the pace those two set.
  static Iterable<({int from, int to})> _segmentsOf(
    LaneCurve curve,
    List<int> keyed,
  ) sync* {
    final way = curve.way;
    if (way == null) {
      for (var index = 0; index + 1 < keyed.length; index += 1) {
        yield (from: keyed[index], to: keyed[index + 1]);
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
  static double _averageSpeed(LaneCurve curve, ({int from, int to}) span) {
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
  static List<({EaseSide side, bool leaving})> _easesToward(
    LaneCurve curve,
    ({int from, int to}) span,
  ) => [
    if (curve.sides[span.from]?.outgoing case final EaseSide side)
      (side: side, leaving: true),
    if (curve.sides[span.to]?.incoming case final EaseSide side)
      (side: side, leaving: false),
  ];

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

  /// Draws [plot]'s line through [pass] — every number it holds, or in a
  /// speed graph the one speed they move at (I-89-Q5 B) — in dashes for a
  /// guest.
  void _drawLine(_LaneGraphPass pass, _LaneGraphPlot plot) {
    final (:line, :dashed, :fit) = plot;
    final curve = line.lane.curve;
    if (curve == null || fit == null) {
      return;
    }
    final (:keyed, :ranges) = fit;
    final (:canvas, :frames, window: _, :times, :extent) = pass;
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
  }

  @override
  bool shouldRepaint(TimelineLaneGraphPainter oldDelegate) =>
      oldDelegate.own != own ||
      oldDelegate.guests != guests ||
      oldDelegate.frameAxis != frameAxis ||
      oldDelegate.mode != mode ||
      oldDelegate.selection != selection ||
      oldDelegate.held != held;
}

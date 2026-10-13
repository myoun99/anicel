import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/input/value_control_pointers.dart';
import 'package:anicel/src/ui/timeline/lane_graph.dart' show LaneGraph;
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show laneGroupKey;
import 'package:anicel/src/ui/timeline/timeline_edge_auto_pan.dart'
    show edgeAutoPanDelta;
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;
import 'package:anicel/src/ui/widgets/dock_edge_splitter.dart'
    show DockEdgeSplitter;

import '../../helpers/named_finders.dart';

/// **I-89 ③ — a header graph is pulled to its height.**
///
/// The mock (5판): the graph's bottom edge dragged — on the sheet, the
/// timeline turned a quarter clockwise, its right edge — never shorter than
/// its lanes. The grip is the app's one splitter (`DockEdgeSplitter`).
void main() {
  tearDown(debugClearValueControlPointers);

  testWidgets('pulled down, it grows by the pull — the moves that come '
      'before the last one\'s rebuild included', (tester) async {
    final s = await _pump(tester);
    await _openTheGraph(tester, s);
    final graph = tester.getRect(_graph('timeline'));
    final grip = tester.getRect(_grip('timeline'));
    expect(
      grip,
      rectMoreOrLessEquals(
        Rect.fromLTRB(
          graph.left,
          graph.bottom - DockEdgeSplitter.thickness,
          graph.right,
          graph.bottom,
        ),
      ),
      reason: 'the grip is its bottom edge, the whole of it',
    );
    final before = graph.height;

    final gesture = await _grab(tester, 'timeline');
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 20));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      tester.getRect(_graph('timeline')).height,
      moreOrLessEquals(before + 60),
    );
    expect(
      _graphOf(s)?.extent,
      moreOrLessEquals(before + 60),
      reason: 'view state, as its twirl is',
    );
  });

  testWidgets('never shorter than its lanes — and the pull it could not use '
      'is the hand\'s to bring back first', (tester) async {
    final s = await _pump(tester);
    await _openTheGraph(tester, s);
    final lanes =
        5 *
        tester
            .getRect(
              find.byKey(
                const ValueKey<String>('timeline-lane-label-draw-position'),
              ),
            )
            .height;

    final gesture = await _grab(tester, 'timeline');
    await gesture.moveBy(const Offset(0, -2000));
    await tester.pump();
    expect(
      tester.getRect(_graph('timeline')).height,
      moreOrLessEquals(lanes),
      reason: 'its five lanes, and no room after them',
    );
    expect(
      _graphOf(s)?.extent,
      moreOrLessEquals(lanes),
      reason: 'the view state holds no graph shorter than its lanes — the '
          'pull past them is the drag\'s, not the row\'s',
    );
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      tester.getRect(_graph('timeline')).height,
      moreOrLessEquals(lanes),
      reason: 'the hand is still far past the edge it pulled to',
    );
  });

  testWidgets('a pull that reaches the foot of the view pans the rows, and '
      'the edge stays under the hand', (tester) async {
    // Rows under the graph: room for the pull to pan into, so an edge that
    // did not take the pan in would fall a long way behind the hand — and
    // rows over it, so it pans all the way before it stands at its most.
    final s = await _pump(tester, under: 12, over: 5);
    await _openTheGraph(tester, s);
    final rows = _rowsScroll(tester);
    rows.jumpTo(0);
    await tester.pump();
    final view = _viewOf(tester, rows);
    final most = view.height - _rowExtent(tester);
    expect(
      rows.maxScrollExtent,
      greaterThan(100),
      reason: '⛔전제: rows to pan into',
    );

    final gesture = await _grab(tester, 'timeline');
    var hand = tester.getRect(_grip('timeline')).center;
    hand = Offset(hand.dx, view.bottom - 4);
    await gesture.moveTo(hand);
    await tester.pump();
    for (var step = 0; step < 6; step += 1) {
      hand = hand.translate(0, 0.5);
      await gesture.moveTo(hand);
      await tester.pump();
    }
    expect(rows.pixels, greaterThan(0), reason: 'the rows panned');
    expect(
      tester.getRect(_grip('timeline')).center.dy,
      moreOrLessEquals(hand.dy, epsilon: 1),
      reason: 'the pan is folded into the pull — the edge did not slide off',
    );
    expect(
      tester.getRect(_graph('timeline')).height,
      lessThan(most),
      reason: '⛔전제: it never stood at its most',
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('at its most it pans no further — the edge stays where the '
      'pull left it, not carried off up the view', (tester) async {
    final s = await _pump(tester, under: 12);
    await _openTheGraph(tester, s);
    final rows = _rowsScroll(tester);
    rows.jumpTo(0);
    await tester.pump();
    final view = _viewOf(tester, rows);
    final most = view.height - _rowExtent(tester);

    final gesture = await _grab(tester, 'timeline');
    var hand = tester.getRect(_grip('timeline')).center;
    hand = Offset(hand.dx, view.bottom - 4);
    Future<void> reach(int steps) async {
      for (var step = 0; step < steps; step += 1) {
        hand = hand.translate(0, 0.5);
        await gesture.moveTo(hand);
        await tester.pump();
      }
    }

    await gesture.moveTo(hand);
    await tester.pump();
    await reach(6);
    expect(
      tester.getRect(_graph('timeline')).height,
      moreOrLessEquals(most),
      reason: 'it stands at its most: the view less its header\'s row',
    );
    final panned = rows.pixels;
    final edge = tester.getRect(_grip('timeline')).center.dy;
    expect(panned, greaterThan(0), reason: 'the pull panned to get there');
    await reach(6);
    expect(
      rows.pixels,
      panned,
      reason: 'nothing left to grow into, nothing to pan for',
    );
    expect(
      tester.getRect(_grip('timeline')).center.dy,
      moreOrLessEquals(edge),
      reason: 'the edge stays where the pull left it',
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('reaching its most partway through a pan, the view pans as '
      'far as it grew and no further — the edge still under the hand', (
    tester,
  ) async {
    final s = await _pump(tester, under: 12);
    await _openTheGraph(tester, s);
    final rows = _rowsScroll(tester);
    rows.jumpTo(0);
    await tester.pump();
    final view = _viewOf(tester, rows);
    final most = view.height - _rowExtent(tester);
    final graphs = s.railView.laneGraphs;
    graphs.value = graphs.value.copyWith(
      open: {
        ...graphs.value.open,
        _transformGroup: _graphOf(s)!.copyWith(extent: most - 60),
      },
    );
    await tester.pump();

    // The one move: from the grip, clear of the band, into the band — the
    // hand's own way taken whole, then the pan that move asks for.
    final hand = Offset(view.left + 40, view.bottom - 4);
    double roomAfterTheHand() =>
        most -
        tester.getRect(_graph('timeline')).height -
        (hand.dy - tester.getRect(_grip('timeline')).center.dy);
    // What is left once the hand's way is taken shrinks one for one as the
    // rows scroll: scrolled so that about five are left.
    rows.jumpTo(rows.pixels + roomAfterTheHand() - 5);
    await tester.pump();
    final room = roomAfterTheHand();
    expect(room, moreOrLessEquals(5, epsilon: 0.5), reason: '⛔전제');
    expect(
      edgeAutoPanDelta(hand.dy - view.top, view.height),
      greaterThan(room + 10),
      reason: '⛔전제: the move asks for a pan well past what is left',
    );
    final before = rows.pixels;

    final gesture = await _grab(tester, 'timeline');
    await gesture.moveTo(hand);
    await tester.pump();
    expect(
      tester.getRect(_graph('timeline')).height,
      moreOrLessEquals(most),
      reason: 'it stands at its most',
    );
    expect(
      rows.pixels,
      moreOrLessEquals(before + room, epsilon: 0.5),
      reason: 'the view panned what it grew, not the whole of the pan',
    );
    expect(
      tester.getRect(_grip('timeline')).center.dy,
      moreOrLessEquals(hand.dy, epsilon: 1),
      reason: 'the edge did not slide off up the view',
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('on the sheet it is pulled out to the right', (tester) async {
    final s = await _pump(tester, tall: true);
    await _openTheGraph(tester, s);
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle-button')),
    );
    await tester.pumpAndSettle();
    final graph = tester.getRect(_graph('xsheet'));
    final grip = tester.getRect(_grip('xsheet'));
    expect(
      grip,
      rectMoreOrLessEquals(
        Rect.fromLTRB(
          graph.right - DockEdgeSplitter.thickness,
          graph.top,
          graph.right,
          graph.bottom,
        ),
      ),
      reason: 'the grip is its right edge, the whole of it',
    );
    final before = graph.width;

    final gesture = await _grab(tester, 'xsheet');
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      tester.getRect(_graph('xsheet')).width,
      moreOrLessEquals(before + 40),
    );
    expect(_graphOf(s)?.extent, moreOrLessEquals(before + 40));
  });
}

const _drawId = LayerId('draw');

String get _transform => transformGroupHeaderLane.laneId;
String get _transformGroup => laneGroupKey(_drawId, _transform);

Finder _graph(String grid) =>
    find.byKey(ValueKey<String>('$grid-lane-graph-$_transformGroup'));

Finder _grip(String grid) =>
    find.byKey(ValueKey<String>('$grid-lane-graph-grip-$_transformGroup'));

LaneGraph? _graphOf(EditorSessionManager s) =>
    s.railView.laneGraphs.value.open[_transformGroup];

/// A press on [grid]'s grip where the view shows it — a mouse, as on the
/// desk.
Future<TestGesture> _grab(WidgetTester tester, String grid) async {
  final grip = tester.getRect(_grip(grid));
  final view = tester.getRect(
    find.byKey(
      ValueKey<String>(
        grid == 'timeline'
            ? 'timeline-frame-scroll-viewport'
            : 'xsheet-frame-vertical-viewport',
      ),
    ),
  );
  final at = grid == 'timeline'
      ? Offset(view.left + 40, grip.center.dy)
      : Offset(grip.center.dx, view.top + 40);
  final gesture = await tester.startGesture(
    at,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  return gesture;
}

/// The timeline's rows' scroll — along the layers.
ScrollPosition _rowsScroll(WidgetTester tester) => tester
    .stateList<ScrollableState>(
      find.ancestor(
        of: find.byKey(
          const ValueKey<String>('timeline-frame-rows-scroll-body'),
        ),
        matching: find.byType(Scrollable),
      ),
    )
    .firstWhere((scroll) => scroll.position.axis == Axis.vertical)
    .position;

/// Where the scroll [position] stands on the screen.
Rect _viewOf(WidgetTester tester, ScrollPosition position) {
  final box = position.context.notificationContext!.findRenderObject()!
      as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// The drawing's lanes twirled open and its Transform graph with them, its
/// Position stood on.
Future<void> _openTheGraph(WidgetTester tester, EditorSessionManager s) async {
  await _tap(tester, 'timeline-lane-toggle-${_drawId.value}');
  await _tap(tester, 'timeline-lane-group-toggle-draw-$_transform');
  await _tap(tester, 'timeline-lane-group-graph-draw-$_transform');
  s.standOnRow(const LaneRowAddress(_drawId, 'position'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String name) async {
  final button = find.named(name);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// [tall]: a surface twice as tall, the dock at its cap of half of it —
/// the sheet stands the rail up as its header. [under], [over]: that many
/// layers' rows under the drawing's, and over it.
Future<EditorSessionManager> _pump(
  WidgetTester tester, {
  bool tall = false,
  int under = 0,
  int over = 0,
}) async {
  await tester.binding.setSurfaceSize(Size(1400, tall ? 2400 : 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: HomePage(initialProject: _project(under: under, over: over)),
    ),
  );
  await tester.pumpAndSettle();
  await tester.drag(
    find.byKey(const ValueKey<String>('dock-resize-bottom')),
    Offset(0, tall ? -1200 : -520),
  );
  await tester.pumpAndSettle();
  return tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
}

/// How tall one of the timeline's rows stands — the drawing's Position
/// lane's.
double _rowExtent(WidgetTester tester) => tester
    .getRect(
      find.byKey(const ValueKey<String>('timeline-lane-label-draw-position')),
    )
    .height;

Layer _empty(String id) =>
    Layer(id: LayerId(id), name: id, frames: const []);

Project _project({required int under, required int over}) => Project(
  id: const ProjectId('graph-grip'),
  name: 'Graph Grip',
  createdAt: DateTime.utc(2026, 10, 11),
  tracks: [
    Track(
      id: const TrackId('t'),
      name: 'V',
      cuts: [
        Cut(
          id: const CutId('c'),
          name: 'C',
          duration: 48,
          canvasSize: const CanvasSize(width: 640, height: 360),
          camera: CutCamera.empty(),
          layers: [
            // The list runs bottom up: these stand under the drawing.
            for (var index = 0; index < under; index += 1)
              _empty('under-$index'),
            Layer(
              id: _drawId,
              name: 'Drawing',
              frames: const [],
              transformTrack: TransformTrack.empty().copyWith(
                position: PropertyTrack<CanvasPoint>()
                    .withKey(0, CanvasPoint(x: 100, y: 50))
                    .withKey(8, CanvasPoint(x: 180, y: 10)),
              ),
            ),
            for (var index = 0; index < over; index += 1)
              _empty('over-$index'),
          ],
        ),
      ],
    ),
  ],
);

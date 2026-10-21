import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
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
import 'package:anicel/src/ui/timeline/lane_graph.dart' show LaneGraphMode;
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show laneGroupKey;
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart'
    show LaneEditPreview;
import 'package:anicel/src/ui/timeline/timeline_lane_graph.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

import '../../helpers/named_finders.dart';

/// **I-89 ③ — a header graph's handle is pulled by the hand.**
///
/// The mock (5판): an ease's handle dragged bends its segment. The press is
/// the handle's — it takes the gesture, as every grip's press does — the
/// pull is shown while the hand is on it, under the hand, and its drop is
/// the key window's write (`a_graph_handle_writes_what_the_key_window_
/// writes_test` pins the scope that write takes).
void main() {
  tearDown(debugClearValueControlPointers);

  testWidgets('pulled, a handle stays under the hand and shows its ease '
      'without writing it — though it bends its line past what the line was '
      'fitted to; let go of, it writes what it showed, in one undo', (
    tester,
  ) async {
    final s = await _pump(tester);
    await _openTheGraph(tester, s);
    final taken = _handleOf(tester, 'timeline');
    final start = _handleOnScreen(tester, 'timeline');
    // Along the segment, and three times its rise across: the far key's
    // value is left behind.
    final (:from, :to) = taken.across;
    final pull = Offset(24, from + 3 * (to - from) - taken.at.dy);

    final gesture = await tester.startGesture(
      // Off its middle: the handle goes as far as the hand does, and does
      // not jump to it.
      start + const Offset(2, 1),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(pull / 2);
    await tester.pump();
    await gesture.moveBy(pull / 2);
    await tester.pump();

    expect(s.dragPreview.value, isA<LaneEditPreview>());
    expect(_leaving(s), const EaseSide(), reason: 'shown, not written');
    final bent = _graphOf(tester, 'timeline').painter.own.single.lane.curve!;
    expect(
      [
        for (var frame = 1; frame < 8; frame += 1)
          bent.at(frame.toDouble()).single,
      ].reduce(math.max),
      greaterThan(45),
      reason: '⛔전제: bent past the far key\'s value, where a line fitted '
          'again would stretch to take it in',
    );
    expect(
      _handleOnScreen(tester, 'timeline'),
      offsetMoreOrLessEquals(start + pull, epsilon: 0.5),
      reason: 'held to the fit it was taken at, the line does not slide '
          'from under the hand that bends it',
    );
    final shown = (s.dragPreview.value! as LaneEditPreview)
        .row!
        .transformTrack
        .rotation
        .keyAt(0)!
        .outgoing;

    await gesture.up();
    await tester.pumpAndSettle();
    expect(s.dragPreview.value, isNull);
    expect(_leaving(s), shown, reason: 'the drop writes what was shown');
    expect(
      (_leaving(s) as EaseSide).influence,
      greaterThan(EaseSide.easeInfluence),
      reason: 'pulled on along the segment',
    );
    s.undo();
    expect(_leaving(s), const EaseSide());
  });

  testWidgets('a pull on a handle is the handle\'s: the rows do not scroll '
      'under it', (tester) async {
    final s = await _pump(tester, under: 12);
    await _openTheGraph(tester, s);
    final rows = _rowsScroll(tester);
    final frames = _framesScroll(tester);
    rows.jumpTo(0);
    await tester.pump();
    expect(rows.maxScrollExtent, greaterThan(100), reason: '⛔전제');
    final start = _handleOnScreen(tester, 'timeline');

    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    for (var step = 0; step < 6; step += 1) {
      await gesture.moveBy(const Offset(-6, 12));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(rows.pixels, 0, reason: 'not along the layers');
    expect(frames.pixels, 0, reason: 'nor along the frames');
    expect(_leaving(s), isNot(const EaseSide()), reason: 'the pull bent it');
  });

  testWidgets('a press beside a handle is not the handle\'s: it falls to what '
      'lies under — a finger that does not draw scrolls the rows there', (
    tester,
  ) async {
    // Where one finger draws, it boxes there as a mouse does (I-3 ⑤).
    AppInput.settings.value = AppInput.settings.value.copyWith(
      touchDragOneFinger: CanvasTouchDragAction.flip,
    );
    addTearDown(
      () => AppInput.settings.value = AppInputSettings.testCorpusBaseline,
    );
    final s = await _pump(tester, under: 12);
    await _openTheGraph(tester, s);
    final rows = _rowsScroll(tester);
    rows.jumpTo(0);
    await tester.pump();
    expect(rows.maxScrollExtent, greaterThan(100), reason: '⛔전제');
    final start = _handleOnScreen(tester, 'timeline');

    final gesture = await tester.startGesture(
      // Past its circle and its ink, 4.5 + 0.8 round.
      start + const Offset(0, 7),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    for (var step = 0; step < 6; step += 1) {
      await gesture.moveBy(const Offset(0, -12));
      await tester.pump();
    }
    expect(s.dragPreview.value, isNot(isA<LaneEditPreview>()));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(rows.pixels, greaterThan(0));
    expect(_leaving(s), const EaseSide());
  });

  testWidgets('a graph shut under the hand drops what its handle showed, and '
      'writes nothing', (tester) async {
    final s = await _pump(tester);
    await _openTheGraph(tester, s);
    final undoable = s.historyManager.canUndo;
    final gesture = await tester.startGesture(
      _handleOnScreen(tester, 'timeline'),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(20, -20));
    await tester.pump();
    expect(s.dragPreview.value, isA<LaneEditPreview>(), reason: '⛔전제');

    final graphs = s.railView.laneGraphs;
    graphs.value = graphs.value.copyWith(open: const {});
    await tester.pump();
    await tester.pump();
    expect(
      s.dragPreview.value,
      isNull,
      reason: 'dropped once the tree settled',
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_leaving(s), const EaseSide());
    expect(s.historyManager.canUndo, undoable);
  });

  testWidgets('in a speed graph too: the handle stays under the hand, and '
      'its drop writes the speed the hand stood at (I-89-Q5 B)', (
    tester,
  ) async {
    final s = await _pump(tester);
    await _openTheGraph(tester, s);
    await _tap(
      tester,
      'timeline-lane-graph-plot-${LaneGraphMode.speed.name}-$_transformGroup',
    );
    // Shown, the pill scrolled the frames: back to their start, where the
    // handle stands clear of the rail's edge.
    _framesScroll(tester).jumpTo(0);
    await tester.pump();
    final taken = _handleOf(tester, 'timeline');
    expect(taken.mode, LaneGraphMode.speed, reason: '⛔전제');
    final start = _handleOnScreen(tester, 'timeline');
    // Straight up, from still to half the segment's average speed.
    final (:from, :to) = taken.across;
    final pull = Offset(0, (to - from) / 2);

    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(pull / 2);
    await tester.pump();
    await gesture.moveBy(pull / 2);
    await tester.pump();
    expect(
      _handleOnScreen(tester, 'timeline'),
      offsetMoreOrLessEquals(start + pull, epsilon: 0.5),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    final written = _leaving(s) as EaseSide;
    expect(written.influence, closeTo(EaseSide.easeInfluence, 1e-6));
    expect(written.speed, closeTo(0.5, 1e-6));
  });

  testWidgets('on the sheet, the timeline turned a quarter clockwise, the '
      'handle stays under the hand too', (tester) async {
    final s = await _pump(tester, tall: true);
    await _openTheGraph(tester, s);
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle-button')),
    );
    await tester.pumpAndSettle();
    final start = _handleOnScreen(tester, 'xsheet');
    const pull = Offset(30, 18);

    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(pull);
    await tester.pump();
    expect(
      _handleOnScreen(tester, 'xsheet'),
      offsetMoreOrLessEquals(start + pull, epsilon: 0.5),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_leaving(s), isNot(const EaseSide()));
  });
}

const _drawId = LayerId('draw');

String get _transformGroup =>
    laneGroupKey(_drawId, transformGroupHeaderLane.laneId);

/// [grid]'s graph as it is drawn: the painter, and the box it paints.
({TimelineLaneGraphPainter painter, RenderBox box}) _graphOf(
  WidgetTester tester,
  String grid,
) {
  final paint = find.descendant(
    of: find.descendant(
      of: find.byKey(ValueKey<String>('$grid-lane-graph-$_transformGroup')),
      matching: find.byType(LaneGraphPicture),
    ),
    matching: find.byType(CustomPaint),
  );
  return (
    painter:
        tester.widget<CustomPaint>(paint).painter! as TimelineLaneGraphPainter,
    box: tester.renderObject<RenderBox>(paint),
  );
}

/// [grid]'s graph's one handle — Rotation's key on 0, leaving.
LaneGraphHandle _handleOf(WidgetTester tester, String grid) {
  final (:painter, :box) = _graphOf(tester, grid);
  final handle = painter.handlesIn(box.size).single;
  expect((handle.frame, handle.leaving), (0, true), reason: '⛔전제');
  return handle;
}

/// Where [grid]'s graph shows its one handle, on the screen.
Offset _handleOnScreen(WidgetTester tester, String grid) =>
    _graphOf(tester, grid).box.localToGlobal(_handleOf(tester, grid).at);

KeyExit _leaving(EditorSessionManager s) => s.requireActiveCut.layers
    .byId(_drawId)!
    .transformTrack
    .rotation
    .keyAt(0)!
    .outgoing;

ScrollPosition _rowsScroll(WidgetTester tester) => _scrollOf(
  tester,
  'timeline-frame-rows-scroll-body',
  Axis.vertical,
);

ScrollPosition _framesScroll(WidgetTester tester) => _scrollOf(
  tester,
  'timeline-frame-rows-scroll-body',
  Axis.horizontal,
);

/// The scroll along [axis] that holds the [key]ed body.
ScrollPosition _scrollOf(WidgetTester tester, String key, Axis axis) => tester
    .stateList<ScrollableState>(
      find.ancestor(
        of: find.byKey(ValueKey<String>(key)),
        matching: find.byType(Scrollable),
      ),
    )
    .firstWhere((scroll) => scroll.position.axis == axis)
    .position;

/// The drawing's lanes twirled open and its Transform graph with them, its
/// Rotation stood on — the one lane the graph then draws.
Future<void> _openTheGraph(WidgetTester tester, EditorSessionManager s) async {
  await _tapNamed(tester, 'timeline-lane-toggle-${_drawId.value}');
  await _tapNamed(
    tester,
    'timeline-lane-group-toggle-draw-${transformGroupHeaderLane.laneId}',
  );
  await _tapNamed(
    tester,
    'timeline-lane-group-graph-draw-${transformGroupHeaderLane.laneId}',
  );
  s.standOnRow(const LaneRowAddress(_drawId, 'rotation'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final button = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _tapNamed(WidgetTester tester, String name) async {
  final button = find.named(name);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// [tall]: a surface twice as tall, the dock at its cap of half of it —
/// the sheet stands the rail up as its header. [under]: that many layers'
/// rows under the drawing's.
Future<EditorSessionManager> _pump(
  WidgetTester tester, {
  bool tall = false,
  int under = 0,
}) async {
  await tester.binding.setSurfaceSize(Size(1400, tall ? 2400 : 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: _project(under: under))),
  );
  await tester.pumpAndSettle();
  await tester.drag(
    find.byKey(const ValueKey<String>('dock-resize-bottom')),
    Offset(0, tall ? -1200 : -520),
  );
  await tester.pumpAndSettle();
  return tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
}

Project _project({required int under}) => Project(
  id: const ProjectId('graph-handle'),
  name: 'Graph Handle',
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
              Layer(
                id: LayerId('under-$index'),
                name: 'Under $index',
                frames: const [],
              ),
            Layer(
              id: _drawId,
              name: 'Drawing',
              frames: const [],
              transformTrack: TransformTrack.empty().copyWith(
                rotation: PropertyTrack<double>()
                    .withKey(0, 0, outgoing: const EaseSide())
                    .withKey(8, 45),
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);

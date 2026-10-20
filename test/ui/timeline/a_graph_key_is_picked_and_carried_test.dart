import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:anicel/src/ui/session/session_row_button_presses.dart';
import 'package:anicel/src/ui/timeline/lane_graph.dart' show LaneGraphMode;
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show laneGroupKey;
import 'package:anicel/src/ui/timeline/timeline_lane_graph.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart'
    show timelineLaneKeyMarkerSize;
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

import '../../helpers/named_finders.dart';

/// **I-3 — a header graph's key is picked and carried, AE's way.**
///
/// 🗣️유저 2026-10-16 (관제가 받음): 「I3은 애초에 ae랑 지금 구조 통일한거라
/// 키 자체 끌어 값/시간바꾸기 이런게 ae에도 있으면 구현이고 아니면 안할거야」.
/// AE's graph editor: a click on a key selects it, and a drag moves it along
/// the time. Here the selection is the lane selection the key's row takes,
/// and the move is that selection's — the lanes' own law (2026-08-08: a key
/// is moved by moving the selection that holds it).
void main() {
  tearDown(debugClearValueControlPointers);

  testWidgets('a press on a key picks its cell in the lane selection, as '
      'its row\'s band would; let go of where it went down, it stays '
      'picked, nothing moves and the playhead stays where it was', (
    tester,
  ) async {
    final s = await _pump(tester);
    await _openTheGraph(tester, s);
    final standing = s.currentFrameIndex;
    expect(s.laneRangeSelection.value, isNull, reason: '⛔전제');

    final gesture = await tester.startGesture(
      _keyOnScreen(tester, 8),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final picked = s.laneRangeSelection.value!;
    expect((picked.layerId, picked.startIndex), (_drawId, 8));
    expect(picked.spanLaneIds, ['rotation']);
    expect(picked.endIndexExclusive, 9);
    expect(_keyedFrames(s), [0, 8]);
    expect(s.currentFrameIndex, standing, reason: 'AE\'s click leaves it');
  });

  testWidgets('dragged along the frames, the key goes with the hand by '
      'whole frames — shown while the hand is on it, landed where it is let '
      'go in one undo, the selection on it', (tester) async {
    final s = await _pump(tester);
    await _openTheGraph(tester, s);
    final cell = _cellExtent(tester);
    final undoable = s.historyManager.canUndo;

    final gesture = await tester.startGesture(
      _keyOnScreen(tester, 8),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(Offset(cell * 1.5, 0));
    await tester.pump();
    await gesture.moveBy(Offset(cell * 1.5, 0));
    await tester.pump();

    expect(_keyedFrames(s), [0, 8], reason: 'shown, not written');
    expect(
      _graphOf(tester).painter.own.single.lane.keyedFrames,
      {0, 11},
      reason: 'the graph draws the move in flight',
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(_keyedFrames(s), [0, 11]);
    expect(s.laneRangeSelection.value!.startIndex, 11);
    s.undo();
    expect(_keyedFrames(s), [0, 8]);
    expect(s.historyManager.canUndo, undoable);
  });

  testWidgets('a key inside the selection carries all of it, as a drag '
      'begun inside a band\'s selection does', (tester) async {
    final s = await _pump(tester);
    await _openTheGraph(tester, s);
    s.updateLaneRangeSelectionDrag(
      layerId: _drawId,
      laneId: 'rotation',
      anchorIndex: 0,
      headIndex: 8,
      spanLaneIds: const ['rotation'],
    );
    await tester.pumpAndSettle();
    final cell = _cellExtent(tester);

    final gesture = await tester.startGesture(
      _keyOnScreen(tester, 8),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(Offset(cell * 2, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_keyedFrames(s), [2, 10]);
    expect(
      (
        s.laneRangeSelection.value!.startIndex,
        s.laneRangeSelection.value!.endIndexExclusive,
      ),
      (2, 11),
    );
  });

  testWidgets('a key picked wears the selection\'s ring, as on its lane\'s '
      'row', (tester) async {
    final s = await _pump(tester);
    await _openTheGraph(tester, s);
    // Any path stroked as the ring is, past the line and the marks.
    final ring = paints
      ..something((method, arguments) {
        if (method != #drawPath) {
          return false;
        }
        // A paint keeps its stroke as a 32-bit float.
        final paint = arguments[1] as Paint;
        return paint.style == PaintingStyle.stroke &&
            (paint.strokeWidth - 8 / 3).abs() < 1e-6;
      });
    expect(_paintOf(tester), isNot(ring), reason: '⛔전제: none picked');

    s.updateLaneRangeSelectionDrag(
      layerId: _drawId,
      laneId: 'rotation',
      anchorIndex: 2,
      headIndex: 4,
      spanLaneIds: const ['rotation'],
    );
    await tester.pumpAndSettle();
    expect(
      _paintOf(tester),
      isNot(ring),
      reason: 'its lane is held, but none of its keys',
    );

    s.updateLaneRangeSelectionDrag(
      layerId: _drawId,
      laneId: 'rotation',
      anchorIndex: 8,
      headIndex: 8,
      spanLaneIds: const ['rotation'],
    );
    await tester.pumpAndSettle();

    expect(_paintOf(tester), ring);
  });

  testWidgets('a finger on a key carries it too: the press is the key\'s, '
      'and the rows do not scroll under it', (tester) async {
    final s = await _pump(tester, under: 12);
    await _openTheGraph(tester, s);
    final cell = _cellExtent(tester);
    final rows = _rowsScroll(tester);
    rows.jumpTo(0);
    await tester.pump();
    expect(rows.maxScrollExtent, greaterThan(100), reason: '⛔전제');

    final gesture = await tester.startGesture(
      _keyOnScreen(tester, 8),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    for (var step = 0; step < 4; step += 1) {
      await gesture.moveBy(Offset(cell / 2, -12));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(rows.pixels, 0);
    expect(_keyedFrames(s), [0, 10]);
  });

  testWidgets('a key is picked in the box its mark is drawn in — as high '
      'as its row, as wide as its cell lets it — and nowhere beside it', (
    tester,
  ) async {
    final s = await _pump(tester);
    await _openTheGraph(tester, s);
    final (:painter, :box) = _graphOf(tester);
    final key = painter.keysIn(box.size).singleWhere((key) => key.frame == 8);
    final mark = timelineLaneKeyMarkerSize(
      painter.frameAxis.laneExtent,
      frameCellExtent: _cellExtent(tester),
    );
    expect(
      mark.width,
      lessThan(mark.height - 2),
      reason: '⛔전제: the mark is narrower than it is high at this zoom',
    );

    LaneGraphKey? at(double along) =>
        painter.keyAt(key.at + Offset(along, 0), box.size);
    expect(at(mark.width / 2 - 1), key, reason: 'on its mark');
    expect(at(mark.width / 2 + 1), isNull, reason: 'beside it, no key');
  });

  testWidgets('a speed graph marks no key, so it has none to pick', (
    tester,
  ) async {
    final s = await _pump(tester);
    await _openTheGraph(tester, s);
    _keyOnScreen(tester, 8); // ⛔전제: the value graph marks it

    SessionRowButtonPresses(s).plotLaneGraph(
      _transformGroup,
      LaneGraphMode.speed,
    );
    await tester.pumpAndSettle();

    final (:painter, :box) = _graphOf(tester);
    expect(painter.keysIn(box.size), isEmpty);
  });
}

const _drawId = LayerId('draw');

String get _transformGroup =>
    laneGroupKey(_drawId, transformGroupHeaderLane.laneId);

List<int> _keyedFrames(EditorSessionManager s) => [
  ...s.requireActiveCut.layers.byId(_drawId)!.transformTrack.rotation.keys
      .keys,
]..sort();

/// The timeline's graph as it is drawn: the painter, and the box it paints.
({TimelineLaneGraphPainter painter, RenderBox box}) _graphOf(
  WidgetTester tester,
) {
  final paint = _paintFinder;
  return (
    painter:
        tester.widget<CustomPaint>(paint).painter! as TimelineLaneGraphPainter,
    box: tester.renderObject<RenderBox>(paint),
  );
}

Finder get _paintFinder => find.descendant(
  of: find.descendant(
    of: find.byKey(ValueKey<String>('timeline-lane-graph-$_transformGroup')),
    matching: find.byType(LaneGraphPicture),
  ),
  matching: find.byType(CustomPaint),
);

RenderObject _paintOf(WidgetTester tester) =>
    tester.renderObject(_paintFinder);

/// How long a frame is along the graph.
double _cellExtent(WidgetTester tester) => _graphOf(
  tester,
).painter.frameAxis.geometry.value.frameCellExtent;

/// Where the graph marks Rotation's key on [frame], on the screen.
Offset _keyOnScreen(WidgetTester tester, int frame) {
  final (:painter, :box) = _graphOf(tester);
  final key = painter
      .keysIn(box.size)
      .singleWhere((key) => key.frame == frame);
  return box.localToGlobal(key.at);
}

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

Future<void> _tapNamed(WidgetTester tester, String name) async {
  final button = find.named(name);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// [under]: that many layers' rows under the drawing's.
Future<EditorSessionManager> _pump(
  WidgetTester tester, {
  int under = 0,
}) async {
  await tester.binding.setSurfaceSize(const Size(1400, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: _project(under: under))),
  );
  await tester.pumpAndSettle();
  await tester.drag(
    find.byKey(const ValueKey<String>('dock-resize-bottom')),
    const Offset(0, -520),
  );
  await tester.pumpAndSettle();
  return tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
}

Project _project({required int under}) => Project(
  id: const ProjectId('graph-key'),
  name: 'Graph Key',
  createdAt: DateTime.utc(2026, 10, 20),
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
                    .withKey(0, 0)
                    .withKey(8, 45),
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);

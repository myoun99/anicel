import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
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
import 'package:anicel/src/ui/session/session_row_button_presses.dart';
import 'package:anicel/src/ui/text/app_strings.dart' show AppText;
import 'package:anicel/src/ui/timeline/lane_graph.dart' show LaneGraphMode;
import 'package:anicel/src/ui/timeline/lane_graph_box_stretch.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show laneGroupKey;
import 'package:anicel/src/ui/timeline/timeline_lane_graph.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart'
    show selectedLaneKeyRing, timelineLaneKeyMarkerSize;
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;
import 'package:anicel/src/ui/widgets/app_icon_button.dart'
    show AppIconButtonFace;

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

  testWidgets('a box drawn on the graph\'s ground picks the frames it spans '
      'on the lanes of the keys inside it, and moves nothing (I-3 ⑤)', (
    tester,
  ) async {
    final s = await _pump(tester);
    await _openTheGraph(tester, s);
    final (:painter, :box) = _graphOf(tester);
    final frames = painter.frameAxis.geometry.value;
    final key = painter.keysIn(box.size).singleWhere((key) => key.frame == 8);
    final press = Offset(frames.edgeAt(6) + 1, key.at.dy + 60);
    expect(
      (painter.keyAt(press, box.size), painter.handleAt(press, box.size)),
      (null, null),
      reason: '⛔전제: the ground',
    );

    final gesture = await tester.startGesture(
      box.localToGlobal(press),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(
      box.localToGlobal(Offset(frames.edgeAt(9) + 1, key.at.dy - 4)),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final picked = s.laneRangeSelection.value!;
    expect(
      (picked.layerId, picked.startIndex, picked.endIndexExclusive),
      (_drawId, 6, 10),
    );
    expect(picked.spanLaneIds, ['rotation']);
    expect(_keyedFrames(s), [0, 8]);
  });

  testWidgets('a box drawn to the view\'s edge pans it on, as a band\'s '
      'select does (D42, F-15)', (tester) async {
    final s = await _pump(tester, duration: 600);
    await _openTheGraph(tester, s);
    final frames = tester
        .stateList<ScrollableState>(
          find.ancestor(
            of: _paintFinder,
            matching: find.byType(Scrollable),
          ),
        )
        .firstWhere((scroll) => scroll.position.axis == Axis.horizontal)
        .position;
    expect(frames.maxScrollExtent, greaterThan(100), reason: '⛔전제');
    final (:painter, :box) = _graphOf(tester);
    final press = Offset(painter.frameAxis.geometry.value.edgeAt(2) + 1, 4);
    expect(
      (painter.keyAt(press, box.size), painter.handleAt(press, box.size)),
      (null, null),
      reason: '⛔전제: the ground',
    );
    final view = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-frame-scroll-viewport')),
    );

    final gesture = await tester.startGesture(
      box.localToGlobal(press),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(Offset(view.right - 2, box.localToGlobal(press).dy));
    await tester.pump();
    await gesture.moveBy(const Offset(1, 0));
    await tester.pump();
    expect(frames.pixels, greaterThan(0));
    await gesture.up();
    await tester.pumpAndSettle();
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

  // I-3 ② — 🗣️I-3-Q1 B (유저 2026-10-21): 「고른 키 전부 (AE)」. AE's value
  // graph: a key dragged up or down changes its value, and every key picked
  // goes with it.
  testWidgets('dragged up the graph, the key\'s value goes with the hand: '
      'under the hand while carried, nothing written until it is let go, '
      'then what was shown is written, in one undo', (tester) async {
    final s = await _pump(tester);
    await _openTheGraph(tester, s);
    final undoable = s.historyManager.canUndo;
    final press = _keyOnScreen(tester, 8);

    final gesture = await tester.startGesture(
      press,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();

    expect(_rotationAt(s, 8), 45, reason: 'shown, not written');
    expect(
      _keyOnScreen(tester, 8),
      offsetMoreOrLessEquals(press + const Offset(0, -40), epsilon: 0.01),
      reason: 'the key stays under the hand',
    );
    final shown = _shownAt(tester, 8).single;
    expect(shown, greaterThan(45), reason: 'up the graph is up the value');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(_keyedFrames(s), [0, 8]);
    expect(_rotationAt(s, 8), closeTo(shown, 1e-9));
    expect(_rotationAt(s, 0), 0, reason: 'a key not picked stays');
    s.undo();
    expect(_rotationAt(s, 8), 45);
    expect(s.historyManager.canUndo, undoable);
  });

  testWidgets('dragged along the frames and up the graph at once, the key '
      'takes its frame and its value together, in one undo', (tester) async {
    final s = await _pump(tester);
    await _openTheGraph(tester, s);
    final cell = _cellExtent(tester);
    final undoable = s.historyManager.canUndo;

    final gesture = await tester.startGesture(
      _keyOnScreen(tester, 8),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(Offset(cell * 1.5, -15));
    await tester.pump();
    await gesture.moveBy(Offset(cell * 1.5, -15));
    await tester.pump();
    final shown = _shownAt(tester, 11).single;
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_keyedFrames(s), [0, 11]);
    expect(shown, greaterThan(45));
    expect(_rotationAt(s, 11), closeTo(shown, 1e-9));
    s.undo();
    expect(_keyedFrames(s), [0, 8]);
    expect(_rotationAt(s, 8), 45);
    expect(s.historyManager.canUndo, undoable);
  });

  testWidgets('every key the selection holds goes as far as the hand on the '
      'screen, each by its line\'s range', (tester) async {
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
    final first = _keyOnScreen(tester, 0);
    final press = _keyOnScreen(tester, 8);

    final gesture = await tester.startGesture(
      press,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();

    expect(
      _keyOnScreen(tester, 0),
      offsetMoreOrLessEquals(first + const Offset(0, -30), epsilon: 0.01),
    );
    expect(
      _keyOnScreen(tester, 8),
      offsetMoreOrLessEquals(press + const Offset(0, -30), epsilon: 0.01),
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(_rotationAt(s, 0), greaterThan(0));
    expect(
      _rotationAt(s, 8) - _rotationAt(s, 0),
      closeTo(45, 1e-9),
      reason: 'one line, one range: one step',
    );
  });

  testWidgets('of a line of two numbers, the one the key in hand is on goes '
      'and the other stays — 「한 번에 숫자 하나」', (tester) async {
    final s = await _pump(
      tester,
      transform: TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>()
            .withKey(0, CanvasPoint(x: 100, y: 300))
            .withKey(8, CanvasPoint(x: 200, y: 50)),
      ),
    );
    await _openTheGraph(tester, s, lane: 'position');

    final press = _keyOnScreen(tester, 8, part: 1);
    final gesture = await tester.startGesture(
      press,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(_up30);
    await tester.pump();
    expect(
      _keyOnScreen(tester, 8, part: 1),
      offsetMoreOrLessEquals(press + _up30, epsilon: 0.01),
      reason: 'each number by its own range: under the hand',
    );
    await gesture.up();
    await tester.pumpAndSettle();
    final down = _transformOf(s).position.keys[8]!.value;
    expect((down.x, down.y > 50), (200, true));

    await _carry(tester, _keyOnScreen(tester, 8), _up30);
    final across = _transformOf(s).position.keys[8]!.value;
    expect((across.x > 200, across.y), (true, down.y));
  });

  testWidgets('a Scale carried keeps to the chain — the transform tool\'s '
      '「배율 연동」, its row\'s chain — as its value editor does: linked, '
      'the other number goes along; unlinked, it stays', (
    tester,
  ) async {
    final s = await _pump(
      tester,
      transform: TransformTrack.empty().copyWith(
        scale: PropertyTrack<CanvasPoint>()
            .withKey(0, CanvasPoint(x: 1, y: 1.5))
            .withKey(8, CanvasPoint(x: 2, y: 1)),
      ),
    );
    await _openTheGraph(tester, s, lane: 'scale');
    final chain = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .transformOptions!;
    expect(chain.value.scaleLinked, isTrue, reason: '⛔전제: the default');

    await _carry(tester, _keyOnScreen(tester, 8), _up30);
    final linked = _transformOf(s).scale.keys[8]!.value;
    expect(linked.x, greaterThan(2));
    expect(linked.y / linked.x, closeTo(0.5, 1e-9));

    s.undo();
    chain.value = chain.value.copyWith(scaleLinked: false);
    await tester.pumpAndSettle();
    await _carry(tester, _keyOnScreen(tester, 8), _up30);
    final unlinked = _transformOf(s).scale.keys[8]!.value;
    expect((unlinked.x > 2, unlinked.y), (true, 1));
  });

  // I-3 ③ — AE's graph editor: Shift-drag keeps a key to the horizontal or
  // the vertical.
  testWidgets('with Shift held, a carry keeps to the one way it has gone '
      'further: mostly up, the key stays on its frame; mostly along, its '
      'value stays', (tester) async {
    final s = await _pump(tester);
    await _openTheGraph(tester, s);
    final cell = _cellExtent(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);

    await _carry(tester, _keyOnScreen(tester, 8), Offset(cell * 2, -cell * 3));
    expect(_keyedFrames(s), [0, 8], reason: 'up alone');
    final raised = _rotationAt(s, 8);
    expect(raised, greaterThan(45));

    await _carry(tester, _keyOnScreen(tester, 8), Offset(cell * 3, -cell * 2));
    expect(_keyedFrames(s), [0, 11], reason: 'along alone');
    expect(_rotationAt(s, 11), raised);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  });

  testWidgets('Shift pressed during a carry keeps it to one way from that '
      'move on — held before the press and pressed during it are one '
      'question', (tester) async {
    final s = await _pump(tester);
    await _openTheGraph(tester, s);
    final cell = _cellExtent(tester);

    final gesture = await tester.startGesture(
      _keyOnScreen(tester, 8),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(Offset(cell * 2, -cell));
    await tester.pump();
    expect(
      _graphOf(tester).painter.own.single.lane.keyedFrames,
      {0, 10},
      reason: '⛔전제: free',
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await gesture.moveBy(Offset(0, -cell * 3));
    await tester.pump();
    expect(_graphOf(tester).painter.own.single.lane.keyedFrames, {0, 8});

    await gesture.up();
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(_keyedFrames(s), [0, 8]);
    expect(_rotationAt(s, 8), greaterThan(45));
  });

  // I-3 ④ — AE's pen in the graph editor: a click on a line adds a key
  // there, the value kept; a Ctrl+click does so without the pen.
  testWidgets('the pen button takes the graph\'s pen up and puts it down, '
      'its face on while it is up', (tester) async {
    final s = await _pump(tester);
    await _openTheGraph(tester, s);
    bool penUp() => s.railView.laneGraphs.value.open[_transformGroup]!.pen;
    AppIconButtonFace face() => tester.widget<AppIconButtonFace>(_penButton);
    expect(penUp(), isFalse, reason: '⛔전제');
    expect(face().isSelected, isFalse);
    expect(face().tooltip, AppText.strings.laneGraphPen);

    await _tapThePen(tester);
    expect(penUp(), isTrue);
    expect(face().isSelected, isTrue);
    expect(face().tooltip, AppText.strings.laneGraphPenOn);

    await _tapThePen(tester);
    expect(penUp(), isFalse);
  });

  testWidgets('with the pen up, a finger on the line puts a key on the '
      'frame it is in — the value the line holds there kept, the key '
      'picked, in one undo', (tester) async {
    final s = await _pump(tester);
    await _openTheGraph(tester, s);
    await _tapThePen(tester);
    final held = _shownAt(tester, 4).single;
    final undoable = s.historyManager.canUndo;

    await _tapTheLine(tester, 4, PointerDeviceKind.touch);

    expect(_keyedFrames(s), [0, 4, 8]);
    expect(_rotationAt(s, 4), closeTo(held, 1e-9));
    final picked = s.laneRangeSelection.value!;
    expect(
      (picked.layerId, picked.startIndex, picked.endIndexExclusive),
      (_drawId, 4, 5),
    );
    expect(picked.spanLaneIds, ['rotation']);
    s.undo();
    expect(_keyedFrames(s), [0, 8]);
    expect(s.historyManager.canUndo, undoable);
  });

  // 🗣️I-3-Q5 (유저 2026-10-22): 「경계 상자를 둔다 (AE 변형 상자)」.
  group('the box round the keys picked (I-3 ⑤b)', () {
    Rect? boxed(WidgetTester tester) {
      final (:painter, :box) = _graphOf(tester);
      return painter.pickedIn(box.size).box;
    }

    /// [at] on the screen, where nothing drawn takes a press.
    Offset bare(WidgetTester tester, Offset at) {
      final (:painter, :box) = _graphOf(tester);
      final local = box.globalToLocal(at);
      expect(
        (
          painter.keyAt(local, box.size),
          painter.handleAt(local, box.size),
        ),
        (null, null),
        reason: '⛔전제: no key and no handle there',
      );
      return at;
    }

    testWidgets('two keys picked are boxed round in the selection\'s ring; '
        'one is not', (tester) async {
      final s = await _pump(tester);
      await _openTheGraph(tester, s);
      expect(boxed(tester), isNull, reason: 'none picked');

      await _pick(tester, s, from: 8);
      expect(boxed(tester), isNull, reason: 'one picked');

      await _pick(tester, s);
      final round = boxed(tester)!;
      final box = _graphOf(tester).box;
      for (final frame in [0, 8]) {
        expect(
          round.contains(box.globalToLocal(_keyOnScreen(tester, frame))),
          isTrue,
        );
      }
      expect(
        _paintOf(tester),
        paints..rect(rect: round, color: selectedLaneKeyRing.color),
      );
    });

    // graph-box-handles-more ⓔ — AE's 「Show Transform Box」.
    testWidgets('the box button hides the box, its handles and the carry '
        'from inside it — a drag there draws a new box — and shows them '
        'again, its face on while it is shown', (tester) async {
      final s = await _pump(tester);
      await _openTheGraph(tester, s);
      await _pick(tester, s);
      bool shown() =>
          s.railView.laneGraphs.value.open[_transformGroup]!.transformBox;
      AppIconButtonFace face() => tester.widget<AppIconButtonFace>(_boxButton);
      final round = boxed(tester)!;
      expect(shown(), isTrue, reason: '⛔전제: shown on a new graph');
      expect(face().isSelected, isTrue);
      expect(face().tooltip, AppText.strings.laneGraphTransformBoxOn);

      await tester.tap(_boxButton);
      await tester.pumpAndSettle();
      expect(shown(), isFalse);
      expect(face().isSelected, isFalse);
      expect(face().tooltip, AppText.strings.laneGraphTransformBox);
      expect(boxed(tester), isNull);
      expect(
        _paintOf(tester),
        isNot(paints..rect(rect: round, color: selectedLaneKeyRing.color)),
      );

      final first = _keyOnScreen(tester, 0);
      final last = _keyOnScreen(tester, 8);
      final cell = _cellExtent(tester);
      await _carry(
        tester,
        bare(tester, Offset(last.dx - cell * 2, first.dy)),
        Offset(cell * 2, 0),
      );
      expect(_keyedFrames(s), [0, 8], reason: 'a box moves nothing');

      await _pick(tester, s);
      await tester.tap(_boxButton);
      await tester.pumpAndSettle();
      expect(shown(), isTrue);
      expect(boxed(tester), round);
    });

    testWidgets('a drag begun on the box\'s ground carries the keys picked, '
        'as one begun on a key does; outside it, a drag draws a new box', (
      tester,
    ) async {
      final s = await _pump(tester);
      await _openTheGraph(tester, s);
      await _pick(tester, s);
      final cell = _cellExtent(tester);
      final first = _keyOnScreen(tester, 0);
      final last = _keyOnScreen(tester, 8);

      await _carry(
        tester,
        bare(tester, Offset(last.dx - cell * 2, first.dy)),
        Offset(cell * 2, 0),
      );
      expect(_keyedFrames(s), [2, 10]);

      final top = _keyOnScreen(tester, 10);
      final outside = bare(tester, top + Offset(cell * 2, 60));
      final box = _graphOf(tester).box;
      expect(
        boxed(tester)!.contains(box.globalToLocal(outside)),
        isFalse,
        reason: '⛔전제',
      );
      final gesture = await tester.startGesture(
        outside,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(top + Offset(-cell, -4));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final picked = s.laneRangeSelection.value!;
      expect((picked.startIndex, picked.endIndexExclusive), (9, 13));
      expect(_keyedFrames(s), [2, 10], reason: 'a box moves nothing');
    });

    testWidgets('of a line of two numbers, the number marked nearest the '
        'press goes — 「한 번에 숫자 하나」', (tester) async {
      // Each number fitted to its own range: x high at 0 and 8, y low there
      // — so the mark farthest from a press by 8's y is the OTHER number,
      // 0's x at the box's top left, and the press takes the nearest.
      final s = await _pump(
        tester,
        transform: TransformTrack.empty().copyWith(
          position: PropertyTrack<CanvasPoint>()
              .withKey(0, CanvasPoint(x: 300, y: 50))
              .withKey(4, CanvasPoint(x: 100, y: 100))
              .withKey(8, CanvasPoint(x: 300, y: 50)),
        ),
      );
      await _openTheGraph(tester, s, lane: 'position');
      await _pick(tester, s, lane: 'position', from: 8);
      expect(boxed(tester), isNull, reason: 'one key, marked twice');
      await _pick(tester, s, lane: 'position');
      final cell = _cellExtent(tester);

      await _carry(
        tester,
        bare(tester, _keyOnScreen(tester, 8, part: 1) - Offset(cell, 0)),
        _up30,
      );
      final moved = _transformOf(s).position.keys[8]!.value;
      expect((moved.x, moved.y > 50), (300, true));
    });

    testWidgets('with the pen up, a press on the line inside the box puts a '
        'key there, as it does outside', (tester) async {
      final s = await _pump(tester);
      await _openTheGraph(tester, s);
      await _pick(tester, s);
      await _tapThePen(tester);
      final box = _graphOf(tester).box;
      expect(
        boxed(tester)!.contains(
          box.globalToLocal(_lineOnScreen(tester, 4)),
        ),
        isTrue,
        reason: '⛔전제',
      );

      await _tapTheLine(tester, 4, PointerDeviceKind.mouse);

      expect(_keyedFrames(s), [0, 4, 8]);
    });
  });

  group('the box\'s handles stretch the keys it holds (I-3 ⑥)', () {
    /// Where [handle] stands on the box round the keys picked, on the
    /// screen.
    Offset handleOnScreen(WidgetTester tester, LaneGraphBoxHandle handle) {
      final (:painter, :box) = _graphOf(tester);
      final round = painter.pickedIn(box.size).box!;
      return box.localToGlobal(
        laneGraphBoxHandleAt(handle, round, Axis.horizontal),
      );
    }

    /// The Rotation keyed 0 on [first] and 45 on [last].
    TransformTrack rotating(int first, int last) =>
        TransformTrack.empty().copyWith(
          rotation: PropertyTrack<double>()
              .withKey(first, 0)
              .withKey(last, 45),
        );

    Map<int, double> rotations(EditorSessionManager s) => {
      for (final MapEntry(key: frame, value: key)
          in _transformOf(s).rotation.keys.entries)
        frame: key.value,
    };

    testWidgets('two keys picked wear eight handles on their box in the '
        'ring\'s ink; a press on one takes the handle, not the key it '
        'stands over, and pulled along it stretches the keys about the '
        'box\'s other end', (tester) async {
      final s = await _pump(tester);
      await _openTheGraph(tester, s);
      await _pick(tester, s);
      final (:painter, :box) = _graphOf(tester);
      final round = painter.pickedIn(box.size).box!;
      final corner = laneGraphBoxHandleAt(
        (along: 1, across: -1),
        round,
        Axis.horizontal,
      );
      expect(
        _paintOf(tester),
        paints
          ..rect(rect: round, color: selectedLaneKeyRing.color)
          ..rect(
            rect: Rect.fromCenter(
              center: round.topLeft,
              width: 9,
              height: 9,
            ),
            color: selectedLaneKeyRing.color,
          ),
      );
      // Inside the corner's square, and inside the key's mark as well.
      final press = corner + const Offset(-2, 2);
      expect(
        painter.keyAt(press, box.size)?.frame,
        8,
        reason: '⛔전제: the key on 8 is under the corner',
      );
      expect(
        painter.pickedIn(box.size).handleAt(press),
        (along: 1, across: -1),
      );

      await _carry(
        tester,
        box.localToGlobal(press),
        Offset(_cellExtent(tester) * 8, 0),
      );

      expect(rotations(s), {0: 0, 16: 45});
      final picked = s.laneRangeSelection.value!;
      expect((picked.startIndex, picked.endIndexExclusive), (0, 17));
    });

    testWidgets('a finger on the start\'s handle stretches them too: the '
        'press is the handle\'s', (tester) async {
      final s = await _pump(tester, transform: rotating(8, 16));
      await _openTheGraph(tester, s);
      await _pick(tester, s, from: 8, to: 16);
      final gesture = await tester.startGesture(
        handleOnScreen(tester, (along: -1, across: 0)),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      await gesture.moveBy(Offset(-_cellExtent(tester) * 8, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(rotations(s), {0: 0, 16: 45});
    });

    testWidgets('with Ctrl held, about the box\'s middle', (tester) async {
      final s = await _pump(tester, transform: rotating(4, 8));
      await _openTheGraph(tester, s);
      await _pick(tester, s, from: 4);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);

      await _carry(
        tester,
        handleOnScreen(tester, (along: 1, across: 0)),
        Offset(_cellExtent(tester) * 2, 0),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      expect(rotations(s), {2: 0, 10: 45});
    });

    // graph-box-handles-more ⓓ — AE's 「an anchor point appears in the
    // center」, dragged to move, 「Ctrl-drag to scale around the anchor
    // point」.
    Offset pivotOnScreen(WidgetTester tester) {
      final (:painter, :box) = _graphOf(tester);
      return box.localToGlobal(painter.pickedIn(box.size).pivotAt!);
    }

    testWidgets('the box\'s anchor point stands between the keys, a ring '
        'in the ring\'s ink; dragged, it goes with the hand, and a Ctrl-pull '
        'stretches about it', (tester) async {
      final s = await _pump(tester, transform: rotating(4, 8));
      await _openTheGraph(tester, s);
      await _pick(tester, s, from: 4);
      final first = _keyOnScreen(tester, 4);
      final last = _keyOnScreen(tester, 8);
      final middle = Offset.lerp(first, last, 0.5)!;
      expect(pivotOnScreen(tester), within(distance: 1e-6, from: middle));
      final box = _graphOf(tester).box;
      expect(
        _paintOf(tester),
        paints..circle(
          x: box.globalToLocal(middle).dx,
          y: box.globalToLocal(middle).dy,
          color: selectedLaneKeyRing.color,
        ),
      );

      // Pressed off its middle, it keeps as far off the hand as it was.
      const off = Offset(2, 2);
      await _carry(tester, middle + off, Offset(first.dx - middle.dx, 0));
      expect(pivotOnScreen(tester).dx, moreOrLessEquals(first.dx));
      expect(rotations(s), {4: 0, 8: 45}, reason: 'it moves no key');

      // Out past the box, it is the hand's still.
      final cell = _cellExtent(tester);
      await _carry(tester, pivotOnScreen(tester), Offset(-cell * 3, 0));
      final outside = pivotOnScreen(tester);
      final (:painter, box: graph) = _graphOf(tester);
      expect(
        graph.globalToLocal(outside).dx,
        lessThan(painter.pickedIn(graph.size).box!.left),
        reason: '⛔전제: out past the box',
      );
      await _carry(tester, outside, Offset(cell * 3, 0));
      expect(pivotOnScreen(tester).dx, moreOrLessEquals(first.dx));

      // A press on it the platform cancels: the next press, on a handle, is
      // the handle's.
      final cancelled = await tester.startGesture(
        pivotOnScreen(tester),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await cancelled.cancel();
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await _carry(
        tester,
        handleOnScreen(tester, (along: 1, across: 0)),
        Offset(cell * 2, 0),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(rotations(s), {4: 0, 10: 45});
    });

    testWidgets('a carry keeps the anchor point where the hand put it; '
        'picked anew, it is back in the middle', (tester) async {
      final s = await _pump(tester, transform: rotating(4, 8));
      await _openTheGraph(tester, s);
      await _pick(tester, s, from: 4);
      final first = _keyOnScreen(tester, 4);
      final middle = pivotOnScreen(tester);
      await _carry(tester, middle, Offset(first.dx - middle.dx, 0));

      final cell = _cellExtent(tester);
      await _carry(tester, _keyOnScreen(tester, 8), Offset(cell * 2, 0));
      expect(rotations(s), {6: 0, 10: 45}, reason: '⛔전제');
      expect(
        pivotOnScreen(tester).dx,
        moreOrLessEquals(_keyOnScreen(tester, 6).dx),
      );

      s.laneRangeSelection.value = null;
      await _pick(tester, s, from: 6, to: 10);
      expect(
        pivotOnScreen(tester),
        within(
          distance: 1e-6,
          from: Offset.lerp(
            _keyOnScreen(tester, 6),
            _keyOnScreen(tester, 10),
            0.5,
          )!,
        ),
      );
    });

    testWidgets('the top\'s handle pulled up stretches the values about the '
        'bottom: the key there stays, the other goes up, and none moves '
        'along the frames', (tester) async {
      final s = await _pump(tester);
      await _openTheGraph(tester, s);
      await _pick(tester, s);

      await _carry(
        tester,
        handleOnScreen(tester, (along: 0, across: -1)),
        _up30,
      );

      expect(_keyedFrames(s), [0, 8]);
      expect(_rotationAt(s, 0), 0);
      expect(_rotationAt(s, 8), greaterThan(45));
    });

    testWidgets('with Shift held, a corner pulled along keeps the box\'s '
        'shape: the values stretch as far as the frames', (tester) async {
      final s = await _pump(tester);
      await _openTheGraph(tester, s);
      await _pick(tester, s);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);

      await _carry(
        tester,
        handleOnScreen(tester, (along: 1, across: -1)),
        Offset(_cellExtent(tester) * 8, 0),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      expect(_keyedFrames(s), [0, 16]);
      expect(_rotationAt(s, 0), 0);
      expect(_rotationAt(s, 16), greaterThan(45));
    });

    testWidgets('pulled past the box\'s other end, the keys turn about it '
        'and run the other way in time — AE\'s', (tester) async {
      final s = await _pump(tester, transform: rotating(4, 8));
      await _openTheGraph(tester, s);
      await _pick(tester, s, from: 4);

      await _carry(
        tester,
        handleOnScreen(tester, (along: 1, across: 0)),
        Offset(-_cellExtent(tester) * 8, 0),
      );

      expect(rotations(s), {0: 45, 4: 0});
    });

    // 🗣️graph-box-handles-scale-keys-Q1 (유저 2026-10-22): 「둘 다 (AE
    // 그대로)」.
    testWidgets('of a line of two numbers, the top\'s handle stretches both: '
        'each mark as far as the box, on its own number\'s range', (
      tester,
    ) async {
      final s = await _pump(
        tester,
        transform: TransformTrack.empty().copyWith(
          position: PropertyTrack<CanvasPoint>()
              .withKey(0, CanvasPoint(x: 100, y: 300))
              .withKey(8, CanvasPoint(x: 200, y: 50)),
        ),
      );
      await _openTheGraph(tester, s, lane: 'position');
      await _pick(tester, s, lane: 'position');

      await _carry(
        tester,
        handleOnScreen(tester, (along: 0, across: -1)),
        _up30,
      );

      final keys = _transformOf(s).position.keys;
      final (first, last) = (keys[0]!.value, keys[8]!.value);
      // x runs 100 → 200 and y 300 → 50: 0's y and 8's x stand at the
      // box's top and go up, 0's x and 8's y at its bottom and stay.
      expect((first.x, last.y), (100, 50));
      expect((first.y > 300, last.x > 200), (true, true));
      expect(
        (first.y - 300) / (last.x - 200),
        closeTo(250 / 100, 0.1),
        reason: 'the same rise on the screen, each on its own range',
      );
    });
  });
}

/// The [lane]'s keys from [from] to [to] picked — the Rotation's on 0
/// and 8, where not told.
Future<void> _pick(
  WidgetTester tester,
  EditorSessionManager s, {
  String lane = 'rotation',
  int from = 0,
  int to = 8,
}) async {
  s.updateLaneRangeSelectionDrag(
    layerId: _drawId,
    laneId: lane,
    anchorIndex: from,
    headIndex: to,
    spanLaneIds: [lane],
  );
  await tester.pumpAndSettle();
}

Finder get _penButton =>
    find.byKey(ValueKey<String>('timeline-lane-graph-pen-$_transformGroup'));

/// A tap on the graph's pen button.
Future<void> _tapThePen(WidgetTester tester) async {
  await tester.tap(_penButton);
  await tester.pumpAndSettle();
}

Finder get _boxButton =>
    find.byKey(ValueKey<String>('timeline-lane-graph-box-$_transformGroup'));

/// A tap of [kind] on the graph's line at [frame].
Future<void> _tapTheLine(
  WidgetTester tester,
  int frame,
  PointerDeviceKind kind,
) async {
  await tester.tapAt(_lineOnScreen(tester, frame.toDouble()), kind: kind);
  await tester.pumpAndSettle();
}

/// Where the graph draws its lane's line at [time], on the screen.
Offset _lineOnScreen(WidgetTester tester, double time) {
  final (:painter, :box) = _graphOf(tester);
  final line = painter.own.single;
  final fit = painter.fits[laneGroupKey(line.layer.id, line.lane.laneId)]!;
  return box.localToGlobal(
    Offset(
      laneGraphAlong(time, painter.frameAxis.geometry.value),
      laneGraphAcross(
        line.lane.curve!.at(time).single,
        fit.ranges.single,
        box.size.height,
        Axis.horizontal,
      ),
    ),
  );
}

/// A press on the key at [at], carried [by] and let go.
Future<void> _carry(WidgetTester tester, Offset at, Offset by) async {
  final gesture = await tester.startGesture(
    at,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await gesture.moveBy(by);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

const _drawId = LayerId('draw');

/// Thirty pixels up the graph.
const _up30 = Offset(0, -30);

String get _transformGroup =>
    laneGroupKey(_drawId, transformGroupHeaderLane.laneId);

TransformTrack _transformOf(EditorSessionManager s) =>
    s.requireActiveCut.layers.byId(_drawId)!.transformTrack;

List<int> _keyedFrames(EditorSessionManager s) => [
  ..._transformOf(s).rotation.keys.keys,
]..sort();

double _rotationAt(EditorSessionManager s, int frame) =>
    _transformOf(s).rotation.keys[frame]!.value;

/// The numbers the graph's line shows on [frame] — what a carry in flight
/// shows there.
List<double> _shownAt(WidgetTester tester, int frame) =>
    _graphOf(tester).painter.own.single.lane.curve!.at(frame.toDouble());

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

/// Where the graph marks its lane's key on [frame] — of its numbers, the
/// [part]th's — on the screen.
Offset _keyOnScreen(WidgetTester tester, int frame, {int part = 0}) {
  final (:painter, :box) = _graphOf(tester);
  final key = painter
      .keysIn(box.size)
      .singleWhere((key) => key.frame == frame && key.part == part);
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
/// [lane] stood on — the one lane the graph then draws.
///
/// Pulled taller than it opens: a line's top stands about where the tools
/// in the view's near corner end, and the key on 8 is that top — half under
/// them once the pen joined them (I-3 ④).
Future<void> _openTheGraph(
  WidgetTester tester,
  EditorSessionManager s, {
  String lane = 'rotation',
}) async {
  await _tapNamed(tester, 'timeline-lane-toggle-${_drawId.value}');
  await _tapNamed(
    tester,
    'timeline-lane-group-toggle-draw-${transformGroupHeaderLane.laneId}',
  );
  await _tapNamed(
    tester,
    'timeline-lane-group-graph-draw-${transformGroupHeaderLane.laneId}',
  );
  SessionRowButtonPresses(s).resizeLaneGraph(_transformGroup, 320);
  s.standOnRow(LaneRowAddress(_drawId, lane));
  await tester.pumpAndSettle();
}

Future<void> _tapNamed(WidgetTester tester, String name) async {
  final button = find.named(name);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// [under]: that many layers' rows under the drawing's. [transform]: the
/// drawing's, where not its Rotation keyed 0 on frame 0 and 45 on 8. The
/// cut [duration] frames long.
Future<EditorSessionManager> _pump(
  WidgetTester tester, {
  int under = 0,
  TransformTrack? transform,
  int duration = 48,
}) async {
  await tester.binding.setSurfaceSize(const Size(1400, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: HomePage(
        initialProject: _project(
          under: under,
          transform: transform,
          duration: duration,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.drag(
    find.byKey(const ValueKey<String>('dock-resize-bottom')),
    const Offset(0, -520),
  );
  await tester.pumpAndSettle();
  return tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
}

Project _project({
  required int under,
  TransformTrack? transform,
  int duration = 48,
}) => Project(
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
          duration: duration,
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
              transformTrack:
                  transform ??
                  TransformTrack.empty().copyWith(
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

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/services/guide_stroke_input.dart' show ShiftLine;
import 'package:anicel/src/ui/canvas/canvas_selection_layer.dart';
import 'package:anicel/src/ui/canvas/selection_drag.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

/// 🗣️I-121 (유저 2026-10-21): 「스냅 발생하면 쉬프트 떼기 전까지는 같은스냅」
/// — a lasso is a path the hand draws as a stroke is (I-110), so the line a
/// hold kept goes on through it too: the layer hands its drag the line, and
/// says at the press and as its modifier finger lifts whether Shift is held.
void main() {
  const layerKey = ValueKey<String>('layer');
  late ShiftLine line;
  late List<DrawnShapePath> drawn;

  setUp(() {
    line = ShiftLine();
    drawn = [];
  });

  Future<void> pumpLayer(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: 300,
            child: CanvasSelectionLayer(
              key: layerKey,
              tool: CanvasSelectionTool.drawShape,
              shapeKind: CanvasShapeKind.lasso,
              viewport: CanvasViewport(),
              pasteboard: const CanvasSize(
                width: 400,
                height: 300,
              ).pasteboardAt(PasteboardReach.whole),
              frameToken: 'frame',
              onShapeCommitted: (before, after) {},
              onDrawShape: (copies) => drawn.add(copies.single),
              shiftLine: line,
            ),
          ),
        ),
      ),
    ),
  );

  Offset on(WidgetTester tester, Offset local) =>
      tester.getTopLeft(find.byKey(layerKey)) + local;

  Future<TestGesture> down(
    WidgetTester tester,
    Offset local, {
    PointerDeviceKind kind = PointerDeviceKind.mouse,
    int pointer = 1,
  }) async {
    final hand = await tester.startGesture(
      on(tester, local),
      kind: kind,
      pointer: pointer,
      buttons: kPrimaryButton,
    );
    await tester.pump();
    return hand;
  }

  Future<void> through(
    WidgetTester tester,
    TestGesture hand,
    List<Offset> path,
  ) async {
    for (final local in path) {
      await hand.moveTo(on(tester, local));
      await tester.pump();
    }
  }

  Future<void> up(WidgetTester tester, TestGesture hand) async {
    await hand.up();
    await tester.pump();
  }

  /// A lasso Shift locks level, through y = 100.
  Future<void> level(WidgetTester tester) async {
    final hand = await down(tester, const Offset(100, 100));
    await through(tester, hand, const [Offset(140, 104), Offset(180, 98)]);
    await up(tester, hand);
  }

  (double, double) placed(CanvasPoint point) => (point.x, point.y);

  (double, double) pressedOnTheLine() =>
      placed(line.onTheLine(CanvasPoint(x: 150, y: 130)));

  testWidgets('🚨held through the lift, the next lasso starts on the line '
      'its hold kept', (tester) async {
    await pumpLayer(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await level(tester);
    final hand = await down(tester, const Offset(150, 130));
    await through(tester, hand, const [Offset(220, 100)]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await through(tester, hand, const [Offset(240, 170), Offset(160, 180)]);
    await up(tester, hand);

    expect(placed(drawn.last.points.first), (150.0, 100.0));
  });

  testWidgets('🚨let go before the press, the line goes with it', (
    tester,
  ) async {
    await pumpLayer(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await level(tester);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await up(tester, await down(tester, const Offset(150, 130)));

    expect(pressedOnTheLine(), (150.0, 130.0));
  });

  testWidgets('🚨a finger holding the lasso\'s Shift keeps the line while it '
      'rests, and lifted lets it go', (tester) async {
    await pumpLayer(tester);
    final pen = await down(
      tester,
      const Offset(100, 100),
      kind: PointerDeviceKind.stylus,
      pointer: 3,
    );
    final finger = await down(
      tester,
      const Offset(380, 20),
      kind: PointerDeviceKind.touch,
      pointer: 9,
    );
    await through(tester, pen, const [Offset(140, 104), Offset(180, 98)]);
    await up(tester, pen);
    expect(pressedOnTheLine(), (150.0, 100.0), reason: 'held while it rests');

    await up(tester, finger);
    expect(pressedOnTheLine(), (150.0, 130.0));
  });
}

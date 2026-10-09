// 🗣️I-88 (유저 2026-10-09): 「키보드유저용 캔버스 쉽게 회전하려고 지금
// 스페이스바는 이동이니까 스페이스바+컨트롤상태에선 회전으로 작동하도록」.
//
// While the 「회전」 key is held, a primary drag on the canvas TURNS the view
// about the middle its turn buttons use, by the angle the drag sweeps about
// it — and does nothing else: it pans nothing, and no tool takes it.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/viewport_point.dart';
import 'package:anicel/src/ui/canvas/canvas_press.dart';
import 'package:anicel/src/ui/canvas/canvas_view_hold.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_gesture_layer.dart';

void main() {
  tearDown(() => CanvasViewHold.held.value = null);

  Future<List<CanvasViewport>> pumpLayer(
    WidgetTester tester, {
    bool rotationEnabled = true,
    ViewportPoint Function()? turnAnchor,
  }) async {
    final viewports = <CanvasViewport>[];
    await tester.binding.setSurfaceSize(const Size(400, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: CanvasViewportGestureLayer(
          viewport: CanvasViewport(),
          onViewportChanged: viewports.add,
          rotationEnabled: rotationEnabled,
          turnAnchor: turnAnchor,
          child: const SizedBox.expand(),
        ),
      ),
    );
    return viewports;
  }

  /// A primary mouse drag from [from] by each step of [by] in turn.
  Future<void> drag(WidgetTester tester, Offset from, List<Offset> by) async {
    final mouse = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    for (final step in by) {
      await mouse.moveBy(step);
      await tester.pump();
    }
    await mouse.up();
    await tester.pump();
  }

  testWidgets('a drag a quarter round the middle turns the view a quarter, '
      'about the middle', (tester) async {
    final viewports = await pumpLayer(tester);
    CanvasViewHold.held.value = ViewHold.turn;

    // From right of the middle (200, 200) round to below it — a quarter,
    // clockwise on the screen.
    await drag(tester, const Offset(300, 200), const [Offset(-100, 100)]);

    expect(viewports, isNotEmpty);
    final middle = ViewportPoint(x: 200, y: 200);
    expect(
      viewports.last,
      CanvasViewport().rotatedAround(nextRotationDegrees: 90, anchor: middle),
    );
  });

  testWidgets('the angle follows the drag round, back past where it began',
      (tester) async {
    final viewports = await pumpLayer(tester);
    CanvasViewHold.held.value = ViewHold.turn;

    // Right of the middle → below it → left of it: half a turn.
    await drag(tester, const Offset(300, 200), const [
      Offset(-100, 100),
      Offset(-100, -100),
    ]);

    expect(viewports.last.rotationDegrees.abs(), closeTo(180, 1e-6));
  });

  testWidgets('it turns about the host\'s middle when the host names one',
      (tester) async {
    final anchor = ViewportPoint(x: 100, y: 100);
    final viewports = await pumpLayer(tester, turnAnchor: () => anchor);
    CanvasViewHold.held.value = ViewHold.turn;

    await drag(tester, const Offset(200, 100), const [Offset(-100, 100)]);

    expect(
      viewports.last,
      CanvasViewport().rotatedAround(nextRotationDegrees: 90, anchor: anchor),
    );
  });

  testWidgets('⛔the turn key\'s drag pans nothing, and the pan key\'s turns '
      'nothing', (tester) async {
    final viewports = await pumpLayer(tester);

    CanvasViewHold.held.value = ViewHold.turn;
    // Straight out from the middle sweeps no angle.
    await drag(tester, const Offset(300, 200), const [Offset(50, 0)]);
    for (final viewport in viewports) {
      expect((viewport.panX, viewport.panY), (0, 0));
    }

    CanvasViewHold.held.value = ViewHold.pan;
    await drag(tester, const Offset(300, 200), const [Offset(-100, 100)]);
    expect(viewports.last.rotationDegrees, 0);
    expect(viewports.last.panX, isNot(0));
  });

  testWidgets('⛔a host whose content does not turn turns nothing — and pans '
      'nothing either', (tester) async {
    final viewports = await pumpLayer(tester, rotationEnabled: false);
    CanvasViewHold.held.value = ViewHold.turn;

    await drag(tester, const Offset(300, 200), const [Offset(-100, 100)]);

    expect(viewports, isEmpty);
  });

  test('the turn key\'s press is the view\'s and draws nothing; with no '
      'key held it is the tool\'s', () {
    CanvasViewHold.held.value = ViewHold.turn;
    expect(canvasPressTurns(kPrimaryButton), isTrue);
    expect(canvasPressPans(kPrimaryButton), isFalse);
    expect(canvasPressMovesTheView(kPrimaryButton), isTrue);
    expect(canvasPressTurns(kSecondaryMouseButton), isFalse);

    CanvasViewHold.held.value = null;
    expect(canvasPressTurns(kPrimaryButton), isFalse);
    expect(canvasPressMovesTheView(kPrimaryButton), isFalse);
  });
}

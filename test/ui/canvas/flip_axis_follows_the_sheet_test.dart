import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_gesture_layer.dart';
import 'package:anicel/src/ui/canvas/flip_hud_controller.dart';
import 'package:anicel/src/ui/input/app_input_settings.dart';

/// F-28 — **the canvas flip reads its frame direction off the sheet.**
///
/// 유저 2026-08-24: 「타임라인패널 x시트일 경우, 플립 그냥 반전시키자. 세로가
/// 프레임이동 가로가 레이어이동 되도록. 그게 직관적임」.
///
/// The gesture locks to the axis the fingers moved along and then has to say
/// what that axis MEANS. Sideways-is-frames was written into the lock, which
/// is right for the timeline and backwards for the X-sheet — where the frames
/// run down the page and the rows run across it.
void main() {
  const flipFingers = 3;

  setUp(() {
    // Whatever the machine's saved settings are, this test needs the finger
    // count it drives to BE the flip gesture.
    AppInput.settings.value = AppInput.settings.value.copyWith(
      touchDragThreeFingers: CanvasTouchDragAction.flip,
    );
  });

  Future<List<String>> flipDrag(
    WidgetTester tester, {
    required Offset travel,
    required bool framesRunVertically,
  }) async {
    final actions = <String>[];
    final hud = FlipHudController()..framesRunVertically = framesRunVertically;
    addTearDown(hud.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasViewportGestureLayer(
            viewport: CanvasViewport(),
            onViewportChanged: (_) {},
            onInvokeAction: actions.add,
            flipHud: hud,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    const origin = Offset(400, 300);
    final gestures = <TestGesture>[];
    for (var finger = 0; finger < flipFingers; finger += 1) {
      gestures.add(
        await tester.startGesture(origin + Offset(finger * 20.0, 0)),
      );
    }
    await tester.pump();
    for (final gesture in gestures) {
      await gesture.moveBy(travel);
      await tester.pump();
    }
    for (final gesture in gestures) {
      await gesture.up();
    }
    await tester.pumpAndSettle();
    return actions;
  }

  testWidgets('on the TIMELINE, sideways walks frames', (tester) async {
    final actions = await flipDrag(
      tester,
      travel: const Offset(160, 0),
      framesRunVertically: false,
    );
    expect(
      actions,
      isNotEmpty,
      reason: 'fixture premise: the drag crossed at least one step',
    );
    expect(actions.every((id) => id.startsWith('drawing-')), isTrue);
  });

  testWidgets('on the X-SHEET, sideways walks ROWS instead', (tester) async {
    final actions = await flipDrag(
      tester,
      travel: const Offset(160, 0),
      framesRunVertically: true,
    );
    expect(actions, isNotEmpty);
    expect(actions.every((id) => id.startsWith('selection-nudge-')), isTrue);
  });

  testWidgets('and downward walks FRAMES there', (tester) async {
    final actions = await flipDrag(
      tester,
      travel: const Offset(0, 160),
      framesRunVertically: true,
    );
    expect(actions, isNotEmpty);
    expect(actions.every((id) => id.startsWith('drawing-')), isTrue);
  });

  testWidgets('while on the timeline downward still walks rows', (
    tester,
  ) async {
    final actions = await flipDrag(
      tester,
      travel: const Offset(0, 160),
      framesRunVertically: false,
    );
    expect(actions, isNotEmpty);
    expect(actions.every((id) => id.startsWith('selection-nudge-')), isTrue);
  });
}

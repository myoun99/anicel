import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/ui/input/panel_pan.dart';

/// 🗣️R26-rest-Q2 (유저 2026-09-30): 「캔버스 설정을 그대로 따른다 — 「없음」이면
/// 거기서도 안 움직인다」 — a finger on a panel the canvas's pan reaches (the
/// timeline, the x-sheet, the conte panel) moves it as the canvas's setting
/// for that many fingers says. The defaults move it as they always did.
void main() {
  late ScrollController controller;
  late int taps;
  late int edits;

  setUp(() {
    controller = ScrollController();
    taps = 0;
    edits = 0;
  });
  tearDown(() {
    controller.dispose();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  Future<void> pumpPanel(WidgetTester tester, AppInputSettings input) async {
    AppInput.settings.value = input;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PanelPanDriver(
            controllers: [controller],
            child: ListView.builder(
              controller: controller,
              itemExtent: 40,
              itemCount: 200,
              itemBuilder: (context, index) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => taps += 1,
                // An edit drag, on the timeline's own device set: it takes
                // a finger exactly while one finger draws (결정 10).
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  supportedDevices: AppInput.timelineEditPanDevices,
                  onPanStart: (_) => edits += 1,
                  child: Text('row $index'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// [fingers] land together at the panel's centre and travel up as one.
  Future<void> dragWith(WidgetTester tester, int fingers) async {
    final centre = tester.getCenter(find.byType(ListView));
    final gestures = [
      for (var finger = 0; finger < fingers; finger += 1)
        await tester.startGesture(
          centre + Offset(finger * 40.0, 0),
          kind: PointerDeviceKind.touch,
          pointer: 10 + finger,
        ),
    ];
    for (var step = 0; step < 10; step += 1) {
      for (final gesture in gestures) {
        await gesture.moveBy(const Offset(0, -20));
      }
      await tester.pump();
    }
    for (final gesture in gestures) {
      await gesture.up();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('with the defaults a finger drag scrolls the panel as it '
      'always did — one finger and two', (tester) async {
    await pumpPanel(tester, const AppInputSettings());

    await dragWith(tester, 1);
    final afterOne = controller.offset;
    expect(afterOne, greaterThan(0), reason: 'one finger flips: it scrolls');

    await dragWith(tester, 2);
    expect(controller.offset, greaterThan(afterOne), reason: 'two navigate');
  });

  testWidgets('one finger set to 「없음」 does not move the panel — and a tap '
      'is still a tap', (tester) async {
    await pumpPanel(
      tester,
      const AppInputSettings(touchDragOneFinger: CanvasTouchDragAction.none),
    );

    await dragWith(tester, 1);
    expect(controller.offset, 0);

    await tester.tap(find.text('row 3'));
    await tester.pump();
    expect(taps, 1, reason: 'the setting names a DRAG, not a press');
  });

  testWidgets('two fingers set to 「없음」 hold the panel still — the finger '
      'that landed first included — and one finger still scrolls', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      const AppInputSettings(touchDragTwoFingers: CanvasTouchDragAction.none),
    );

    await dragWith(tester, 2);
    expect(controller.offset, 0);

    await dragWith(tester, 1);
    expect(controller.offset, greaterThan(0), reason: 'one finger flips');
  });

  // The scroller lets go of the first finger on its own when the second is
  // one it may not take; an EDIT drag takes every finger while one finger
  // draws, so the finger that landed first is held here or it edits.
  testWidgets('one finger drawing, two set to 「없음」: a two-finger drag '
      'neither scrolls nor edits — the first finger is held too', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      const AppInputSettings(
        touchDragOneFinger: CanvasTouchDragAction.draw,
        touchDragTwoFingers: CanvasTouchDragAction.none,
      ),
    );

    await dragWith(tester, 2);

    expect(controller.offset, 0);
    expect(edits, 0);
  });
}

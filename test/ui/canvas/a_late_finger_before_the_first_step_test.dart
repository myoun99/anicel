import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_gesture_layer.dart';
import 'package:anicel/src/models/app_input_settings.dart';

/// 🚨★★★H30 — A SECOND FINGER THAT LANDS AFTER THE FIRST HAS MOVED.
///
/// 유저 (H30): 「지인이 아이패드로 작업중인데, 두손핑거로 캔버스 컨트롤하려다
/// **레이어이동, 즉 1핑거로 인식하는경우**가 종종 있는거같아. 아마 두손가락을
/// **동시에 착지안하고 따로따로 착지**하는게 버릇인거같은데」.
///
/// ⛔The engine already allows a staggered LAND — a second finger arriving
/// 400ms later still forms the pinch, because pre-lock joins have no time
/// window (PEN-8 #3). What it did NOT allow is a second finger arriving
/// after the first has already MOVED: the group locks the instant any finger
/// crosses the 18px slop, and from then on late fingers are modifiers, never
/// members. One finger that twitched 20px had already decided the gesture.
///
/// ⇒ The lock waits for the first EFFECT instead of the first movement. A
/// flip's first effect is a whole step (48px), so everything under that is
/// still 「분류 전」 and a finger arriving there joins.
///
/// ⚠️Only flip waits. Navigate, brush size and draw make their first pixel
/// count, so for them the slop IS the first effect and nothing moves.
void main() {
  tearDown(() {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  Future<({List<String> actions, List<CanvasViewport> viewports})> pumpEngine(
    WidgetTester tester,
  ) async {
    if (AppInput.settings.value.touchDragOneFinger ==
        CanvasTouchDragAction.draw) {
      AppInput.settings.value = AppInput.settings.value.copyWith(
        touchDragOneFinger: CanvasTouchDragAction.flip,
      );
    }
    final actions = <String>[];
    final viewports = <CanvasViewport>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasViewportGestureLayer(
            viewport: CanvasViewport(),
            onViewportChanged: viewports.add,
            onInvokeAction: actions.add,
            onBrushSizeDragStart: () {},
            onBrushSizeDragUpdate: (delta, {required snap}) {},
            onBrushSizeDragEnd: () {},
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    return (actions: actions, viewports: viewports);
  }

  testWidgets(
    '🚨★★★the second finger lands after 25px — past the slop, before the '
    'first flip step — and the gesture is still a pinch',
    (tester) async {
      final probes = await pumpEngine(tester);

      final first = await tester.startGesture(
        const Offset(200, 200),
        kind: PointerDeviceKind.touch,
      );
      // 25 is the whole point: past the 18px slop that used to lock the
      // group, short of the 48px that makes a flip actually DO something.
      await first.moveBy(const Offset(25, 0));
      await tester.pump();

      final second = await tester.startGesture(
        const Offset(280, 200),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      await first.moveBy(const Offset(-40, 0));
      await second.moveBy(const Offset(40, 0));
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pump();

      expect(
        probes.actions,
        isEmpty,
        reason: '🚨no one-finger flip may fire — 「1핑거로 인식하는경우」 is '
            'the bug being reported',
      );
      expect(
        probes.viewports,
        isNotEmpty,
        reason: 'the two fingers are a pinch, and a pinch navigates',
      );
    },
  );

  testWidgets(
    '⛔once a step has actually happened the group IS locked — a later '
    'finger is a modifier, not a member',
    (tester) async {
      final probes = await pumpEngine(tester);

      final first = await tester.startGesture(
        const Offset(200, 200),
        kind: PointerDeviceKind.touch,
      );
      // Past a whole step: the flip has DONE something, so the gesture is
      // decided. ⛔Re-classifying here is the Callipeg confusion the engine
      // exists to avoid.
      await first.moveBy(const Offset(60, 0));
      await tester.pump();
      expect(
        probes.actions,
        isNotEmpty,
        reason: '⛔premise: a step really fired — otherwise this test is '
            'asserting about a gesture that never started',
      );

      final second = await tester.startGesture(
        const Offset(280, 200),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      await first.moveBy(const Offset(-40, 0));
      await second.moveBy(const Offset(40, 0));
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pump();

      expect(
        probes.viewports,
        isEmpty,
        reason: 'a locked flip does not become a pinch half way through',
      );
    },
  );
}

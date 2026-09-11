import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/canvas/canvas_touch_contacts.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_gesture_layer.dart';

/// UP and CANCEL are the same event to the viewport gesture layer: **this
/// pointer left**. A pan drops its anchor either way, and a finger leaves
/// the touch group either way — a cancelled contact that stayed behind
/// would keep panning off a pointer nobody is holding.
void main() {
  setUp(CanvasTouchContacts.reset);
  tearDown(CanvasTouchContacts.reset);
  // The wheel pans only when it is mapped to (I-15): mapped here, so the
  // middle drags below are the pan whose lift these tests watch.
  setUp(() {
    AppInput.settings.value = AppInput.settings.value.copyWith(
      canvasWheelClick: const CanvasPointerMapping(
        action: CanvasPointerAction.pan,
      ),
    );
  });
  tearDown(() {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  Future<CanvasViewport Function()> pumpLayer(WidgetTester tester) async {
    var viewport = CanvasViewport();
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          home: Scaffold(
            body: CanvasViewportGestureLayer(
              viewport: viewport,
              onViewportChanged: (next) => setState(() => viewport = next),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return () => viewport;
  }

  /// A middle-button drag, mapped to the pan above.
  Future<double> panThenLift(
    WidgetTester tester, {
    required bool cancel,
  }) async {
    final read = await pumpLayer(tester);
    final mouse = TestPointer(
      41,
      PointerDeviceKind.mouse,
      null,
      kTertiaryButton,
    );
    await tester.sendEventToBinding(mouse.down(const Offset(200, 200)));
    await tester.pump();
    await tester.sendEventToBinding(mouse.move(const Offset(260, 200)));
    await tester.pump();

    final panned = read().panX;
    expect(
      panned,
      isNot(0),
      reason: 'LIVENESS — the drag has to have panned before the lift means '
          'anything',
    );

    await tester.sendEventToBinding(
      cancel ? mouse.cancel() : mouse.up(),
    );
    await tester.pump();

    // A SECOND drag proves the anchor is gone: the layer takes one pan
    // pointer at a time, so a pointer left behind would refuse this one.
    final next = TestPointer(
      42,
      PointerDeviceKind.mouse,
      null,
      kTertiaryButton,
    );
    await tester.sendEventToBinding(next.down(const Offset(200, 200)));
    await tester.pump();
    await tester.sendEventToBinding(next.move(const Offset(230, 200)));
    await tester.pump();
    return read().panX - panned;
  }

  testWidgets('a pan drops its anchor when the button lifts', (tester) async {
    expect(await panThenLift(tester, cancel: false), 30);
  });

  testWidgets('a pan drops its anchor when the pointer is CANCELLED', (
    tester,
  ) async {
    expect(
      await panThenLift(tester, cancel: true),
      30,
      reason: 'a cancelled pan pointer is gone exactly as a lifted one is — '
          'the next middle drag is free to take the anchor',
    );
  });

  /// Two fingers navigating, then one of them leaves. Any base finger
  /// leaving ends the gesture whole — the survivor drives nothing.
  Future<double> pinchThenLift(
    WidgetTester tester, {
    required bool cancel,
  }) async {
    final read = await pumpLayer(tester);
    final a = TestPointer(51, PointerDeviceKind.touch);
    final b = TestPointer(52, PointerDeviceKind.touch);
    await tester.sendEventToBinding(a.down(const Offset(180, 300)));
    await tester.sendEventToBinding(b.down(const Offset(320, 300)));
    await tester.pump();
    await tester.sendEventToBinding(a.move(const Offset(100, 300)));
    await tester.sendEventToBinding(b.move(const Offset(400, 300)));
    await tester.pump();

    final zoomed = read().zoom;
    expect(
      zoomed,
      isNot(1),
      reason: 'LIVENESS — the pinch has to have zoomed first',
    );

    await tester.sendEventToBinding(cancel ? a.cancel() : a.up());
    await tester.pump();
    await tester.sendEventToBinding(b.move(const Offset(700, 300)));
    await tester.pump();
    return read().zoom - zoomed;
  }

  testWidgets('a lifted finger ends the two-finger gesture', (tester) async {
    expect(await pinchThenLift(tester, cancel: false), 0);
  });

  testWidgets('a CANCELLED finger ends it the same way', (tester) async {
    expect(
      await pinchThenLift(tester, cancel: true),
      0,
      reason: 'a contact left behind by cancel would keep the pinch running '
          'off a finger the glass no longer has',
    );
  });
}

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/canvas/canvas_touch_contacts.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_gesture_layer.dart';
import 'package:anicel/src/ui/debug/input_inspector.dart';

/// **H24 — a gesture you do not hold ALL of is not your gesture.**
///
/// 유저 2026-08-25: 「터치 제스처가 패널을 통과」. Two fingers on the glass
/// with one of them over the timeline, and the canvas ran a ONE-finger
/// gesture — the timeline flipped frames while the user was pinching.
///
/// The canvas counts the fingers IT received. When the app is holding more
/// than that, the rest are somewhere else, and what is happening is not the
/// N-finger gesture that count names.
void main() {
  setUp(CanvasTouchContacts.reset);
  tearDown(CanvasTouchContacts.reset);

  /// The app's ONE always-mounted pointer observer, wrapped around a canvas
  /// gesture layer — the production arrangement, so the census is fed the
  /// way it really is.
  /// A flip speaks through `onInvokeAction`. Wired so a stood-down group
  /// cannot fire one unnoticed.
  late List<String> invoked;

  Future<CanvasViewport Function()> pumpCanvas(WidgetTester tester) async {
    var viewport = CanvasViewport();
    invoked = <String>[];
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          home: Scaffold(
            body: InputInspectorHost(
              child: CanvasViewportGestureLayer(
                viewport: viewport,
                onViewportChanged: (next) => setState(() => viewport = next),
                onInvokeAction: invoked.add,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return () => viewport;
  }

  /// A finger that lands somewhere the canvas never sees — the timeline,
  /// the timesheet, another panel. Only the app-wide observer counts it.
  void fingerOnAnotherPanel(int pointer) => CanvasTouchContacts.noteAppWide(
    PointerDownEvent(pointer: pointer, kind: PointerDeviceKind.touch),
  );

  void liftFingerOnAnotherPanel(int pointer) => CanvasTouchContacts.noteAppWide(
    PointerUpEvent(pointer: pointer, kind: PointerDeviceKind.touch),
  );

  group('the census the law reads', () {
    testWidgets('counts a finger whichever panel it lands on', (tester) async {
      await pumpCanvas(tester);
      expect(CanvasTouchContacts.appWideCount, 0);

      final finger = TestPointer(11, PointerDeviceKind.touch);
      await tester.sendEventToBinding(finger.down(const Offset(200, 200)));
      await tester.pump();
      expect(CanvasTouchContacts.appWideCount, 1);

      await tester.sendEventToBinding(finger.up());
      await tester.pump();
      expect(CanvasTouchContacts.appWideCount, 0);
    });

    testWidgets('🧪⛔and CANNOT be inflated by the promoted mouse', (
      tester,
    ) async {
      // The card refused to ship the law until this was measured: an
      // over-count would stand every canvas gesture down. Windows promotes
      // a pinch to `mouse hover` + `mouse scroll` at the centroid, and this
      // file's own D34 note records that those really do arrive.
      await pumpCanvas(tester);
      final mouse = TestPointer(21, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(const Offset(300, 300)));
      await tester.sendEventToBinding(mouse.down(const Offset(300, 300)));
      await tester.pump();

      expect(
        CanvasTouchContacts.appWideCount,
        0,
        reason: 'the census filters to touch — a promoted mouse is a mouse',
      );
    });

    testWidgets('⛔a cancelled finger does not leak', (tester) async {
      await pumpCanvas(tester);
      final finger = TestPointer(31, PointerDeviceKind.touch);
      await tester.sendEventToBinding(finger.down(const Offset(200, 200)));
      await tester.pump();
      expect(CanvasTouchContacts.appWideCount, 1);

      await tester.sendEventToBinding(finger.cancel());
      await tester.pump();
      expect(
        CanvasTouchContacts.appWideCount,
        0,
        reason:
            'a leaked contact would leave the canvas standing down forever '
            '— which is the failure mode that kept this law off the board',
      );
    });
  });


  /// The reported gesture: a PINCH, with one of the two fingers over
  /// another panel. Two fingers reach the canvas or the pinch is not the
  /// canvas's to run.
  group('the law', () {
    /// A two-finger pinch on the canvas, optionally with [alsoDown] fingers
    /// already held on some other panel.
    Future<double> pinch(WidgetTester tester, {int alsoDown = 0}) async {
      final read = await pumpCanvas(tester);
      for (var i = 0; i < alsoDown; i += 1) {
        fingerOnAnotherPanel(90 + i);
      }

      final a = TestPointer(61, PointerDeviceKind.touch);
      final b = TestPointer(62, PointerDeviceKind.touch);
      await tester.sendEventToBinding(a.down(const Offset(300, 300)));
      await tester.sendEventToBinding(b.down(const Offset(500, 300)));
      await tester.pump();
      await tester.sendEventToBinding(a.move(const Offset(250, 300)));
      await tester.sendEventToBinding(b.move(const Offset(550, 300)));
      await tester.pump();
      await tester.sendEventToBinding(a.up());
      await tester.sendEventToBinding(b.up());
      await tester.pumpAndSettle();

      for (var i = 0; i < alsoDown; i += 1) {
        liftFingerOnAnotherPanel(90 + i);
      }
      return read().zoom;
    }

    testWidgets('a pinch the canvas holds WHOLE navigates', (tester) async {
      expect(
        await pinch(tester),
        isNot(CanvasViewport().zoom),
        reason:
            'fixture premise: this really is the navigate gesture — without '
            'it the test below would pass on a canvas that never zooms',
      );
    });

    testWidgets('⛔but with a third finger on another panel it runs NOTHING', (
      tester,
    ) async {
      expect(
        await pinch(tester, alsoDown: 1),
        CanvasViewport().zoom,
        reason:
            '🚨the canvas held TWO fingers of a THREE-finger gesture. Two '
            'fingers name the pinch; three name the brush-size drag, and which '
            'of them is happening is not something this layer can see. '
            'Standing down is the only honest answer.',
      );
    });

    testWidgets('⛔and it stays down however many are elsewhere', (
      tester,
    ) async {
      expect(await pinch(tester, alsoDown: 3), CanvasViewport().zoom);
    });

    testWidgets('⛔a finger landing on a panel MID-pinch does not '
        'reclassify what is already running', (tester) async {
      final read = await pumpCanvas(tester);

      final a = TestPointer(71, PointerDeviceKind.touch);
      final b = TestPointer(72, PointerDeviceKind.touch);
      await tester.sendEventToBinding(a.down(const Offset(300, 300)));
      await tester.sendEventToBinding(b.down(const Offset(500, 300)));
      await tester.pump();
      // The lock happens here, while the canvas holds everything.
      await tester.sendEventToBinding(a.move(const Offset(280, 300)));
      await tester.sendEventToBinding(b.move(const Offset(520, 300)));
      await tester.pump();
      final atLock = read().zoom;
      expect(
        atLock,
        isNot(CanvasViewport().zoom),
        reason: 'premise: it locked and navigated',
      );

      fingerOnAnotherPanel(98);
      await tester.sendEventToBinding(a.move(const Offset(200, 300)));
      await tester.sendEventToBinding(b.move(const Offset(600, 300)));
      await tester.pump();
      await tester.sendEventToBinding(a.up());
      await tester.sendEventToBinding(b.up());
      await tester.pumpAndSettle();
      liftFingerOnAnotherPanel(98);

      expect(
        read().zoom,
        isNot(atLock),
        reason:
            'lock-then-modify: the classification is made ONCE, at the '
            'lock, and a late finger never re-makes it — the law is a gate '
            'on classifying, not a brake on a gesture already running',
      );
    });
  });
}

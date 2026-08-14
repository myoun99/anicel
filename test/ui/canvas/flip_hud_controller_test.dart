import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_gesture_layer.dart';
import 'package:anicel/src/ui/canvas/flip_hud_controller.dart';
import 'package:anicel/src/ui/canvas/flip_hud_model.dart';
import 'package:anicel/src/ui/canvas/flip_hud_overlay.dart';
import 'package:anicel/src/ui/input/app_input_settings.dart';

/// The flip HUD's state: ONE haptic rule, and a window that never owns
/// the cursor.
final _testOwner = Object();

void main() {
  tearDown(() {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  // A ► 2 empty, block '1' (3f), block '2' (2f), 3 empty, block '3' (1f),
  // 4 empty. B ► nothing at all: standing on it is standing on nothing.
  const rowA = FlipHudRow(
    name: 'A',
    kind: LayerKind.animation,
    runs: [
      FlipHudRun(startIndex: 2, length: 3, label: '1'),
      FlipHudRun(startIndex: 5, length: 2, label: '2'),
      FlipHudRun(startIndex: 10, length: 1, label: '3'),
    ],
  );
  const rowB = FlipHudRow(
    name: 'B',
    kind: LayerKind.animation,
    runs: <FlipHudRun>[],
  );

  group('the one haptic rule', () {
    late FlipHudController controller;
    late List<int> ticks;
    var frame = 0;
    var rowIndex = 0;
    var clock = DateTime(2026);

    setUp(() {
      frame = 0;
      rowIndex = 0;
      clock = DateTime(2026);
      ticks = <int>[];
      controller =
          FlipHudController(
            hapticTick: () => ticks.add(ticks.length),
            hapticsEnabled: () => true,
            clock: () => clock,
          )..bind(
            _testOwner,
            (_) => FlipHudSnapshot(
              rows: const [rowA, rowB],
              rowIndex: rowIndex,
              frameIndex: frame,
              frameCount: 15,
            ),
          );
    });

    tearDown(() => controller.dispose());

    /// Lands the cursor somewhere and lets the controller read it, a
    /// comfortable step past the coalesce window so these assertions are
    /// about the RULE rather than about the throttle.
    void land(int next, {int row = 0}) {
      frame = next;
      rowIndex = row;
      clock = clock.add(FlipHudController.hapticCoalesce * 2);
      controller.refresh();
    }

    test('a different drawing ticks; a hold inside one does not', () {
      controller.begin(
        axis: FlipHudAxis.frame,
        anchor: Offset.zero,
        frameStep: false,
      );
      expect(ticks, isEmpty, reason: 'showing the window is not a step');

      land(2); // onto block '1'
      expect(ticks.length, 1);

      land(3); // its hold — same picture
      expect(ticks.length, 1);

      land(5); // onto block '2'
      expect(ticks.length, 2);
    });

    test('empty space is silent, in and out', () {
      controller.begin(
        axis: FlipHudAxis.frame,
        anchor: Offset.zero,
        frameStep: false,
      );
      land(5); // block '2'
      expect(ticks.length, 1);

      land(7); // into the gap
      land(8); // still in it
      land(9);
      expect(ticks.length, 1, reason: 'nothing was drawn there');

      land(10); // out onto block '3'
      expect(ticks.length, 2);
    });

    test('a clamped end never ticks', () {
      controller.begin(
        axis: FlipHudAxis.frame,
        anchor: Offset.zero,
        frameStep: false,
      );
      land(10);
      expect(ticks.length, 1);

      // The session refused to move — the same frame lands again.
      land(10);
      land(10);
      expect(ticks.length, 1);
    });

    test('a row with no cel under the cursor is silent', () {
      controller.begin(
        axis: FlipHudAxis.row,
        anchor: Offset.zero,
        frameStep: false,
      );
      land(2); // row A, block '1'
      expect(ticks.length, 1);

      land(2, row: 1); // row B holds nothing here
      expect(ticks.length, 1);

      land(2); // back onto A
      expect(ticks.length, 2);
    });

    test('the preference silences the motor without changing the rest', () {
      var quiet = false;
      final muted =
          FlipHudController(
            hapticTick: () => ticks.add(ticks.length),
            hapticsEnabled: () => !quiet,
          )..bind(
            _testOwner,
            (_) => FlipHudSnapshot(
              rows: const [rowA],
              rowIndex: 0,
              frameIndex: frame,
              frameCount: 15,
            ),
          );
      addTearDown(muted.dispose);
      muted.begin(
        axis: FlipHudAxis.frame,
        anchor: Offset.zero,
        frameStep: false,
      );
      quiet = true;
      frame = 2;
      muted.refresh();
      expect(ticks, isEmpty);
      expect(muted.visible, isTrue, reason: 'the window still shows');
    });
  });

  group('a fast sweep', () {
    test('coalesces rather than queueing a backlog', () {
      var frame = 0;
      final ticks = <int>[];
      final controller =
          FlipHudController(
            hapticTick: () => ticks.add(ticks.length),
            hapticsEnabled: () => true,
            // A frozen clock IS the fast sweep: every crossing inside one
            // coalesce window.
            clock: () => DateTime(2026),
          )..bind(
            _testOwner,
            (_) => FlipHudSnapshot(
              rows: const [rowA],
              rowIndex: 0,
              frameIndex: frame,
              frameCount: 15,
            ),
          );
      addTearDown(controller.dispose);
      controller.begin(
        axis: FlipHudAxis.frame,
        anchor: Offset.zero,
        frameStep: false,
      );

      // Three different blocks crossed inside one coalesce window.
      for (final next in [2, 5, 10]) {
        frame = next;
        controller.refresh();
      }

      expect(ticks.length, 1);
    });
  });

  group('the slide keeps up with the hand', () {
    test('a leg never outlasts the gap between the steps it joins', () {
      // An implicit animation restarts at full duration on every target
      // change, so a leg longer than the step interval never lands: the
      // strip trails the hand for as long as the sweep continues.
      expect(FlipHudMetrics.slideFor(null), FlipHudMetrics.slide);
      expect(
        FlipHudMetrics.slideFor(const Duration(milliseconds: 400)),
        FlipHudMetrics.slide,
        reason: 'a leisurely flip gets the full slide',
      );
      expect(
        FlipHudMetrics.slideFor(const Duration(milliseconds: 40)),
        const Duration(milliseconds: 40),
        reason: 'a brisk sweep gets a leg that lands in time',
      );
      expect(
        FlipHudMetrics.slideFor(const Duration(milliseconds: 8)),
        Duration.zero,
        reason: 'below a frame or two a tween is a cut anyway',
      );
    });

    test('the interval is measured landing to landing, not per notify', () {
      var frame = 0;
      var clock = DateTime(2026);
      final controller =
          FlipHudController(
            hapticTick: () {},
            hapticsEnabled: () => false,
            clock: () => clock,
          )..bind(
            _testOwner,
            (_) => FlipHudSnapshot(
              rows: const [rowA],
              rowIndex: 0,
              frameIndex: frame,
              frameCount: 15,
            ),
          );
      addTearDown(controller.dispose);
      controller.begin(
        axis: FlipHudAxis.frame,
        anchor: Offset.zero,
        frameStep: false,
      );
      expect(controller.lastStepInterval, isNull);

      clock = clock.add(const Duration(milliseconds: 30));
      frame = 2;
      controller.refresh();
      expect(
        controller.lastStepInterval,
        isNull,
        reason: 'the first landing has nothing to measure against',
      );

      clock = clock.add(const Duration(milliseconds: 30));
      frame = 5;
      controller.refresh();
      expect(controller.lastStepInterval, const Duration(milliseconds: 30));

      // A modifier change re-renders without moving the cursor; letting
      // that re-time the slide would size the next leg off a non-event.
      clock = clock.add(const Duration(milliseconds: 500));
      controller.refresh(frameStep: true);
      expect(controller.lastStepInterval, const Duration(milliseconds: 30));
    });
  });

  group('the window\'s lifetime', () {
    testWidgets('shows on the lock, holds after the lift, then lets go', (
      tester,
    ) async {
      final controller =
          FlipHudController(hapticTick: () {}, hapticsEnabled: () => true)
            ..bind(
            _testOwner,
              (_) => const FlipHudSnapshot(
                rows: [rowA],
                rowIndex: 0,
                frameIndex: 2,
                frameCount: 15,
              ),
            );
      addTearDown(controller.dispose);

      expect(controller.visible, isFalse);
      expect(controller.displayAxis, isNull);

      controller.begin(
        axis: FlipHudAxis.frame,
        anchor: const Offset(120, 240),
        frameStep: false,
      );
      expect(controller.visible, isTrue);
      expect(controller.axis, FlipHudAxis.frame);

      controller.end();
      // The live axis is gone at once; the picture is not.
      expect(controller.axis, isNull);
      expect(controller.visible, isTrue);
      expect(controller.displayAxis, FlipHudAxis.frame);

      await tester.pump(FlipHudController.holdAfterRelease);
      expect(controller.visible, isFalse);
      expect(controller.displayAxis, FlipHudAxis.frame, reason: 'fading');

      await tester.pump(FlipHudController.fadeOut);
      expect(controller.displayAxis, isNull);
      expect(controller.anchor, isNull);
    });

    testWidgets('a cut with nothing in it never shows the window', (
      tester,
    ) async {
      final controller = FlipHudController(
        hapticTick: () {},
        hapticsEnabled: () => true,
      )..bind(_testOwner, (_) => FlipHudSnapshot.empty);
      addTearDown(controller.dispose);

      controller.begin(
        axis: FlipHudAxis.frame,
        anchor: Offset.zero,
        frameStep: false,
      );

      expect(controller.visible, isFalse);
      expect(controller.displayAxis, isNull);
    });
  });

  group('driven by a real flip gesture', () {
    Future<FlipHudController> pumpLayer(WidgetTester tester) async {
      AppInput.settings.value = AppInputSettings.testCorpusBaseline.copyWith(
        touchDragOneFinger: CanvasTouchDragAction.flip,
      );
      final controller =
          FlipHudController(hapticTick: () {}, hapticsEnabled: () => false)
            ..bind(
            _testOwner,
              (_) => const FlipHudSnapshot(
                rows: [rowA, rowB],
                rowIndex: 0,
                frameIndex: 2,
                frameCount: 15,
              ),
            );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CanvasViewportGestureLayer(
              viewport: CanvasViewport(),
              onViewportChanged: (_) {},
              onInvokeAction: (_) {},
              flipHud: controller,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const SizedBox.expand(),
                  FlipHudOverlay(controller: controller),
                ],
              ),
            ),
          ),
        ),
      );
      return controller;
    }

    testWidgets('the window appears on the AXIS LOCK, not on touchdown', (
      tester,
    ) async {
      final controller = await pumpLayer(tester);

      final finger = await tester.startGesture(
        const Offset(300, 400),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      expect(
        controller.visible,
        isFalse,
        reason: 'a tap or a plain pan must never flash it',
      );

      await finger.moveBy(const Offset(30, 2));
      await tester.pump();
      expect(controller.visible, isTrue);
      expect(controller.axis, FlipHudAxis.frame);
      expect(find.byKey(const ValueKey<String>('flip-hud')), findsOneWidget);

      await finger.up();
      await tester.pump();
      expect(controller.axis, isNull);
      await tester.pump(FlipHudController.holdAfterRelease);
      await tester.pump(FlipHudController.fadeOut);
      expect(find.byKey(const ValueKey<String>('flip-hud')), findsNothing);
    });

    testWidgets('the cut emptying out mid-hold fades instead of throwing', (
      tester,
    ) async {
      var rows = const [rowA];
      final controller =
          FlipHudController(hapticTick: () {}, hapticsEnabled: () => false)
            ..bind(
            _testOwner,
              (_) => FlipHudSnapshot(
                rows: rows,
                rowIndex: 0,
                frameIndex: 2,
                frameCount: rows.isEmpty ? 0 : 15,
              ),
            );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FlipHudOverlay(controller: controller)),
        ),
      );

      controller.begin(
        axis: FlipHudAxis.frame,
        anchor: const Offset(300, 400),
        frameStep: false,
      );
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('flip-hud')), findsOneWidget);

      // The cut closes under the window while it is still on screen.
      rows = const <FlipHudRow>[];
      controller.refresh();
      await tester.pump();

      expect(tester.takeException(), isNull);
      await tester.pump(FlipHudController.fadeOut);
      expect(tester.takeException(), isNull);

      controller.end();
      await tester.pump();
    });

    testWidgets('a vertical lock shows the ROW axis', (tester) async {
      final controller = await pumpLayer(tester);

      final finger = await tester.startGesture(
        const Offset(300, 400),
        kind: PointerDeviceKind.touch,
      );
      await finger.moveBy(const Offset(2, -30));
      await tester.pump();

      expect(controller.axis, FlipHudAxis.row);

      await finger.up();
      await tester.pump(FlipHudController.holdAfterRelease);
      await tester.pump(FlipHudController.fadeOut);
    });

    testWidgets('the +1 finger switches the window to frame columns', (
      tester,
    ) async {
      final controller = await pumpLayer(tester);

      final finger = await tester.startGesture(
        const Offset(300, 400),
        kind: PointerDeviceKind.touch,
      );
      await finger.moveBy(const Offset(30, 2));
      await tester.pump();
      expect(controller.frameStep, isFalse);

      final modifier = await tester.startGesture(
        const Offset(500, 500),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      expect(controller.frameStep, isTrue);

      await modifier.up();
      await tester.pump();
      expect(controller.frameStep, isFalse);

      await finger.up();
      await tester.pump(FlipHudController.holdAfterRelease);
      await tester.pump(FlipHudController.fadeOut);
    });
  });
}

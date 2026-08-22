import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_gesture_layer.dart';
import 'package:anicel/src/ui/input/app_input_settings.dart';

/// PEN-7b: the CONTROL-mode touch engine — finger-count slots, the
/// lock-then-modifier rule, snap constraints. Everything runs under the
/// control mode (the product default); the corpus baseline elsewhere is
/// untouched (this file opts in per test).
void main() {
  tearDown(() {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  Future<
    ({
      List<String> actions,
      List<CanvasViewport> viewports,
      List<(double, bool)> sizeDrags,
    })
  >
  pumpEngine(WidgetTester tester, {CanvasViewport? viewport}) async {
    // Opt INTO an engine-driven one-finger slot (the corpus baseline
    // pins draw = the engine stands down): keep any custom settings a
    // test already applied.
    if (AppInput.settings.value.touchDragOneFinger ==
        CanvasTouchDragAction.draw) {
      AppInput.settings.value = AppInput.settings.value.copyWith(
        touchDragOneFinger: CanvasTouchDragAction.flip,
      );
    }
    final actions = <String>[];
    final viewports = <CanvasViewport>[];
    final sizeDrags = <(double, bool)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasViewportGestureLayer(
            viewport: viewport ?? CanvasViewport(),
            onViewportChanged: viewports.add,
            onInvokeAction: actions.add,
            onBrushSizeDragStart: () {},
            onBrushSizeDragUpdate: (delta, {required snap}) =>
                sizeDrags.add((delta, snap)),
            onBrushSizeDragEnd: () {},
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    return (actions: actions, viewports: viewports, sizeDrags: sizeDrags);
  }

  testWidgets('1-finger horizontal flip steps drawings; the late finger '
      'switches to ONE-FRAME steps (lock-then-modifier)', (tester) async {
    final probes = await pumpEngine(tester);

    final finger = await tester.startGesture(
      const Offset(200, 200),
      kind: PointerDeviceKind.touch,
    );
    // Cross the slop horizontally, then one full step right.
    await finger.moveBy(const Offset(30, 2));
    await finger.moveBy(const Offset(48, 0));
    await tester.pump();
    expect(probes.actions, contains('drawing-next'));

    // A LATE second finger = modifier, never a re-classification: the
    // gesture keeps flipping, but by single frames now.
    final modifier = await tester.startGesture(
      const Offset(400, 300),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    probes.actions.clear();
    await finger.moveBy(const Offset(96, 0));
    await tester.pump();
    expect(probes.actions, isNotEmpty);
    expect(probes.actions.toSet(), {'frame-next'});

    await modifier.up();
    await finger.up();
    await tester.pump();
  });

  testWidgets('1-finger vertical flip walks layers through the arrow '
      'arbitration ids', (tester) async {
    final probes = await pumpEngine(tester);

    final finger = await tester.startGesture(
      const Offset(200, 300),
      kind: PointerDeviceKind.touch,
    );
    await finger.moveBy(const Offset(2, -30));
    await finger.moveBy(const Offset(0, -48));
    await tester.pump();
    await finger.up();
    await tester.pump();

    expect(probes.actions, contains('selection-nudge-up'));
  });

  testWidgets('2-finger drag navigates (pan reaches the viewport); with '
      'rotation disabled the view never rotates', (tester) async {
    AppInput.settings.value = const AppInputSettings(
      touchTimelineScroll: false,
      navigationRotationEnabled: false,
    );
    final probes = await pumpEngine(tester);

    final first = await tester.startGesture(
      const Offset(200, 200),
      kind: PointerDeviceKind.touch,
    );
    final second = await tester.startGesture(
      const Offset(300, 200),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    // Move both fingers together (pan) with a strong relative twist.
    await first.moveBy(const Offset(40, 10));
    await second.moveBy(const Offset(40, 90));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pump();

    expect(probes.viewports, isNotEmpty);
    for (final viewport in probes.viewports) {
      expect(viewport.rotationDegrees, 0);
    }
  });

  testWidgets('3-finger vertical drag reports brush size; the late finger '
      'flags SNAP', (tester) async {
    final probes = await pumpEngine(tester);

    final fingers = [
      await tester.startGesture(
        const Offset(200, 300),
        kind: PointerDeviceKind.touch,
      ),
      await tester.startGesture(
        const Offset(260, 300),
        kind: PointerDeviceKind.touch,
      ),
      await tester.startGesture(
        const Offset(320, 300),
        kind: PointerDeviceKind.touch,
      ),
    ];
    await tester.pump();
    for (final finger in fingers) {
      await finger.moveBy(const Offset(0, -30));
    }
    await tester.pump();
    expect(probes.sizeDrags, isNotEmpty);
    expect(probes.sizeDrags.last.$2, isFalse);
    expect(probes.sizeDrags.last.$1, greaterThan(0), reason: 'up = bigger');

    final modifier = await tester.startGesture(
      const Offset(500, 400),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    for (final finger in fingers) {
      await finger.moveBy(const Offset(0, -10));
    }
    await tester.pump();
    expect(probes.sizeDrags.last.$2, isTrue, reason: 'modifier = snap');

    await modifier.up();
    for (final finger in fingers) {
      await finger.up();
    }
    await tester.pump();
  });

  testWidgets('a STAGGERED second finger still forms the two-finger '
      'gesture (PEN-8 #3: pre-lock joins have no time window)', (tester) async {
    final probes = await pumpEngine(tester);

    final first = await tester.startGesture(
      const Offset(200, 200),
      kind: PointerDeviceKind.touch,
    );
    // The second finger lands WELL past any simultaneity window (the
    // tablet-reported miss: 살짝 어긋난 핀치가 안 먹히던 케이스).
    await tester.pump(const Duration(milliseconds: 400));
    final second = await tester.startGesture(
      const Offset(260, 200),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    await first.moveBy(const Offset(-40, 0));
    await second.moveBy(const Offset(40, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pump();

    expect(probes.actions, isEmpty, reason: 'no one-finger flip fired');
    expect(probes.viewports, isNotEmpty, reason: 'the pinch navigated');
    expect(probes.viewports.last.zoom, greaterThan(1));
  });

  testWidgets('slots are ASSIGNABLE: 1-finger set to navigate pans the '
      'viewport instead of flipping', (tester) async {
    AppInput.settings.value = const AppInputSettings(
      touchTimelineScroll: false,
      touchDragOneFinger: CanvasTouchDragAction.navigate,
    );
    final probes = await pumpEngine(tester);

    final finger = await tester.startGesture(
      const Offset(200, 200),
      kind: PointerDeviceKind.touch,
    );
    await finger.moveBy(const Offset(30, 0));
    await finger.moveBy(const Offset(60, 0));
    await tester.pump();
    await finger.up();
    await tester.pump();

    expect(probes.actions, isEmpty, reason: 'no flip on a navigate slot');
    expect(probes.viewports, isNotEmpty, reason: 'one-finger pan');
  });

  testWidgets('a DRAW one-finger slot stands the engine down — no flip, '
      'no nav; two fingers landing together still navigate (PEN-12 #4)', (
    tester,
  ) async {
    final probes = await pumpEngine(tester);
    AppInput.settings.value = AppInput.settings.value.copyWith(
      touchDragOneFinger: CanvasTouchDragAction.draw,
    );

    // A long single-finger drag: the brush view's stroke — the engine
    // must emit NOTHING (no flip steps, no viewport changes).
    final finger = await tester.startGesture(
      const Offset(200, 200),
      kind: PointerDeviceKind.touch,
    );
    for (var step = 0; step < 5; step += 1) {
      await finger.moveBy(const Offset(40, 0));
      await tester.pump();
    }
    await finger.up();
    await tester.pump();
    expect(probes.actions, isEmpty, reason: 'the stroke owns the finger');
    expect(probes.viewports, isEmpty);

    // Two fingers landing together (pre-lock join): the two-finger slot
    // still navigates.
    final first = await tester.startGesture(
      const Offset(200, 200),
      kind: PointerDeviceKind.touch,
      pointer: 21,
    );
    final second = await tester.startGesture(
      const Offset(260, 200),
      kind: PointerDeviceKind.touch,
      pointer: 22,
    );
    await first.moveBy(const Offset(-40, 0));
    await second.moveBy(const Offset(40, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pump();
    expect(probes.viewports, isNotEmpty, reason: 'pinch still navigates');
  });

  testWidgets('PEN-14: the modifier landing mid-navigate keeps the zoom '
      'CONTINUOUS — never a snap back to the gesture-start scale', (
    tester,
  ) async {
    final probes = await pumpEngine(tester);

    // Two fingers pinch OUT to 2×. The harness never rebuilds the layer
    // with the emitted viewport (widget.viewport stays 1.0) — exactly
    // the mid-gesture staleness a real parent shows between frames.
    final first = await tester.startGesture(
      const Offset(200, 200),
      kind: PointerDeviceKind.touch,
      pointer: 31,
    );
    final second = await tester.startGesture(
      const Offset(300, 200),
      kind: PointerDeviceKind.touch,
      pointer: 32,
    );
    await first.moveBy(const Offset(-50, 0));
    await second.moveBy(const Offset(50, 0));
    await tester.pump();
    expect(probes.viewports.last.zoom, closeTo(2.0, 0.01));

    // The MODIFIER lands: constrain from HERE — the zoom must stay ~2×
    // (snapped within the percent list), not collapse to the stale
    // widget.viewport scale.
    final modifier = await tester.startGesture(
      const Offset(250, 300),
      kind: PointerDeviceKind.touch,
      pointer: 33,
    );
    await tester.pump();
    await second.moveBy(const Offset(2, 0));
    await tester.pump();
    expect(
      probes.viewports.last.zoom,
      closeTo(2.0, 0.01),
      reason: 'the constraint anchors at the LIVE zoom, not the stale prop',
    );

    await first.up();
    await second.up();
    await modifier.up();
    await tester.pump();
  });
}

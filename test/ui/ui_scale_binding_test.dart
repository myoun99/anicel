import 'dart:ui' as ui show PointerData, PointerDataPacket, PointerChange;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/ui_scale.dart';

import '../helpers/scaled_test_binding.dart';

void main() {
  final binding = ScaledTestBinding.ensureInitialized();

  tearDown(() => AppUiScale.value.value = AppUiScale.defaultScale);

  testWidgets('the scale multiplies into the ROOT device matrix', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox.expand());
    final raw = tester.view.devicePixelRatio;
    expect(binding.renderViews.single.configuration.devicePixelRatio, raw);

    AppUiScale.value.value = 1.25;
    await tester.pump();
    expect(
      binding.renderViews.single.configuration.devicePixelRatio,
      raw * 1.25,
    );

    AppUiScale.value.value = 0.75;
    await tester.pump();
    expect(
      binding.renderViews.single.configuration.devicePixelRatio,
      raw * 0.75,
    );
  });

  testWidgets('the root matrix is a PURE SCALE — no translation', (
    tester,
  ) async {
    // The invariant the whole quantization round rests on: the root child's
    // origin is exactly on the device grid, so any app-chosen integral
    // device offset keeps its descendants there. A UI scale must not put a
    // translation into that matrix.
    AppUiScale.value.value = 1.1;
    await tester.pumpWidget(const SizedBox.expand());
    final matrix = binding.renderViews.single.configuration.toMatrix();
    expect(matrix.getTranslation().x, 0);
    expect(matrix.getTranslation().y, 0);
    expect(matrix.getTranslation().z, 0);
    final raw = tester.view.devicePixelRatio;
    expect(matrix.entry(0, 0), raw * 1.1);
    expect(matrix.entry(1, 1), raw * 1.1);
  });

  testWidgets('scaling up SHRINKS the logical box the child is given', (
    tester,
  ) async {
    // 🚨The half that is easy to forget. Chrome that scales up without a
    // smaller logical box lays a window's worth of UI out past the edge of
    // the window, and nothing reports it — the overflow banner only fires
    // inside a flex.
    late Size given;
    Widget probe() => LayoutBuilder(
      builder: (context, constraints) {
        given = constraints.biggest;
        return const SizedBox.expand();
      },
    );
    await tester.pumpWidget(probe());
    final unscaled = given;

    AppUiScale.value.value = 1.25;
    await tester.pumpWidget(probe());
    expect(given.width, closeTo(unscaled.width / 1.25, 1e-9));
    expect(given.height, closeTo(unscaled.height / 1.25, 1e-9));

    AppUiScale.value.value = 0.9;
    await tester.pumpWidget(probe());
    expect(given.width, closeTo(unscaled.width / 0.9, 1e-9));
  });

  testWidgets('a scale change forces a frame on its own', (tester) async {
    // Nobody calls `setState` for the binding half: the notifier's listener
    // is the only path from "the user picked 125%" to a relaid-out window.
    late Size given;
    await tester.pumpWidget(
      LayoutBuilder(
        builder: (context, constraints) {
          given = constraints.biggest;
          return const SizedBox.expand();
        },
      ),
    );
    final unscaled = given;
    AppUiScale.value.value = 1.5;
    // ⛔No `pumpWidget` — the widget tree is untouched. Only the binding's
    // listener can produce a new layout here.
    await tester.pump();
    expect(given.width, closeTo(unscaled.width / 1.5, 1e-9));
  });

  group('the POINTER is converted with the effective ratio', () {
    // 🚨The half that is invisible to every ordinary widget test.
    // `WidgetTester.tap` hands `handlePointerEvent` an already-logical
    // position and never runs `PointerEventConverter`, so a tap test
    // passes at every scale whether or not the conversion is right. These
    // push a real `PointerDataPacket` with PHYSICAL coordinates, which is
    // the only path that exercises it.
    // ⚠️A press and its release, in one packet. A second `down` for a
    // pointer that never went up is dropped before it reaches the tree —
    // which is how the first draft of this file measured only its first
    // ladder stop and looked like a conversion bug at the second.
    Future<void> sendTap(WidgetTester tester, Offset physical) async {
      ui.PointerData at(ui.PointerChange change) => ui.PointerData(
        viewId: tester.view.viewId,
        change: change,
        kind: PointerDeviceKind.touch,
        physicalX: physical.dx,
        physicalY: physical.dy,
      );
      binding.pumpPointerPacket(
        ui.PointerDataPacket(
          data: <ui.PointerData>[
            at(ui.PointerChange.down),
            at(ui.PointerChange.up),
          ],
        ),
      );
      await tester.pump();
    }

    for (final stop in AppUiScale.ladder) {
      testWidgets(
        'a press lands where it was aimed at ${AppUiScale.label(stop)}',
        (tester) async {
          AppUiScale.value.value = stop;
          Offset? pressedAt;
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: Listener(
                // ⚠️`deferToChild` is the default and an empty `SizedBox` is
                // not hit-testable, so without this the press converts
                // correctly and then hits nothing.
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) => pressedAt = event.position,
                child: const SizedBox.expand(),
              ),
            ),
          );

          final raw = tester.view.devicePixelRatio;
          const physical = Offset(600, 400);
          await sendTap(tester, physical);

          expect(pressedAt, isNotNull);
          // The logical coordinate the tree is laid out in — physical over
          // the ratio the ROOT MATRIX uses, not over the raw one. Divide by
          // the raw ratio instead and this is off by exactly the scale.
          expect(pressedAt!.dx, closeTo(physical.dx / (raw * stop), 1e-9));
          expect(pressedAt!.dy, closeTo(physical.dy / (raw * stop), 1e-9));
        },
      );
    }

    testWidgets('a press reaches the button under those physical pixels', (
      tester,
    ) async {
      // The user-facing form of the same claim: the thing you can see at
      // those pixels is the thing that gets pressed.
      AppUiScale.value.value = 1.25;
      var pressed = false;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          // ⚠️CENTRED, and small. A target at the origin survives the bug:
          // a 25% error on a centre of (20,20) is 5px, still inside a 40px
          // box, so the pin would pass with the raw ratio. Out at the
          // middle of the tree the same 25% is hundreds of pixels.
          child: Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => pressed = true,
              child: const SizedBox(width: 24, height: 24),
            ),
          ),
        ),
      );

      final box = tester.renderObject<RenderBox>(find.byType(GestureDetector));
      final logicalCentre = box.localToGlobal(box.size.center(Offset.zero));
      final ratio = tester.view.devicePixelRatio * 1.25;
      await sendTap(tester, logicalCentre * ratio);

      expect(
        pressed,
        isTrue,
        reason:
            'the 40x40 box painted at those device pixels must be the '
            'one the press reaches — divide by the raw ratio instead and '
            'the press lands 25% away and misses',
      );
    });
  });

  testWidgets('every ladder stop lands its exact product', (tester) async {
    await tester.pumpWidget(const SizedBox.expand());
    final raw = tester.view.devicePixelRatio;
    for (final stop in AppUiScale.ladder) {
      AppUiScale.value.value = stop;
      await tester.pump();
      expect(
        binding.renderViews.single.configuration.devicePixelRatio,
        raw * stop,
        reason: 'stop ${AppUiScale.label(stop)}',
      );
    }
  });
}

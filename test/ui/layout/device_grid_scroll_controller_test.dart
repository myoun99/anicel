import 'package:anicel/src/ui/effective_device_pixel_ratio.dart';
import 'package:anicel/src/ui/layout/device_grid_scroll_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The scrolled content lands on the device grid — and the drag still
/// travels exactly as far as the finger.
void main() {
  const marker = ValueKey<String>('scroll-body-marker');

  Widget harness(ScrollController controller, double ratio) => MediaQuery(
    data: MediaQueryData(devicePixelRatio: ratio),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: EffectiveDevicePixelRatioScope(
        child: SingleChildScrollView(
          controller: controller,
          child: DeviceGridScrollBody(
            controller: controller,
            axisDirection: AxisDirection.down,
            child: const SizedBox(
              key: marker,
              width: 400,
              height: 4000,
            ),
          ),
        ),
      ),
    ),
  );

  void useRatio(WidgetTester tester, double ratio) {
    tester.view.devicePixelRatio = ratio;
    tester.view.physicalSize = Size(800 * ratio, 600 * ratio);
    addTearDown(tester.view.reset);
  }

  double offGridBy(double logical, double ratio) {
    final device = logical * ratio;
    return (device - device.roundToDouble()).abs();
  }

  for (final ratio in <double>[1.125, 1.25, 1.35, 1.75, 1.5 * 0.7]) {
    testWidgets('the CONTENT lands on the grid at every step, ratio $ratio', (
      tester,
    ) async {
      useRatio(tester, ratio);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(harness(controller, ratio));

      final gesture = await tester.startGesture(const Offset(200, 300));
      for (var step = 0; step < 40; step += 1) {
        // 0.37 is deliberately not a whole anything — a step that happens
        // to land on the grid proves nothing. It is also SMALLER than a
        // device pixel at every ratio here, which is what killed the
        // first design.
        await gesture.moveBy(const Offset(0, -0.37));
        await tester.pump();
        final painted = tester.getTopLeft(find.byKey(marker)).dy;
        expect(
          offGridBy(painted, ratio),
          lessThan(1e-3),
          reason:
              'step $step painted the content at $painted logical = '
              '${painted * ratio} device px, with the offset at '
              '${controller.offset}',
        );
      }
      await gesture.up();
      await tester.pumpAndSettle();
    });
  }

  testWidgets('★a long drag travels exactly as far as the finger', (
    tester,
  ) async {
    // 🚨THE pin, and it is the one the first design failed. Snapping the
    // POSITION annihilates any step smaller than a device pixel: 0.37
    // logical is 0.4995 device at 1.35, which rounds to zero, so the
    // content never moved at all — measured, 111 logical px of finger
    // travel produced an offset of 0.0. Correcting only the PAINT leaves
    // the position exact, so travel is preserved by construction.
    const ratio = 1.35;
    useRatio(tester, ratio);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(harness(controller, ratio));

    final gesture = await tester.startGesture(const Offset(200, 300));
    var travelled = 0.0;
    for (var step = 0; step < 300; step += 1) {
      await gesture.moveBy(const Offset(0, -0.37));
      travelled += 0.37;
      await tester.pump();
    }
    final landed = controller.offset;
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      (landed - travelled).abs(),
      lessThan(1e-6),
      reason:
          'after $travelled logical px of finger travel the offset is '
          '$landed. The position must be untouched — only the paint is '
          'corrected.',
    );
  });

  testWidgets('the correction never exceeds half a device pixel', (
    tester,
  ) async {
    // Flooring would make it up to a WHOLE pixel and always in the same
    // direction, which reads as the content lagging the finger rather
    // than as a sub-pixel nudge.
    const ratio = 1.35;
    useRatio(tester, ratio);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(harness(controller, ratio));

    final gesture = await tester.startGesture(const Offset(200, 300));
    for (var step = 0; step < 60; step += 1) {
      await gesture.moveBy(const Offset(0, -0.37));
      await tester.pump();
      final painted = tester.getTopLeft(find.byKey(marker)).dy;
      final ideal = -controller.offset;
      expect(
        (painted - ideal).abs() * ratio,
        lessThanOrEqualTo(0.5 + 1e-6),
        reason:
            'step $step nudged the content ${(painted - ideal).abs() * ratio} '
            'device px, which is more than the half-pixel budget',
      );
    }
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a degenerate grid leaves the content alone', (tester) async {
    useRatio(tester, 1.25);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 0),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: EffectiveDevicePixelRatio(
            ratio: 0,
            child: SingleChildScrollView(
              controller: controller,
              child: DeviceGridScrollBody(
                controller: controller,
                axisDirection: AxisDirection.down,
                child: const SizedBox(key: marker, width: 400, height: 4000),
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(const Offset(200, 300));
    await gesture.moveBy(const Offset(0, -37.3));
    await tester.pump();
    // No correction, and no crash: an inactive grid is a pass-through.
    expect(tester.getTopLeft(find.byKey(marker)).dy, closeTo(-37.3, 1e-6));
    await gesture.up();
    await tester.pumpAndSettle();
  });
}

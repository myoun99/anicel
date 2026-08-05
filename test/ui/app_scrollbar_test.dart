import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/app_scrollbar.dart';

void main() {
  group('AppScrollbarGeometry', () {
    test('thumb extent is proportional to viewport/content ratio', () {
      final geometry = AppScrollbarGeometry(
        trackExtent: 300,
        viewportExtent: 100,
        contentExtent: 1000,
        offset: 0,
        minThumbExtent: 24,
      );

      expect(geometry.canScroll, isTrue);
      expect(geometry.maxScroll, 900);
      expect(geometry.thumbExtent, 30);
      expect(geometry.thumbTravel, 270);
      expect(geometry.thumbStart, 0);
    });

    test('thumb extent respects the minimum', () {
      final geometry = AppScrollbarGeometry(
        trackExtent: 240,
        viewportExtent: 240,
        contentExtent: 4800,
        offset: 0,
        minThumbExtent: 32,
      );

      expect(geometry.thumbExtent, 32);
    });

    test('thumb fills the lane when there is nothing to scroll', () {
      final geometry = AppScrollbarGeometry(
        trackExtent: 240,
        viewportExtent: 240,
        contentExtent: 240,
        offset: 0,
        minThumbExtent: 32,
      );

      expect(geometry.canScroll, isFalse);
      expect(geometry.thumbExtent, 240);
      expect(geometry.thumbStart, 0);
    });

    test('offset and thumb start round-trip', () {
      final geometry = AppScrollbarGeometry(
        trackExtent: 300,
        viewportExtent: 100,
        contentExtent: 1000,
        offset: 450,
        minThumbExtent: 24,
      );

      expect(geometry.thumbStart, closeTo(135, 1e-9));
      expect(
        geometry.offsetForThumbStart(geometry.thumbStart),
        closeTo(450, 1e-9),
      );
    });

    test('offset clamps into the scrollable range', () {
      final geometry = AppScrollbarGeometry(
        trackExtent: 300,
        viewportExtent: 100,
        contentExtent: 1000,
        offset: 5000,
        minThumbExtent: 24,
      );

      expect(geometry.offset, 900);
      expect(geometry.thumbStart, geometry.thumbTravel);
    });
  });

  group('AppScrollbar', () {
    const laneSize = 300.0;

    Future<double Function()> pumpBar(
      WidgetTester tester, {
      required Axis axis,
      AppScrollbarLanePress lanePress = AppScrollbarLanePress.relativeDrag,
      double viewportExtent = 100,
      double contentExtent = 1000,
      double initialOffset = 0,
      VoidCallback? onChangeEnd,
    }) async {
      var offset = initialOffset;
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: StatefulBuilder(
              builder: (context, setState) => SizedBox(
                width: axis == Axis.horizontal ? laneSize : 14,
                height: axis == Axis.horizontal ? 14 : laneSize,
                child: AppScrollbar(
                  key: const ValueKey<String>('app-scrollbar-under-test'),
                  axis: axis,
                  offset: offset,
                  viewportExtent: viewportExtent,
                  contentExtent: contentExtent,
                  lanePress: lanePress,
                  minThumbExtent: 24,
                  thumbKey: const ValueKey<String>('app-scrollbar-thumb'),
                  laneKey: const ValueKey<String>('app-scrollbar-lane'),
                  onOffsetChanged: (next) => setState(() => offset = next),
                  onChangeEnd: onChangeEnd,
                ),
              ),
            ),
          ),
        ),
      );
      return () => offset;
    }

    double thumbStartFor(double offset) => AppScrollbarGeometry(
      trackExtent: laneSize,
      viewportExtent: 100,
      contentExtent: 1000,
      offset: offset,
      minThumbExtent: 24,
    ).thumbStart;

    testWidgets('relative drag moves the thumb 1:1 with the pointer', (
      tester,
    ) async {
      final offsetOf = await pumpBar(tester, axis: Axis.horizontal);

      await tester.drag(
        find.byKey(const ValueKey<String>('app-scrollbar-under-test')),
        const Offset(100, 0),
      );
      await tester.pump();

      expect(thumbStartFor(offsetOf()), closeTo(100, 0.001));
    });

    testWidgets('vertical relative drag moves the thumb 1:1', (tester) async {
      final offsetOf = await pumpBar(tester, axis: Axis.vertical);

      await tester.drag(
        find.byKey(const ValueKey<String>('app-scrollbar-under-test')),
        const Offset(0, 100),
      );
      await tester.pump();

      expect(thumbStartFor(offsetOf()), closeTo(100, 0.001));
    });

    testWidgets('drag clamps the offset to the scrollable range', (
      tester,
    ) async {
      final offsetOf = await pumpBar(tester, axis: Axis.horizontal);
      final bar = find.byKey(
        const ValueKey<String>('app-scrollbar-under-test'),
      );

      await tester.drag(bar, const Offset(1000, 0));
      await tester.pump();
      expect(offsetOf(), 900);

      await tester.drag(bar, const Offset(-1000, 0));
      await tester.pump();
      expect(offsetOf(), 0);
    });

    testWidgets('drag is ignored when there is no scroll range', (
      tester,
    ) async {
      var changeEnds = 0;
      final offsetOf = await pumpBar(
        tester,
        axis: Axis.horizontal,
        viewportExtent: 300,
        contentExtent: 100,
        onChangeEnd: () => changeEnds += 1,
      );

      await tester.drag(
        find.byKey(const ValueKey<String>('app-scrollbar-under-test')),
        const Offset(100, 0),
      );
      await tester.pump();

      expect(offsetOf(), 0);
      expect(changeEnds, 0);
    });

    testWidgets('lane tap jumps the thumb to the pointer in '
        'jumpToPointer mode', (tester) async {
      final offsetOf = await pumpBar(
        tester,
        axis: Axis.horizontal,
        lanePress: AppScrollbarLanePress.jumpToPointer,
      );

      final laneTopLeft = tester.getTopLeft(
        find.byKey(const ValueKey<String>('app-scrollbar-under-test')),
      );
      await tester.tapAt(laneTopLeft + const Offset(200, 7));
      await tester.pump();

      // Thumb (30 wide) centers at the pointer: start 185 of 270 travel.
      expect(thumbStartFor(offsetOf()), closeTo(185, 0.001));
    });

    testWidgets('lane tap does nothing in relativeDrag mode', (tester) async {
      final offsetOf = await pumpBar(tester, axis: Axis.horizontal);

      final laneTopLeft = tester.getTopLeft(
        find.byKey(const ValueKey<String>('app-scrollbar-under-test')),
      );
      await tester.tapAt(laneTopLeft + const Offset(200, 7));
      await tester.pump();

      expect(offsetOf(), 0);
    });

    testWidgets('onChangeEnd fires exactly once on drag end', (tester) async {
      var changeEnds = 0;
      await pumpBar(
        tester,
        axis: Axis.horizontal,
        onChangeEnd: () => changeEnds += 1,
      );

      final gesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(const ValueKey<String>('app-scrollbar-under-test')),
        ),
      );
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(changeEnds, 0);

      await gesture.up();
      await tester.pump();
      expect(changeEnds, 1);
    });

    testWidgets('onChangeEnd fires exactly once on drag cancel', (
      tester,
    ) async {
      var changeEnds = 0;
      await pumpBar(
        tester,
        axis: Axis.horizontal,
        onChangeEnd: () => changeEnds += 1,
      );

      final gesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(const ValueKey<String>('app-scrollbar-under-test')),
        ),
      );
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();

      await gesture.cancel();
      await tester.pump();
      expect(changeEnds, 1);
    });

    Color? thumbColour(WidgetTester tester) {
      final thumb = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey<String>('app-scrollbar-thumb')),
      );
      return (thumb.decoration as BoxDecoration?)?.color;
    }

    double thumbThickness(WidgetTester tester, Axis axis) {
      final thumb = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey<String>('app-scrollbar-thumb')),
      );
      final constraints = thumb.constraints!;
      return axis == Axis.vertical
          ? constraints.maxWidth
          : constraints.maxHeight;
    }

    testWidgets('a press turns the thumb accent and releasing restores it', (
      tester,
    ) async {
      await pumpBar(tester, axis: Axis.vertical);
      final bar = find.byKey(
        const ValueKey<String>('app-scrollbar-under-test'),
      );
      expect(thumbColour(tester), AppColors.hairlineStrong);

      final gesture = await tester.startGesture(tester.getCenter(bar));
      await tester.pump();
      expect(thumbColour(tester), AppColors.accent);

      await gesture.up();
      await tester.pump();
      expect(thumbColour(tester), AppColors.hairlineStrong);
    });

    testWidgets('a press lights the thumb even with nothing to scroll', (
      tester,
    ) async {
      // The timeline rails live in this state whenever the layer list is
      // short: the thumb fills the lane and the drag recognisers bail out
      // early, which is exactly why pressing them used to do nothing at
      // all — no movement AND no colour (user-reported).
      await pumpBar(
        tester,
        axis: Axis.vertical,
        viewportExtent: 300,
        contentExtent: 100,
      );
      final bar = find.byKey(
        const ValueKey<String>('app-scrollbar-under-test'),
      );

      final gesture = await tester.startGesture(tester.getCenter(bar));
      await tester.pump();
      expect(thumbColour(tester), AppColors.accent);

      await gesture.up();
      await tester.pump();
      expect(thumbColour(tester), AppColors.hairlineStrong);
    });

    testWidgets('hovering brightens the thumb to white', (tester) async {
      await pumpBar(tester, axis: Axis.vertical);
      final bar = find.byKey(
        const ValueKey<String>('app-scrollbar-under-test'),
      );

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      await mouse.moveTo(tester.getCenter(bar));
      await tester.pump();
      expect(thumbColour(tester), Colors.white);

      // Well clear of the bar: it is pinned to the top-left, so the origin
      // is still inside it.
      await mouse.moveTo(const Offset(200, 200));
      await tester.pump();
      expect(thumbColour(tester), AppColors.hairlineStrong);
    });

    testWidgets('thumb thickness is the same at rest, hovered and pressed', (
      tester,
    ) async {
      await pumpBar(tester, axis: Axis.vertical);
      final bar = find.byKey(
        const ValueKey<String>('app-scrollbar-under-test'),
      );
      final atRest = thumbThickness(tester, Axis.vertical);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(bar));
      await tester.pump();
      expect(thumbThickness(tester, Axis.vertical), atRest);

      final gesture = await tester.startGesture(tester.getCenter(bar));
      await tester.pump();
      expect(thumbThickness(tester, Axis.vertical), atRest);

      await gesture.up();
      await tester.pump();
      expect(thumbThickness(tester, Axis.vertical), atRest);
    });
  });

  group('AppControllerScrollbar', () {
    testWidgets('thumb drag scrolls the controller', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 240,
              height: 120,
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      controller: controller,
                      child: const SizedBox(width: 720, height: 10),
                    ),
                  ),
                  SizedBox(
                    height: 14,
                    child: AppControllerScrollbar(
                      controller: controller,
                      axis: Axis.horizontal,
                      thumbKey: const ValueKey<String>('controller-thumb'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.drag(
        find.byKey(const ValueKey<String>('controller-thumb')),
        const Offset(60, 0),
      );
      await tester.pump();

      expect(controller.offset, greaterThan(0));
      expect(controller.offset, lessThanOrEqualTo(480));
    });

    testWidgets('programmatic jump moves the thumb', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 240,
              height: 120,
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      controller: controller,
                      child: const SizedBox(width: 720, height: 10),
                    ),
                  ),
                  SizedBox(
                    height: 14,
                    child: AppControllerScrollbar(
                      controller: controller,
                      axis: Axis.horizontal,
                      thumbKey: const ValueKey<String>('controller-thumb'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final before = tester.getTopLeft(
        find.byKey(const ValueKey<String>('controller-thumb')),
      );
      controller.jumpTo(240);
      await tester.pump();
      final after = tester.getTopLeft(
        find.byKey(const ValueKey<String>('controller-thumb')),
      );

      expect(after.dx, greaterThan(before.dx));
    });

    testWidgets('fallback extents size the thumb before attachment', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 240,
              height: 14,
              child: AppControllerScrollbar(
                controller: controller,
                axis: Axis.horizontal,
                minThumbExtent: 32,
                fallbackViewportExtent: 240,
                fallbackContentExtent: 720,
                thumbKey: const ValueKey<String>('controller-thumb'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final thumbPositioned = tester.widget<Positioned>(
        find.ancestor(
          of: find.byKey(const ValueKey<String>('controller-thumb')),
          matching: find.byType(Positioned),
        ),
      );
      expect(thumbPositioned.width, 80);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_vertical_scrollbar_rail.dart';

void main() {
  const railKey = ValueKey<String>('timeline-vertical-scrollbar');
  const trackKey = ValueKey<String>('timeline-vertical-scrollbar-track');
  const thumbKey = ValueKey<String>('timeline-vertical-scrollbar-thumb');

  Future<void> pumpRail(
    WidgetTester tester, {
    required ScrollController controller,
    double viewportHeight = 120,
    double contentHeight = 360,
    bool attachControllerToScrollable = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          // Align breaks the route's tight constraints so the SizedBox
          // actually sizes the rail (the unified scrollbar derives its
          // track from real layout, not the passed extents).
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 12,
              height: viewportHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (attachControllerToScrollable)
                    SingleChildScrollView(
                      controller: controller,
                      child: SizedBox(width: 12, height: contentHeight),
                    ),
                  TimelineVerticalScrollbarRail(
                    controller: controller,
                    viewportHeight: viewportHeight,
                    contentHeight: contentHeight,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Positioned thumbPositioned(WidgetTester tester) {
    return tester.widget<Positioned>(
      find.ancestor(
        of: find.byKey(thumbKey),
        matching: find.byType(Positioned),
      ),
    );
  }

  testWidgets('rail stable key exists exactly once', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await pumpRail(tester, controller: controller);

    expect(find.byKey(railKey), findsOneWidget);
  });

  testWidgets('track and thumb keys exist exactly once', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await pumpRail(tester, controller: controller);

    expect(find.byKey(trackKey), findsOneWidget);
    expect(find.byKey(thumbKey), findsOneWidget);
  });

  testWidgets('thumb is visible when content is taller than viewport', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await pumpRail(
      tester,
      controller: controller,
      viewportHeight: 120,
      contentHeight: 360,
    );

    expect(find.byKey(thumbKey), findsOneWidget);
    expect(thumbPositioned(tester).height, greaterThan(0));
  });

  testWidgets('thumb height respects minimum height', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await pumpRail(
      tester,
      controller: controller,
      viewportHeight: 120,
      contentHeight: 2400,
    );

    expect(thumbPositioned(tester).height, 32);
  });

  testWidgets('thumb fills viewport when content does not exceed viewport', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await pumpRail(
      tester,
      controller: controller,
      viewportHeight: 120,
      contentHeight: 120,
    );

    expect(thumbPositioned(tester).height, 120);
  });

  testWidgets(
    'rail uses the provided external controller and exposes track tap handler',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await pumpRail(
        tester,
        controller: controller,
        viewportHeight: 120,
        contentHeight: 360,
        attachControllerToScrollable: true,
      );

      expect(controller.hasClients, isTrue);

      final rail = tester.widget<TimelineVerticalScrollbarRail>(
        find.byKey(railKey),
      );
      expect(rail.controller, same(controller));

      final trackGestureDetector = tester.widget<GestureDetector>(
        find.ancestor(
          of: find.byKey(trackKey),
          matching: find.byType(GestureDetector),
        ),
      );

      expect(trackGestureDetector.onTapDown, isNotNull);
    },
  );
}

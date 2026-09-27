import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_horizontal_scrollbar_rail.dart';

void main() {
  const scrollbarKey = ValueKey<String>('timeline-horizontal-scrollbar');
  const railKey = ValueKey<String>('timeline-bottom-scrollbar-rail');
  const trackKey = ValueKey<String>('timeline-horizontal-scrollbar-track');
  const thumbKey = ValueKey<String>('timeline-horizontal-scrollbar-thumb');

  Future<void> pumpRail(
    WidgetTester tester, {
    required ScrollController controller,
    double viewportWidth = 240,
    double contentWidth = 720,
    double height = 16,
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
              width: viewportWidth,
              height: height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (attachControllerToScrollable)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      controller: controller,
                      child: SizedBox(width: contentWidth, height: height),
                    ),
                  TimelineHorizontalScrollbarRail(
                    key: scrollbarKey,
                    controller: controller,
                    viewportWidth: viewportWidth,
                    contentWidth: contentWidth,
                    height: height,
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

    expect(find.byKey(scrollbarKey), findsOneWidget);
  });

  testWidgets('internal rail, track, and thumb keys exist exactly once', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await pumpRail(tester, controller: controller);

    expect(find.byKey(railKey), findsOneWidget);
    expect(find.byKey(trackKey), findsOneWidget);
    expect(find.byKey(thumbKey), findsOneWidget);
  });

  testWidgets('thumb is visible when content is wider than viewport', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await pumpRail(
      tester,
      controller: controller,
      viewportWidth: 240,
      contentWidth: 720,
      height: 16,
    );

    expect(find.byKey(thumbKey), findsOneWidget);
    expect(thumbPositioned(tester).width, greaterThan(0));
  });

  testWidgets('thumb width respects minimum width', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await pumpRail(
      tester,
      controller: controller,
      viewportWidth: 240,
      contentWidth: 4800,
      height: 16,
    );

    expect(thumbPositioned(tester).width, 32);
  });

  testWidgets('thumb fills viewport when content does not exceed viewport', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await pumpRail(
      tester,
      controller: controller,
      viewportWidth: 240,
      contentWidth: 240,
      height: 16,
    );

    expect(thumbPositioned(tester).width, 240);
  });

  testWidgets(
    'rail uses provided external controller, and its lane and thumb act '
    'on it',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await pumpRail(
        tester,
        controller: controller,
        viewportWidth: 240,
        contentWidth: 720,
        height: 16,
        attachControllerToScrollable: true,
      );

      expect(controller.hasClients, isTrue);

      final rail = tester.widget<TimelineHorizontalScrollbarRail>(
        find.byKey(scrollbarKey),
      );
      expect(rail.controller, same(controller));

      // Measured by what they DO, not by which detector they hang on: the
      // thumb's drag is the bar's grip now (F-202), not a GestureDetector's.
      await tester.tapAt(
        tester.getTopLeft(find.byKey(trackKey)) + const Offset(220, 8),
      );
      await tester.pump();
      expect(controller.offset, greaterThan(0), reason: 'a lane tap jumps');
      final jumped = controller.offset;

      await tester.drag(find.byKey(thumbKey), const Offset(-60, 0));
      await tester.pump();
      expect(controller.offset, lessThan(jumped), reason: 'the thumb drags');
    },
  );
}

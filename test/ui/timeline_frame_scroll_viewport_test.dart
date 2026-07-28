import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_scroll_viewport.dart';

void main() {
  const horizontalScrollbarViewportKey = ValueKey<String>(
    'timeline-horizontal-scrollbar-viewport',
  );
  const frameScrollViewportKey = ValueKey<String>(
    'timeline-frame-scroll-viewport',
  );
  const frameScrollContentKey = ValueKey<String>(
    'timeline-frame-scroll-content',
  );
  const childKey = ValueKey<String>('test-frame-scroll-child');

  Future<void> pumpViewport(
    WidgetTester tester, {
    required ScrollController controller,
    double viewportWidth = 240,
    double viewportHeight = 120,
    double contentWidth = 720,
    double contentHeight = 120,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SizedBox(
            width: viewportWidth,
            height: viewportHeight,
            child: TimelineFrameScrollViewport(
              controller: controller,
              contentWidth: contentWidth,
              contentHeight: contentHeight,
              child: const SizedBox(key: childKey, width: 720, height: 120),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('viewport stable keys exist exactly once without duplicates', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await pumpViewport(tester, controller: controller);

    expect(find.byKey(horizontalScrollbarViewportKey), findsOneWidget);
    expect(find.byKey(frameScrollViewportKey), findsOneWidget);
    expect(find.byKey(frameScrollContentKey), findsOneWidget);
  });

  testWidgets('provided child renders exactly once', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await pumpViewport(tester, controller: controller);

    expect(find.byKey(childKey), findsOneWidget);
  });

  testWidgets('provided controller is passed to horizontal scroll view', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await pumpViewport(tester, controller: controller);

    final scrollView = tester.widget<SingleChildScrollView>(
      find.byKey(frameScrollViewportKey),
    );

    expect(scrollView.controller, same(controller));
    expect(scrollView.scrollDirection, Axis.horizontal);
  });

  testWidgets('content width and height are preserved', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await pumpViewport(
      tester,
      controller: controller,
      contentWidth: 720,
      contentHeight: 120,
    );

    final contentSubtree = tester.widget<KeyedSubtree>(
      find.byKey(frameScrollContentKey),
    );
    final contentSizedBox = contentSubtree.child as SizedBox;

    expect(contentSizedBox.width, 720);
    expect(contentSizedBox.height, 120);
  });
}

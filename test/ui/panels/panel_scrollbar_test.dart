import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/panels/panel_scrollbar.dart';
import 'package:anicel/src/ui/widgets/app_scrollbar.dart';

void main() {
  group('PanelScrollbar', () {
    const viewportWidth = 200.0;
    const viewportHeight = 100.0;

    Future<void> pumpPanel(
      WidgetTester tester, {
      required ScrollController controller,
      required double contentHeight,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: viewportWidth,
              height: viewportHeight,
              child: PanelScrollbar(
                controller: controller,
                child: SingleChildScrollView(
                  controller: controller,
                  child: SizedBox(
                    key: const ValueKey<String>('panel-content'),
                    width: double.infinity,
                    height: contentHeight,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      // The bar's visibility rides on scroll metrics, which arrive during
      // layout and schedule a rebuild for the next frame.
      await tester.pump();
      await tester.pump();
    }

    testWidgets('no bar at all while the content fits', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await pumpPanel(tester, controller: controller, contentHeight: 50);

      expect(find.byType(AppControllerScrollbar), findsNothing);
    });

    testWidgets('the bar appears once the content overflows', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await pumpPanel(tester, controller: controller, contentHeight: 500);

      expect(find.byType(AppControllerScrollbar), findsOneWidget);
    });

    testWidgets('the bar takes no width from the content', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await pumpPanel(tester, controller: controller, contentHeight: 500);

      // The whole point of the overlay: an overflowing panel is exactly as
      // wide as one that fits. A reserved lane would shave the narrow one.
      expect(
        tester.getSize(find.byKey(const ValueKey<String>('panel-content'))),
        const Size(viewportWidth, 500),
      );
    });

    testWidgets('the lane is the narrow step of the vocabulary', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await pumpPanel(tester, controller: controller, contentHeight: 500);

      expect(
        tester.getSize(find.byType(AppControllerScrollbar)),
        const Size(AppScrollbarLane.narrow, viewportHeight),
      );
    });
  });
}

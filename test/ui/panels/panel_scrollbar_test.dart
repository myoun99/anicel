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
      Axis axis = Axis.vertical,
      double contentWidth = double.infinity,
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
                  scrollDirection: axis,
                  controller: controller,
                  child: SizedBox(
                    key: const ValueKey<String>('panel-content'),
                    width: contentWidth,
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

    // ㉔ (user, 2026-08-12): 「넘칠 때 뜨는 스크롤바의 아래 패딩을 없애고
    // 영역 바닥에 딱 붙인다 (…) 겹치는 건 문제없음」. The lane was already
    // flush; the THUMB sat centred in it, so a 12px lane left 4px of air on
    // the outside of a 4px bar.
    testWidgets('the thumb rides the edge the lane is pinned to, with no '
        'air outside it', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await pumpPanel(tester, controller: controller, contentHeight: 500);

      final lane = tester.getRect(find.byType(AppControllerScrollbar));
      final thumb = tester.getRect(find.byType(AnimatedContainer));
      expect(
        thumb.right,
        lane.right,
        reason: 'a vertical bar sits on the RIGHT edge of its area',
      );
      // And it did not become a fat bar to get there.
      expect(thumb.width, lessThan(lane.width));
    });

    testWidgets('a horizontal bar sits on the BOTTOM edge', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await pumpPanel(
        tester,
        controller: controller,
        axis: Axis.horizontal,
        contentWidth: 500,
        contentHeight: double.infinity,
      );

      final lane = tester.getRect(find.byType(AppControllerScrollbar));
      final thumb = tester.getRect(find.byType(AnimatedContainer));
      expect(thumb.bottom, lane.bottom);
      expect(lane.bottom, viewportHeight, reason: 'the area\'s own bottom');
      expect(thumb.height, lessThan(lane.height));
    });
  });
}

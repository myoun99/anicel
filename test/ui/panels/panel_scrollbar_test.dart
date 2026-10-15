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
                axis: axis,
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

    // 🚨(playback-frame-raster-is-the-whole-window, 10-12) The bar built
    // again is laid out by the LayoutBuilder above it, and that layout
    // paints the panel holding it again — the timeline dock's scroller bars
    // did so at every page turn of a run, for scrollables nested in their
    // panel. The panel here: a LayoutBuilder under a painter that counts.
    Future<_Paints> pumpHeldPanel(
      WidgetTester tester, {
      required ScrollController controller,
      required Widget content,
    }) async {
      final paints = _Paints();
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              child: SizedBox(
                width: viewportWidth,
                height: viewportHeight,
                child: CustomPaint(
                  painter: paints,
                  child: LayoutBuilder(
                    builder: (context, constraints) => PanelScrollbar(
                      controller: controller,
                      axis: Axis.vertical,
                      child: content,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return paints;
    }

    /// Long enough for a notification, the bar's frame-late rebuild and the
    /// layout that rebuild asks for.
    Future<void> settle(WidgetTester tester) async {
      for (var frame = 0; frame < 4; frame += 1) {
        await tester.pump();
      }
    }

    testWidgets('a scrollable NESTED in its content moving builds no bar '
        'around it, so nothing of the panel is painted again', (tester) async {
      final outer = ScrollController();
      final inner = ScrollController();
      addTearDown(outer.dispose);
      addTearDown(inner.dispose);
      final paints = await pumpHeldPanel(
        tester,
        controller: outer,
        content: SingleChildScrollView(
          controller: outer,
          child: Column(
            children: [
              SizedBox(
                height: 40,
                child: ListView(
                  controller: inner,
                  scrollDirection: Axis.horizontal,
                  children: const [SizedBox(width: 600)],
                ),
              ),
              const SizedBox(height: 300),
            ],
          ),
        ),
      );
      expect(find.byType(AppControllerScrollbar), findsOneWidget);
      final before = paints.count;

      inner.jumpTo(100);
      await settle(tester);

      expect(inner.offset, 100);
      expect(
        paints.count,
        before,
        reason: 'the inner list\'s metrics are not the outer bar\'s',
      );
    });

    testWidgets('its OWN list scrolling builds no bar either — the thumb '
        'follows the offset by itself', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final paints = await pumpHeldPanel(
        tester,
        controller: controller,
        content: ListView(
          controller: controller,
          children: const [SizedBox(height: 600)],
        ),
      );
      final before = paints.count;

      controller.jumpTo(50);
      await settle(tester);

      expect(
        paints.count,
        before,
        reason: 'an offset moves the thumb and nothing the bar shows else',
      );
      expect(
        tester.widget<AppScrollbar>(find.byType(AppScrollbar)).offset,
        50,
      );
    });

    testWidgets('content that grows under a still offset still measures the '
        'thumb again', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final length = ValueNotifier<double>(300);
      addTearDown(length.dispose);
      await pumpHeldPanel(
        tester,
        controller: controller,
        content: SingleChildScrollView(
          controller: controller,
          child: ValueListenableBuilder<double>(
            valueListenable: length,
            builder: (context, height, _) => SizedBox(height: height),
          ),
        ),
      );
      double content() =>
          tester.widget<AppScrollbar>(find.byType(AppScrollbar)).contentExtent;
      expect(content(), 300);

      length.value = 600;
      await settle(tester);

      expect(content(), 600);
    });
  });
}

/// Counts how often the panel it stands under is painted.
class _Paints extends CustomPainter {
  int count = 0;

  @override
  void paint(Canvas canvas, Size size) {
    count += 1;
  }

  @override
  bool shouldRepaint(_Paints oldDelegate) => false;
}

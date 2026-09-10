import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/panels/panel_scrollbar.dart';
import 'package:anicel/src/ui/theme/app_scroll_behavior.dart';
import 'package:anicel/src/ui/widgets/app_scrollbar.dart';
import 'package:anicel/src/ui/widgets/content_scrollbar.dart';

/// H35 (유저 2026-09-11): 「내용물에 공통적으로 스크롤바 넣자. 항상 보이도록.
/// 법 하나로 최대한 통일하면서」 — the shared lane the two tool panels use.
void main() {
  Widget host({required int rows, ScrollController? controller}) =>
      MaterialApp(
        // The app's own behaviour, so the overlay bar it hands every
        // scrollable is really in play underneath.
        scrollBehavior: const AppScrollBehavior(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 300,
              child: ContentScrollbar(
                controller: controller,
                builder: (context, controller) => ListView(
                  controller: controller,
                  children: [
                    for (var i = 0; i < rows; i += 1)
                      SizedBox(height: 40, child: Text('row $i')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Rect laneOf(WidgetTester tester) =>
      tester.getRect(find.byType(AppControllerScrollbar));

  testWidgets('🚨the lane is there when nothing overflows, and nothing is '
      'drawn under it', (tester) async {
    await tester.pumpWidget(host(rows: 2));
    await tester.pumpAndSettle();

    final lane = laneOf(tester);
    expect(lane.width, AppScrollbarLane.wide, reason: 'CLAUDE.md: 레인 16px');
    expect(lane.height, 300, reason: 'the whole height of the content');
    expect(
      tester.getRect(find.byType(ListView)).right,
      lane.left,
      reason: 'a reserved lane beside the content, not a bar laid over it',
    );
  });

  testWidgets('dragging the lane scrolls the content it belongs to', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(rows: 40, controller: controller));
    await tester.pumpAndSettle();

    final lane = laneOf(tester);
    await tester.dragFrom(
      lane.topCenter + const Offset(0, 10),
      const Offset(0, 120),
    );
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(0));
  });

  testWidgets('⛔on a desktop the overlay bar stays off underneath — one bar, '
      'not two', (tester) async {
    await tester.pumpWidget(host(rows: 40));
    await tester.pumpAndSettle();

    expect(find.byType(PanelScrollbar), findsNothing);
    expect(find.byType(AppControllerScrollbar), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}

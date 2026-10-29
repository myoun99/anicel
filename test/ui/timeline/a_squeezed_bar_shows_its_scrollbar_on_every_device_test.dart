import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_scroll_behavior.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/timeline_command_bar.dart';
import 'package:anicel/src/ui/widgets/app_scrollbar.dart';
import 'package:anicel/src/ui/widgets/kept_tail_row.dart' show FoldFloor;
import 'package:anicel/src/ui/widgets/tick_layer.dart';

/// 🗣️F-502 (유저 2026-10-29): 「타임라인 왼쪽 묶음 … 알약쪽 줄어들면 바로
/// 스크롤바 생기게. 갤탭에서 확인한바 안생김. 알약이든 뭐든 줄어들어서
/// 잘리면. 그 옆 줌쪽버튼이든」 — a frame panel's command bar, squeezed, says
/// what it cut away with the app's bar on every device: the pills' scroller
/// once the pills give way, the zoom's once the right group does.
void main() {
  /// A bar [width] wide (inside the 800 the test window is), as the app
  /// lays it: the transport, pills that give way down to the cut pill, and
  /// the right group down to its fit.
  Future<void> pumpBar(WidgetTester tester, double width) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        scrollBehavior: const AppScrollBehavior(),
        home: TickLayer.host(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: const TimelineCommandBar(
                transport: SizedBox(width: 60, height: 28),
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FoldFloor(child: SizedBox(width: 80, height: 28)),
                    SizedBox(width: 300, height: 28),
                  ],
                ),
                cluster: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 200, height: 28),
                    FoldFloor(child: SizedBox(width: 40, height: 28)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The bar's scrollers, pills first, and whether each wears a bar.
  List<bool> barred(WidgetTester tester) => [
    for (final scroller in find
        .descendant(
          of: find.byType(TimelineCommandBar),
          matching: find.byType(SingleChildScrollView),
        )
        .evaluate())
      find
          .descendant(
            of: find.byWidget(scroller.widget),
            matching: find.byType(AppControllerScrollbar),
          )
          .evaluate()
          .isNotEmpty,
  ];

  testWidgets('wide enough, it wears none', (tester) async {
    await pumpBar(tester, 780);
    expect(barred(tester), [false, false]);
  }, variant: TargetPlatformVariant.all());

  testWidgets('the pills cut away, their scroller wears one at once', (
    tester,
  ) async {
    await pumpBar(tester, 560);
    expect(barred(tester), [true, false]);
  }, variant: TargetPlatformVariant.all());

  testWidgets('the right group cut away too, the zoom\'s scroller wears one',
      (tester) async {
    await pumpBar(tester, 260);
    expect(barred(tester), [true, true]);
  }, variant: TargetPlatformVariant.all());
}

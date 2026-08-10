import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';
import 'package:anicel/src/ui/panels/panel_collapsed_scope.dart';

/// The shell's COLLAPSE contract (유저 확정, 2026-08-10).
///
/// The bug this exists to keep closed: folding used to be a CROP. The dock
/// handed the panel less height than its floor, the shell's overflow branch
/// put it in a vertical scroller at its natural size, and what showed was
/// whatever happened to be in the top of it — measured on the real timeline,
/// 40px of budget over a 136px floor showed the command bar and four pixels
/// of grid. Nothing about that was a decision; it was arithmetic nobody had
/// looked at, and every tab that ever lands in the bottom dock inherits it.
///
/// So the answer is a shell contract: the tab says how tall it needs to be
/// when folded, the shell tells it that it IS folded, and a tab that says
/// nothing gets shown nothing.
void main() {
  const collapsedExtent = 36.0;

  /// A panel that renders its "bar" always and its "body" only when the
  /// scope says it is not collapsed — the shape both frame panels take.
  Widget panel(BuildContext context) => Column(
    children: [
      const SizedBox(height: collapsedExtent, child: Text('BAR')),
      Expanded(
        child: Offstage(
          offstage: PanelCollapsedScope.of(context),
          child: const Text('BODY'),
        ),
      ),
    ],
  );

  Future<void> pumpGroup(
    WidgetTester tester, {
    required bool collapsed,
    double tabCollapsedExtent = collapsedExtent,
    double? minContentHeight = 200,
  }) {
    final height =
        EditorPanelTabs.stripHeight +
        (collapsed ? tabCollapsedExtent : 240.0);
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 800,
              height: height,
              child: EditorPanelTabs(
                collapsed: collapsed,
                stripAtBottom: true,
                activeTabId: 'a',
                onTabSelected: (_) {},
                tabs: [
                  EditorPanelTab(
                    id: 'a',
                    label: 'A',
                    icon: Icons.abc,
                    minContentHeight: minContentHeight,
                    collapsedExtent: tabCollapsedExtent,
                    staticRaster: false,
                    builder: panel,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('expanded: the panel gets its whole body', (tester) async {
    await pumpGroup(tester, collapsed: false);
    expect(find.text('BAR'), findsOneWidget);
    expect(find.text('BODY'), findsOneWidget);
  });

  testWidgets('collapsed: the bar survives and the body goes offstage', (
    tester,
  ) async {
    await pumpGroup(tester, collapsed: true);
    expect(find.text('BAR'), findsOneWidget);
    expect(
      find.text('BODY'),
      findsNothing,
      reason: '접으면 버튼행만 — the body is offstage, not merely clipped',
    );
  });

  testWidgets('collapsed: NO overflow scroller, so nothing is cropped', (
    tester,
  ) async {
    // The whole bug in one assertion. The tab declares a 200px floor and is
    // handed 36; before the contract that put it in a `SingleChildScrollView`
    // at 200 and showed the top 36 of it.
    await pumpGroup(tester, collapsed: true);
    expect(find.byType(SingleChildScrollView), findsNothing);

    final bar = tester.getRect(find.text('BAR'));
    final strip = tester.getRect(find.byType(EditorPanelTabs));
    expect(
      bar.top,
      greaterThanOrEqualTo(strip.top - 0.01),
      reason: 'the bar sits inside the region rather than scrolled out of it',
    );
  });

  testWidgets('expanded: a panel under its floor still gets the scroller', (
    tester,
  ) async {
    // The overflow branch is not deleted — it is right for a frame panel
    // squeezed into a side rail. It is only wrong for a fold.
    await pumpGroup(tester, collapsed: false, minContentHeight: 900);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('a tab that declares no collapsed form shows NOTHING', (
    tester,
  ) async {
    // 유저 확정 for 콘티·뷰어: 「진짜 깔끔하게 내용물 안 보이게」. The subtree
    // stays MOUNTED (a keep-alive tab must not lose its state to a fold);
    // it simply does not lay out.
    await pumpGroup(tester, collapsed: true, tabCollapsedExtent: 0);
    expect(find.text('BAR'), findsNothing);
    expect(find.text('BODY'), findsNothing);
  });

  testWidgets('collapsing reaches a KEEP-ALIVE panel through the scope', (
    tester,
  ) async {
    // The trap this pins: keep-alive tabs are served from a widget cache, so
    // the instance handed to the framework is identical across folds. An
    // inherited dependency is what still reaches them — which is why the
    // scope sits OUTSIDE that cache.
    var collapsed = false;
    late StateSetter setOuter;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return SizedBox(
                height: EditorPanelTabs.stripHeight + (collapsed ? 36 : 240),
                child: EditorPanelTabs(
                  collapsed: collapsed,
                  activeTabId: 'a',
                  onTabSelected: (_) {},
                  tabs: [
                    EditorPanelTab(
                      id: 'a',
                      label: 'A',
                      icon: Icons.abc,
                      keepAlive: true,
                      collapsedExtent: 36,
                      staticRaster: false,
                      builder: panel,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    expect(find.text('BODY'), findsOneWidget);

    setOuter(() => collapsed = true);
    await tester.pump();
    expect(
      find.text('BODY'),
      findsNothing,
      reason: 'the cached subtree must still hear the fold',
    );

    setOuter(() => collapsed = false);
    await tester.pump();
    expect(find.text('BODY'), findsOneWidget);
  });
}

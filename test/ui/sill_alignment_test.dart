import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';
import 'package:anicel/src/ui/widgets/command_pill.dart';

/// ⑪ 유저 2026-08-12: 「타임라인 문턱에 있는 재생이나 설정버튼 왜
/// 우측정렬안했지? 말한것들좀 지키자. 그리고 설정버튼은 알약 테두리 없애고
/// 그냥 일반버튼으로」.
///
/// The sill's right edge is the whole reason the transport was moved there
/// (유저 2026-08-10: 「왼쪽 정렬이면 패널을 추가할 때 재생 버튼이 밀린다」), so
/// the test asks the question that rule is about: does the group stay put?
void main() {
  Future<void> pump(WidgetTester tester, double width) async {
    await tester.binding.setSurfaceSize(Size(width, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
  }

  Finder settings() =>
      find.byKey(const ValueKey<String>('project-settings-button'));

  testWidgets('the sill group sits at the RIGHT edge, not after the tabs', (
    tester,
  ) async {
    await pump(tester, 1700);
    final button = tester.getRect(settings());
    // The STRIP it lives in — the sill spans the region, so "right aligned"
    // means "at that strip's edge" rather than any window number.
    final region = tester.getRect(
      find.ancestor(of: settings(), matching: find.byType(EditorPanelTabs)).first,
    );
    expect(
      region.right - button.right,
      lessThan(120),
      reason: 'a loose Flexible left this group sitting straight after the '
          'tabs, which reads as left-aligned and slides when a tab is added',
    );
  });

  testWidgets('the ⚙ is a plain button — no pill border on the sill', (
    tester,
  ) async {
    await pump(tester, 1700);
    expect(settings(), findsOneWidget);
    expect(
      find.ancestor(of: settings(), matching: find.byType(CommandPill)),
      findsNothing,
      reason: 'the sill is a row of state-machine icons; a border around one '
          'of them says the opposite of what its neighbours say',
    );
  });
}

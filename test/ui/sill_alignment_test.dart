import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';
import 'package:anicel/src/ui/timeline/frame_panel_sill_controls.dart';

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

  // The group itself: the ⚙ that measured it left the sill for the top
  // strip (답 playback-quality-home-Q1 「프로젝트 설정으로 같이」).
  Finder sill() => find.byType(FramePanelSillControls);

  testWidgets('the sill group sits at the RIGHT edge, not after the tabs', (
    tester,
  ) async {
    await pump(tester, 1700);
    final group = tester.getRect(sill());
    // The STRIP it lives in — the sill spans the region, so "right aligned"
    // means "at that strip's edge" rather than any window number.
    final region = tester.getRect(
      find.ancestor(of: sill(), matching: find.byType(EditorPanelTabs)).first,
    );
    expect(
      region.right - group.right,
      lessThan(120),
      reason: 'a loose Flexible left this group sitting straight after the '
          'tabs, which reads as left-aligned and slides when a tab is added',
    );
  });
}

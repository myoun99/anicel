import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:anicel/src/ui/session/panel_view_memory.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

/// F-267 (유저 2026-10-01): 「콘티패널,타임라인패널 스크롤상태, 콘티패널,
/// 그리고 각 컷들 줌 상태도 프로젝트 파일에 기록해서 다시 열면 그대로
/// 열리도록」 — so each project holds its own. The window held one conte zoom
/// and one scroll per panel for every tab: a project came on screen at the
/// zoom another was left at, and a save of a tab behind wrote down the one in
/// front.
void main() {
  testWidgets('a project tab shows the conte at ITS zoom — not at the one '
      'the last tab was left at', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(initialProject: createDefaultProject()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();
    final projects = tester
        .widget<EditorTopStrip>(find.byType(EditorTopStrip))
        .projects;
    double conteZoom() => tester
        .widget<StoryboardPanel>(find.byType(StoryboardPanel))
        .pixelsPerFrame;

    final first = projects.active;
    first.panelViews.storyboardPixelsPerFrame.value = 4;
    await tester.pumpAndSettle();
    expect(conteZoom(), 4, reason: 'premise: the conte shows the zoom');

    final second = projects.open(createDefaultProject());
    await tester.pumpAndSettle();
    expect(projects.active, same(second), reason: 'premise: B is in front');
    expect(
      conteZoom(),
      PanelViewMemory.defaultStoryboardPixelsPerFrame,
      reason: 'B was never zoomed — its conte opens at the default',
    );

    projects.activate(first);
    await tester.pumpAndSettle();
    expect(conteZoom(), 4, reason: 'and A comes back at its own');
  });
}

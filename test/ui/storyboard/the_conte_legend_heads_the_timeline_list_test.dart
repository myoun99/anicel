import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard/timeline_list.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';

import '../../helpers/home_page_probes.dart';

/// 🗣️I-150 (유저 2026-11-03): 「위치는 콘티패널에서 레전드의 레이어 텍스트
/// 없애고, 트랙이란 버튼 신설 … 기본값은 트랙1이고 누르면 리스트 팝오버로
/// 트랙 리스트뜸. 해당 영역 전부 버튼이고, 리스트에서 선택되있는 트랙이
/// 텍스트 강조색 … 오른쪽정렬로 오른쪽부터 삭제, 그 왼쪽에 복제 아이콘, 그
/// 왼쪽에 연필아이콘」 — and 「트랙바꾸면 그래서 바뀌도록」.
void main() {
  late EditorSessionManager session;

  Finder inStoryboard(String key) => find.descendant(
    of: find.byType(StoryboardPanel),
    matching: find.byKey(ValueKey<String>(key)),
  );

  Finder byKey(String key) => find.byKey(ValueKey<String>(key));

  Future<void> pumpConte(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: newUntitledProject())),
    );
    await tester.pumpAndSettle();
    await showStoryboardPanel(tester);
    session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
  }

  String headingWords(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(
          of: inStoryboard('legend-heading'),
          matching: byKey('legend-layer'),
        ),
      )
      .data!;

  Future<void> openList(WidgetTester tester) async {
    await tester.tap(inStoryboard('legend-heading'));
    await tester.pumpAndSettle();
  }

  String rowOf(int at) =>
      'timeline-${session.timelineVerbs.timelines[at].id.value}';

  testWidgets('the conte legend\'s heading is a button naming the open '
      'timeline, where the rows\' heading stood', (tester) async {
    await pumpConte(tester);

    expect(headingWords(tester), AppText.strings.timelineNumbered(1));
    expect(
      find.text(AppText.strings.tlLegendLayer),
      findsNothing,
      reason: 'the conte panel\'s heading is the button\'s',
    );
  });

  testWidgets('the list: a ＋ that opens a new one, the open one in the '
      'accent, and choosing a row opens it', (tester) async {
    await pumpConte(tester);
    await openList(tester);
    await tester.tap(byKey('timeline-add'));
    await tester.pumpAndSettle();

    expect(session.timelineVerbs.timelines, hasLength(2));
    expect(headingWords(tester), AppText.strings.timelineNumbered(2));

    await openList(tester);
    Color inkOf(int at) => tester
        .widget<Text>(
          find.descendant(
            of: byKey(rowOf(at)),
            matching: find.text(
              timelineNameOf(session.timelineVerbs.timelines[at]),
            ),
          ),
        )
        .style!
        .color!;
    expect(inkOf(1), AppColors.accent, reason: 'the open one');
    expect(inkOf(0), isNot(AppColors.accent));

    await tester.tap(byKey(rowOf(0)));
    await tester.pumpAndSettle();

    expect(
      session.timelineVerbs.currentTimelineId,
      session.timelineVerbs.timelines.first.id,
    );
    expect(headingWords(tester), AppText.strings.timelineNumbered(1));
  });

  testWidgets('a row\'s duplicate offers a copy\'s name, and the copy '
      'stands right after it, opened', (tester) async {
    await pumpConte(tester);
    await openList(tester);
    await tester.tap(byKey('timeline-add'));
    await tester.pumpAndSettle();
    await openList(tester);
    await tester.tap(byKey('${rowOf(0)}-duplicate'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(byKey('timeline-duplicate-text-field'))
          .controller!
          .text,
      AppText.strings.copyNamed(AppText.strings.timelineNumbered(1)),
    );
    await tester.enterText(byKey('timeline-duplicate-text-field'), '예고');
    await tester.tap(byKey('timeline-duplicate-ok-button'));
    await tester.pumpAndSettle();

    final timelines = session.timelineVerbs.timelines;
    expect(timelines.map(timelineNameOf), [
      AppText.strings.timelineNumbered(1),
      '예고',
      AppText.strings.timelineNumbered(2),
    ]);
    expect(session.timelineVerbs.currentTimelineId, timelines[1].id);
    expect(headingWords(tester), '예고');
  });

  testWidgets('a row\'s pencil names it, and the heading reads the name; '
      'its delete takes it away — never the last one', (tester) async {
    await pumpConte(tester);
    await openList(tester);
    await tester.tap(byKey('${rowOf(0)}-rename'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(byKey('timeline-rename-text-field'))
          .controller!
          .text,
      AppText.strings.timelineNumbered(1),
    );
    await tester.enterText(byKey('timeline-rename-text-field'), '본편');
    await tester.tap(byKey('timeline-rename-ok-button'));
    await tester.pumpAndSettle();

    expect(headingWords(tester), '본편');

    await openList(tester);
    expect(
      tester.widget<AppIconButtonFace>(byKey('${rowOf(0)}-delete')).onPressed,
      isNull,
      reason: 'the last one stays',
    );
  });
}

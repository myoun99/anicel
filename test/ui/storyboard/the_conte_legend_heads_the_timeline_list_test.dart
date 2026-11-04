import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/text/place_lines.dart' show timelineNameOf;
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart'
    show TimelineLayerControlsRow;
import 'package:anicel/src/ui/widgets/app_icon_button.dart';

import '../../helpers/home_page_probes.dart';
import '../../helpers/wait_window.dart';

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

  testWidgets('🚨the button\'s words are written as a row\'s name is', (
    tester,
  ) async {
    // 🗣️F-548 (유저 2026-11-04): 「타임라인1이라는 버튼의 텍스트가 너무
    // 작음. 일반 행 텍스트랑 똑같이 할수있나」.
    await pumpConte(tester);
    TextStyle drawn(Finder text) =>
        tester.renderObject<RenderParagraph>(text).text.style!;
    final heading = drawn(
      find.descendant(
        of: inStoryboard('legend-heading'),
        matching: byKey('legend-layer'),
      ),
    );
    final rowOne = find
        .descendant(
          of: find.byType(StoryboardPanel),
          matching: find.byType(TimelineLayerControlsRow),
        )
        .first;
    final row = drawn(
      find.descendant(
        of: rowOne,
        matching: find.text(
          tester.widget<TimelineLayerControlsRow>(rowOne).layer.name,
        ),
      ),
    );

    expect(
      (heading.fontSize, heading.fontWeight, heading.letterSpacing),
      (row.fontSize, row.fontWeight, row.letterSpacing),
    );
    expect(heading.color, row.color);
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
      allOf(
        AppText.strings.copyNamed(AppText.strings.timelineNumbered(1)),
        isNot(AppText.strings.timelineNumbered(1)),
      ),
      reason: 'a copy is offered a name of its own',
    );
    await tester.enterText(byKey('timeline-duplicate-text-field'), '예고');
    await tester.tap(byKey('timeline-duplicate-ok-button'));
    await tester.pump();
    // 🗣️F-549 (유저 2026-11-04): 「타임라인 복제누르고 진행중에 진행창뜨도록」.
    expect(
      byKey('timeline-duplicate-progress'),
      findsOneWidget,
      reason: "the copy stands behind the app's one wait window",
    );
    await pumpPastTheWaitWindow(tester);

    final timelines = session.timelineVerbs.timelines;
    expect(timelines.map(timelineNameOf), [
      AppText.strings.timelineNumbered(1),
      '예고',
      AppText.strings.timelineNumbered(2),
    ]);
    expect(session.timelineVerbs.currentTimelineId, timelines[1].id);
    expect(headingWords(tester), '예고');
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('with two, a row\'s delete takes that one away', (tester) async {
    await pumpConte(tester);
    await openList(tester);
    await tester.tap(byKey('timeline-add'));
    await tester.pumpAndSettle();
    final added = session.timelineVerbs.timelines[1].id;
    await openList(tester);
    await tester.tap(byKey('${rowOf(1)}-delete'));
    await tester.pumpAndSettle();

    expect(session.timelineVerbs.timelines, hasLength(1));
    expect(
      session.timelineVerbs.timelines.map((timeline) => timeline.id),
      isNot(contains(added)),
    );
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
    await tester.tap(byKey('timeline-rename-ok-button'));
    await tester.pumpAndSettle();
    expect(
      session.timelineVerbs.timelines.first.name,
      isNull,
      reason: 'the name its number gives, left as it was, stays that one',
    );

    await openList(tester);
    await tester.tap(byKey('${rowOf(0)}-rename'));
    await tester.pumpAndSettle();
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

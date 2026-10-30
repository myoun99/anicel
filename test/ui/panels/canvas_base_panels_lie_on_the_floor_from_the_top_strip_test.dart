import 'dart:io';

import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/tools_panel.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_tab_host.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/media/media_pool_panel.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';
import 'package:anicel/src/ui/panels/workspace_layout_store.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';
import 'package:anicel/src/ui/widgets/strip_group_rule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/panel_finders.dart';
import '../../helpers/project_scratch_folder.dart';
import '../../helpers/rail_group_button.dart';
import '../../helpers/settings_flyout.dart' show tapPanelsDrawerRow;
import '../../helpers/settle_async.dart';

/// 🗣️I-147 (유저 2026-10-30): 「캔버스베이스 패널들 … 상단띠 통해 배경에
/// 깔수있게 하도록. 다만 캔버스패널이랑 메인뷰어패널은 지금처럼 배경고정.
/// 못움직임. 그리고 깔 때는 하나씩만 여는거니까 탭 띠를 아이콘버튼위에
/// 만들도록. 그러고 이 버튼 자체 탭 띠는 공용으로 다른 사이드띠에도
/// 쓸수있게해서 해당 버튼들 패널들 통째로 옮길수있도록. 그리고 상단띠에서
/// 배경에 붙은 고정패널이랑 변동이랑 구분하기위해 사이에 세로선추가」 — with
/// its answers: Q1 a (a band per button, inside it — 「버튼을 길게하는게
/// 아니라」), Q2 a (「상단 띠에서는 패널마다 버튼 하나 — 버튼이 곧 바닥의
/// 탭」), Q3 c (「지금 자리 그대로 — 상단 띠의 그 자리는 처음엔 비어 있다」).
void main() {
  final sheets = EditorWorkspace.railGroupId(right: true, slot: 2);
  final media = EditorWorkspace.railGroupId(right: true, slot: 3);
  final onion = EditorWorkspace.railGroupId(right: true, slot: 4);
  String top(int slot) => EditorWorkspace.topGroupId(slot: slot);
  String leftSlot(int slot) =>
      EditorWorkspace.railGroupId(right: false, slot: slot);

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
  }

  Finder band(String groupId) =>
      find.byKey(ValueKey<String>('rail-group-band-$groupId'));
  Finder floorButton(String tabId) =>
      find.byKey(ValueKey<String>('top-strip-floor-$tabId'));

  /// Lifts [groupId]'s button by its band and lets it go over [target],
  /// found once the lift has raised the strips' empty slots.
  Future<void> carry(
    WidgetTester tester,
    String groupId,
    Finder Function() target, {
    Offset nudge = const Offset(-30, 0),
  }) async {
    final gesture = await tester.startGesture(tester.getCenter(band(groupId)));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(nudge);
    await tester.pump();
    final to = tester.getCenter(target());
    await gesture.moveTo(to + const Offset(0, -5));
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('the top strip draws a second rule after the canvas and the '
      'main viewer, and nothing after it until a button is carried there '
      '(Q3 c)', (tester) async {
    await pumpApp(tester);
    final viewer = tester.getRect(
      floorButton(EditorWorkspace.mediaViewerTabId),
    );
    final ruleFinder = find.byType(StripGroupRule);
    final rules = [
      for (var i = 0; i < ruleFinder.evaluate().length; i += 1)
        tester.getRect(ruleFinder.at(i)),
    ].where((rect) => (rect.center.dy - viewer.center.dy).abs() < 20);
    expect(
      rules.where((rect) => rect.left >= viewer.right),
      isNotEmpty,
      reason: 'the rule after the floor\'s own two',
    );
    expect(
      rules.where((rect) => rect.right <= tester.getRect(
        floorButton(EditorWorkspace.canvasTabId),
      ).left),
      isNotEmpty,
      reason: 'the rule after the settings stands as it stood',
    );
    expect(railGroupButton(top(1)), findsNothing);
    expect(railGroupButton(sheets), findsOneWidget);
  });

  testWidgets('every strip button that holds panels wears the tab\'s band '
      'inside its own square — the button does not grow (Q1 a); the floor '
      'switch and the tools wear none', (tester) async {
    await pumpApp(tester);
    for (final groupId in [
      EditorWorkspace.leftGroupId,
      // The colour group's button is the swatch, and wears the band too.
      EditorWorkspace.rightGroupId,
      sheets,
      media,
      onion,
    ]) {
      final button = tester.getRect(railGroupButton(groupId));
      final grip = tester.getRect(band(groupId));
      expect(button.height, ToolsPanel.buttonExtent, reason: groupId);
      expect(grip.top, button.top, reason: groupId);
      expect(grip.left, button.left, reason: groupId);
      expect(grip.right, button.right, reason: groupId);
      expect(grip.bottom, lessThan(button.bottom), reason: groupId);
    }
    expect(band(EditorWorkspace.centerGroupId), findsNothing);
    expect(
      find.descendant(
        of: floorButton(EditorWorkspace.canvasTabId),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'rail-group-band-',
              ),
        ),
      ),
      findsNothing,
    );
  });

  testWidgets('carried to the top strip, the sheets stand there a button per '
      'panel (Q2 a) and the front one lies on the floor — the canvas is no '
      'longer built', (tester) async {
    await pumpApp(tester);
    expect(mainCanvasPanel(), findsOneWidget);

    await carry(tester, sheets, () => railGroupButton(top(1)));

    expect(railGroupButton(sheets), findsNothing);
    for (final slot in [1, 2, 3]) {
      expect(railGroupButton(top(slot)), findsOneWidget, reason: top(slot));
    }
    expect(railGroupButton(top(4)), findsNothing);
    // The rule's margin stands before them, as on its other side.
    final first = tester.getRect(railGroupButton(top(1)));
    final ruleFinder = find.byType(StripGroupRule);
    final rule = [
      for (var i = 0; i < ruleFinder.evaluate().length; i += 1)
        tester.getRect(ruleFinder.at(i)),
    ].where((rect) => rect.right <= first.left).reduce(
      (a, b) => a.right > b.right ? a : b,
    );
    expect(first.left - rule.right, StripGroupRule.margin);
    expect(find.byType(TimesheetTabHost), findsOneWidget);
    expect(mainCanvasPanel(), findsNothing);
    // The timesheet lies on the floor: the whole room the floor has.
    final floor = tester.getRect(
      find.byKey(const ValueKey<String>('workspace-floor')),
    );
    expect(
      tester.getRect(find.byType(TimesheetTabHost)).width,
      greaterThan(floor.width / 2),
    );
  });

  testWidgets('a top strip button lays its panel, one at a time; the canvas '
      'button gives the floor back', (tester) async {
    await pumpApp(tester);
    await carry(tester, sheets, () => railGroupButton(top(1)));

    // The sheets stand in their group's order: timesheet, conte, envelope.
    await tester.tap(railGroupButton(top(2)));
    await tester.pumpAndSettle();
    expect(find.byType(ConteTabHost), findsOneWidget);
    expect(find.byType(TimesheetTabHost), findsNothing);
    // The button of what lies on the floor reads open, as a rail's does.
    bool open(String groupId) => tester
        .widget<RailButton>(
          find.ancestor(
            of: railGroupButton(groupId),
            matching: find.byType(RailButton),
          ),
        )
        .selected;
    expect([open(top(1)), open(top(2)), open(top(3))], [false, true, false]);

    await tester.tap(railGroupButton(top(3)));
    await tester.pumpAndSettle();
    expect(find.byType(CutEnvelopeTabHost), findsOneWidget);
    expect(find.byType(ConteTabHost), findsNothing);

    // Pressed again, it stays.
    await tester.tap(railGroupButton(top(3)));
    await tester.pumpAndSettle();
    expect(find.byType(CutEnvelopeTabHost), findsOneWidget);

    await tester.tap(floorButton(EditorWorkspace.canvasTabId));
    await tester.pumpAndSettle();
    expect(mainCanvasPanel(), findsOneWidget);
    expect(find.byType(CutEnvelopeTabHost), findsNothing);
    // And the top strip keeps its buttons.
    expect(railGroupButton(top(3)), findsOneWidget);
  });

  testWidgets('a button holding a panel that is no canvas-base panel finds no '
      'place on the top strip — and an empty slot beside the drawing', (
    tester,
  ) async {
    await pumpApp(tester);
    final gesture = await tester.startGesture(tester.getCenter(band(media)));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    expect(railGroupButton(top(1)), findsNothing);
    expect(railGroupButton(leftSlot(3)), findsOneWidget);
    await gesture.moveTo(tester.getCenter(railGroupButton(leftSlot(3))));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(railGroupButton(media), findsNothing);
    expect(find.byType(MediaPoolPanel), findsOneWidget, reason: 'lands open');
    expect(
      tester.getRect(railGroupButton(leftSlot(3))).center.dx,
      lessThan(800),
      reason: 'on the left strip',
    );
  });

  testWidgets('a top strip button carried onto a side button JOINS its group, '
      'in front (Q2 a: 「사이드 띠 버튼 위에 놓으면 그 묶음에 들어간다」) — and '
      'onto a side strip\'s empty slot it is a button of its own', (
    tester,
  ) async {
    await pumpApp(tester);
    await carry(tester, sheets, () => railGroupButton(top(1)));

    await carry(
      tester,
      top(3),
      () => railGroupButton(onion),
      nudge: const Offset(0, 30),
    );
    expect(railGroupButton(top(3)), findsNothing);
    expect(find.byType(CutEnvelopeTabHost), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('panel-grip-envelope')),
      findsOneWidget,
      reason: 'a tab of the onion\'s group now',
    );

    await carry(
      tester,
      top(2),
      () => railGroupButton(leftSlot(3)),
      nudge: const Offset(0, 30),
    );
    expect(railGroupButton(top(2)), findsNothing);
    expect(railGroupButton(leftSlot(3)), findsOneWidget);
    expect(find.byType(ConteTabHost), findsOneWidget, reason: 'lands open');
  });

  testWidgets('a group carried onto a side button joins it with its own front '
      'panel in front', (tester) async {
    await pumpApp(tester);
    await carry(
      tester,
      sheets,
      () => railGroupButton(onion),
      nudge: const Offset(0, 30),
    );
    expect(railGroupButton(sheets), findsNothing);
    expect(find.byType(TimesheetTabHost), findsOneWidget);
    expect(find.byType(CutEnvelopeTabHost), findsNothing);
  });

  testWidgets('no panel but the floor\'s own two lies on an emptied floor — '
      '「캔버스패널이랑 메인뷰어패널은 지금처럼 배경고정」', (tester) async {
    await pumpApp(tester);
    await tapPanelsDrawerRow(tester, 'panels-menu-item-canvas');
    await tapPanelsDrawerRow(tester, 'panels-menu-item-media-viewer');
    expect(mainCanvasPanel(), findsNothing);
    if (find.byType(TimesheetTabHost).evaluate().isEmpty) {
      await tester.tap(railGroupButton(sheets));
      await tester.pumpAndSettle();
    }
    final sheet = find.byKey(const ValueKey<String>('panel-grip-timesheet'));
    final gesture = await tester.startGesture(tester.getCenter(sheet));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    await gesture.moveTo(const Offset(500, 500));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(sheet, findsOneWidget, reason: 'still a tab of its group');
    expect(tester.getRect(find.byType(TimesheetTabHost)).width, lessThan(800));
  });

  testWidgets('the panel that lay on the floor leaving the top strip gives '
      'the floor back to the canvas', (tester) async {
    await pumpApp(tester);
    await carry(tester, sheets, () => railGroupButton(top(1)));
    expect(find.byType(TimesheetTabHost), findsOneWidget);

    await carry(
      tester,
      top(1),
      () => railGroupButton(leftSlot(3)),
      nudge: const Offset(0, 30),
    );
    expect(mainCanvasPanel(), findsOneWidget);
    expect(
      find.byType(TimesheetTabHost),
      findsOneWidget,
      reason: 'open beside the drawing now',
    );
    expect(
      tester.getRect(find.byType(TimesheetTabHost)).width,
      lessThan(800),
    );
  });

  testWidgets('a panel tab may come to the top strip by its empty slot, and '
      'onto no top strip button — a top button is one panel (Q2 a)', (
    tester,
  ) async {
    final conteTab = find.byKey(const ValueKey<String>('panel-grip-conte'));
    await pumpApp(tester);
    await carry(tester, sheets, () => railGroupButton(top(1)));
    // Back to the sheets' own button beside the drawing, but the timesheet.
    await carry(
      tester,
      top(2),
      () => railGroupButton(sheets),
      nudge: const Offset(0, 30),
    );
    await carry(
      tester,
      top(3),
      () => railGroupButton(sheets),
      nudge: const Offset(0, 30),
    );
    expect(conteTab, findsOneWidget);

    // The conte's tab onto the timesheet's top button: refused.
    var gesture = await tester.startGesture(tester.getCenter(conteTab));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(railGroupButton(top(1))));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(railGroupButton(top(2)), findsNothing);
    expect(conteTab, findsOneWidget);

    // …and onto the strip's empty slot: a button of its own, laid.
    gesture = await tester.startGesture(tester.getCenter(conteTab));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(railGroupButton(top(2))));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(railGroupButton(top(2)), findsOneWidget);
    expect(conteTab, findsNothing);
    expect(find.byType(ConteTabHost), findsOneWidget);
    expect(mainCanvasPanel(), findsNothing);
  });

  testWidgets('the canvas-base panels are the sheets and the viewers — the '
      'ones whose content stands on the canvas base', (tester) async {
    await pumpApp(tester);
    // Every group that ships closed, opened, so every panel's tab is here.
    for (final groupId in [
      leftSlot(2),
      EditorWorkspace.rightGroupId,
      media,
      onion,
      EditorWorkspace.railGroupId(right: true, slot: 5),
    ]) {
      await tester.tap(railGroupButton(groupId));
      await tester.pumpAndSettle();
    }
    final declared = <String, bool>{
      for (final group in tester.widgetList<EditorPanelTabs>(
        find.byType(EditorPanelTabs),
      ))
        for (final tab in group.tabs) tab.id: tab.canvasBase,
    };
    expect(
      {
        for (final entry in declared.entries)
          if (entry.value) entry.key,
      },
      {
        EditorWorkspace.timesheetTabId,
        EditorWorkspace.conteTabId,
        EditorWorkspace.envelopeTabId,
        EditorWorkspace.mediaViewerTabId,
        EditorWorkspace.mediaViewerSubTabId,
      },
    );
    // The two in front of their groups say so of what they build.
    BrushCanvasPanel canvasPanelIn(Finder host) => tester.widget(
      find.descendant(of: host, matching: find.byType(BrushCanvasPanel)).first,
    );
    expect(canvasPanelIn(find.byType(TimesheetTabHost)).canvasBase, isTrue);
    expect(canvasPanelIn(mainCanvasPanel()).canvasBase, isFalse);
  });

  testWidgets('the layout keeps the top strip\'s buttons and what lay on the '
      'floor', (tester) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('floor_bands'),
    ))!;
    deleteAfterSessionEnds(directory);
    final store = WorkspaceLayoutStore(
      filePath: '${directory.path}/workspace_layout.json',
    );
    Future<void> open() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: HomePage(layoutStore: store),
        ),
      );
      await tester.pumpAndSettle();
    }

    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await open();
    await carry(tester, sheets, () => railGroupButton(top(1)));
    await tester.tap(railGroupButton(top(2)));
    await tester.pumpAndSettle();
    // The save is debounced 800 ms behind the last change.
    await tester.pump(const Duration(milliseconds: 900));
    Map<String, Object?>? saved;
    await settleAsync(tester, () async {
      saved = await tester.runAsync<Map<String, Object?>?>(store.load);
      return saved?['laidFloorTab'] == EditorWorkspace.conteTabId;
    });
    expect(saved?['laidFloorTab'], EditorWorkspace.conteTabId);

    await tester.pumpWidget(const SizedBox.shrink());
    await open();
    await settleAsync(
      tester,
      () async => find.byType(ConteTabHost).evaluate().isNotEmpty,
    );
    expect(railGroupButton(top(3)), findsOneWidget);
    expect(find.byType(ConteTabHost), findsOneWidget);
    expect(mainCanvasPanel(), findsNothing);
  });

  testWidgets('a press on the band that does not move is the button\'s own', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.byType(MediaPoolPanel), findsNothing);
    await tester.tapAt(tester.getCenter(band(media)));
    await tester.pumpAndSettle();
    expect(find.byType(MediaPoolPanel), findsOneWidget);
  });
}

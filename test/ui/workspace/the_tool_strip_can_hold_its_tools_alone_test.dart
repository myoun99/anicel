// 🗣️I-128 (유저 2026-10-25): 「화면 왼쪽띠의 언두나 활성레이어 솔로 등 조작관련
// 버튼, 이 숏컷 버튼 안쓰는 사람 위해서 설정의 패널에 해당 영역 끌수있게 옵션
// 제공. 조작단축버튼이랑 도구 버튼 사이의 가로 구분선도 그 경우 없어도되니
// 사라지도록」.
//
// THE TOOL STRIP CAN HOLD ITS TOOLS ALONE: Settings › 패널 › 「툴 바에 도구만」
// takes the shortcut buttons off the strip, and the rule under them with
// them — the choice kept with the layout, and a reset of the layout putting
// them back.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/panels/workspace_layout_store.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

import '../../helpers/boolean_dot_probe.dart';
import '../../helpers/project_scratch_folder.dart';
import '../../helpers/settings_flyout.dart';
import '../../helpers/settle_async.dart';

const row = 'menu-window-rail-tools-only';

Finder inTheStrip(Finder matching) => find.descendant(
  of: find.byKey(const ValueKey<String>('tools-panel')),
  matching: matching,
);

Future<void> pumpHome(
  WidgetTester tester, {
  WorkspaceLayoutStore? store,
}) async {
  await tester.pumpWidget(
    MaterialApp(theme: buildAppTheme(), home: HomePage(layoutStore: store)),
  );
  await tester.pumpAndSettle();
}

/// Whether the drawer's row is marked — opened, read, and closed again.
Future<bool> rowMarked(WidgetTester tester) async {
  await openPanelsDrawer(tester);
  final item = find.byKey(const ValueKey<String>(row));
  await tester.ensureVisible(item);
  await tester.pumpAndSettle();
  final marked = tester.booleanDotIn(item).value;
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
  return marked;
}

void expectShortcutsAboveTheTools(String why) {
  for (final key in ['undo-button', 'redo-button', 'tool-brush-button']) {
    expect(
      inTheStrip(find.byKey(ValueKey<String>(key))),
      findsOneWidget,
      reason: '$key — $why',
    );
  }
  expect(inTheStrip(find.byType(Divider)), findsOneWidget, reason: why);
}

void expectTheToolsAlone(String why) {
  for (final key in ['undo-button', 'redo-button']) {
    expect(
      find.byKey(ValueKey<String>(key)),
      findsNothing,
      reason: '$key gone — $why',
    );
  }
  expect(
    inTheStrip(find.byKey(const ValueKey<String>('tool-brush-button'))),
    findsOneWidget,
    reason: 'the tools stay — $why',
  );
  expect(
    inTheStrip(find.byType(Divider)),
    findsNothing,
    reason: 'the rule goes with the buttons — $why',
  );
}

void main() {
  testWidgets('by default the shortcut buttons stand above the tools, a rule '
      'between', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpHome(tester);

    expectShortcutsAboveTheTools('the default');
    expect(await rowMarked(tester), isFalse, reason: 'the row says so');
  });

  testWidgets('Settings › 패널 › 「툴 바에 도구만」 takes them off with their '
      'rule, and again puts them back', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpHome(tester);

    await tapPanelsDrawerRow(tester, row);
    expectTheToolsAlone('the row took them off');
    expect(await rowMarked(tester), isTrue);

    await tapPanelsDrawerRow(tester, row);
    expectShortcutsAboveTheTools('the row put them back');
    expect(await rowMarked(tester), isFalse);
  });

  testWidgets('the layout file keeps the choice — a restart stands the tools '
      'alone again, and a reset of the layout puts the buttons back', (
    tester,
  ) async {
    // Real file IO only inside runAsync — awaited on the fake clock a
    // testWidgets body runs on, createTemp never completes.
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('rail_tools_only'),
    ))!;
    deleteAfterSessionEnds(directory);
    final store = WorkspaceLayoutStore(
      filePath: '${directory.path}/workspace_layout.json',
    );
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpHome(tester, store: store);

    await tapPanelsDrawerRow(tester, row);
    // The save is debounced 800 ms behind the last change; the write is real
    // IO whose steps complete in real time and continue on the fake clock.
    await tester.pump(const Duration(milliseconds: 900));
    Object? saved;
    await settleAsync(tester, () async {
      final payload = await tester.runAsync<Map<String, Object?>?>(store.load);
      saved = payload?['railToolsOnly'];
      return saved != null;
    });
    expect(saved, isTrue, reason: 'the row is the change that saved');

    // A restart: the old workspace goes, a new one reads the same file.
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpHome(tester, store: store);
    await settleAsync(
      tester,
      () => !tester.any(find.byKey(const ValueKey<String>('undo-button'))),
    );
    await tester.pumpAndSettle();
    expectTheToolsAlone('the restored layout');

    await tapPanelsDrawerRow(tester, 'menu-window-reset-layout');
    expectShortcutsAboveTheTools('the reset');
  });
}

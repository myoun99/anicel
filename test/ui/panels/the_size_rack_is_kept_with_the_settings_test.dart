import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/panels/tool_size_preset_panel.dart';

import '../../helpers/rail_group_button.dart';

/// 🗣️I-170 (유저 2026-11-13): 「도구 브러시크기 프리셋패널, 슬슬 추가/삭제버튼
/// 추가 … 정상적이면 프리셋에 추가. 삭제는 선택(강조색 되있는)되있는 크기를
/// 삭제하는버튼」 — in the app the panel's rack is the one the input settings
/// keep: what its two buttons do is what the size bar's ± and the size
/// drag's snap read next.
void main() {
  Finder cell(double value) => find.byKey(
    ValueKey<String>('tool-size-preset-${ToolSizePresetPanel.label(value)}'),
  );
  Finder key(String keyValue) => find.byKey(ValueKey<String>(keyValue));

  testWidgets('🚨a size put on the rack in the app is kept with the input '
      'settings and stands as a cell, and the delete takes the lit one off '
      'both', (tester) async {
    addTearDown(() {
      AppInput.settings.value = AppInputSettings.testCorpusBaseline;
    });
    // The onion's group, where the rack rides, is clipped on the default
    // 800×600 surface.
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    await tester.tap(railGroupButton('rail-R4'));
    await tester.pumpAndSettle();
    final tab = key('panel-tab-${EditorWorkspace.toolSizeTabId}');
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab);
    await tester.pumpAndSettle();
    final tool = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .brushTool!;
    expect(cell(11), findsNothing, reason: '⛔premise: 11 is not on the rack');

    await tester.tap(key(ToolSizePresetPanel.addKey));
    await tester.pumpAndSettle();
    for (final pressed in ['1', '1', 'enter']) {
      await tester.tap(key('${ToolSizePresetPanel.addKey}-pad-$pressed'));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(AppInput.settings.value.toolSizes, [
      for (final size in AppInputSettings.defaultToolSizes) ...[
        size,
        if (size == 10) 11,
      ],
    ]);
    expect(cell(11), findsOneWidget);

    // The cell pressed is the tool's size, so it is the lit one.
    await tester.ensureVisible(cell(11));
    await tester.pumpAndSettle();
    await tester.tap(cell(11));
    await tester.pumpAndSettle();
    expect(tool.value.activeSize, 11);

    await tester.tap(key(ToolSizePresetPanel.deleteKey));
    await tester.pumpAndSettle();

    expect(
      AppInput.settings.value.toolSizes,
      AppInputSettings.defaultToolSizes,
    );
    expect(cell(11), findsNothing);
    expect(tool.value.activeSize, 11, reason: 'the tool keeps its size');
  });
}

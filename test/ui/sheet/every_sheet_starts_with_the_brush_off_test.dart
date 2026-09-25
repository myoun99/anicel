import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';

import '../../helpers/app_icon_button_probe.dart';

/// 🚨F-179 — EVERY SHEET STARTS WITH THE BRUSH OFF.
///
/// 유저 2026-09-25: 「브러시 허용으로 바꾸고, 버튼 법 통일하고, 기본값
/// off로」. The workspace owns each sheet's switch so it survives tab
/// switches, and the timesheet's alone used to start on — so this is read
/// through the app, where that default lives, not through a bare host whose
/// constructor default the workspace never used.
void main() {
  testWidgets('the timesheet, the conte and the envelope each open with '
      'their brush switch off', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    for (final (tabId, prefix) in const [
      (EditorWorkspace.timesheetTabId, 'timesheet'),
      (EditorWorkspace.conteTabId, 'conte'),
      (EditorWorkspace.envelopeTabId, 'envelope'),
    ]) {
      tester
          .widgetList<EditorPanelTabs>(find.byType(EditorPanelTabs))
          .firstWhere((host) => host.tabs.any((tab) => tab.id == tabId))
          .onTabSelected(tabId);
      await tester.pumpAndSettle();

      final toggle = find.byKey(ValueKey<String>('$prefix-brush-toggle-button'));
      expect(toggle, findsOneWidget, reason: '$prefix shows its switch');
      expect(
        tester.appIconButton(toggle).isSelected,
        isFalse,
        reason: '$prefix starts with the brush off',
      );
    }
  });
}

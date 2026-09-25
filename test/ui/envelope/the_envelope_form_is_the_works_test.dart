import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/envelope/cut_envelope_presets.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';

/// The 봉투 form is the WORK's choice (유저 답 sheet-form-choice-home:
/// 「해당 패널에 지금처럼 두고싶고, 그 상태에서 작품에 저장되도록」): the
/// panel still picks it, and what it picks is written to the project — one
/// undo takes it back. ↩️It was a workspace value that died with the
/// session.
void main() {
  testWidgets('picking a form in the panel writes it to the work, and one '
      'undo takes it back', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    tester
        .widgetList<EditorPanelTabs>(find.byType(EditorPanelTabs))
        .firstWhere(
          (host) => host.tabs.any(
            (tab) => tab.id == EditorWorkspace.envelopeTabId,
          ),
        )
        .onTabSelected(EditorWorkspace.envelopeTabId);
    await tester.pumpAndSettle();
    expect(session.timesheetInfo.envelopeFormId, CutEnvelopePresets.analogId);

    await tester.tap(
      find.byKey(
        const ValueKey<String>('envelope-form-${CutEnvelopePresets.digitalId}'),
      ),
    );
    await tester.pumpAndSettle();
    expect(session.timesheetInfo.envelopeFormId, CutEnvelopePresets.digitalId);

    session.undo();
    await tester.pumpAndSettle();
    expect(session.timesheetInfo.envelopeFormId, CutEnvelopePresets.analogId);
  });
}

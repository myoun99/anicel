import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/widgets/app_window.dart';

/// F-282-Q7 (유저 2026-10-09): 「출력창과 같은 법 — 화면이 남긴 자리 전체」 —
/// the import window takes the room the screen leaves, by the export
/// window's own law ([AppWindow.fullRoom]). ↩️760 × 520, whatever the
/// screen: the five columns of the table pushed sideways, and the preview
/// panel's pill and transport were cramped in what was left.
void main() {
  testWidgets('the import window takes the room the screen leaves', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ImportDialog(session: s))),
    );
    await tester.pump();

    final window = tester.widget<AppWindow>(find.byType(AppWindow));
    expect(
      (window.width, window.height),
      (1520.0, 936.0),
      reason: 'the screen less the dialog\'s own inset — the room the export '
          'window takes',
    );
  });
}

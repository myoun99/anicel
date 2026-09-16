import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';

/// The export window's modules carry no explanatory copy.
///
/// 유저 2026-09-16 (export-module-notes-Q1): 「모두 지운다」 — the grey sentence
/// under the Timesheet, Conte, Envelope and Size modules was the exact thing
/// the house rule forbids (「설명 문구 금지 — 컨트롤 밑 안내 텍스트·부연 캡션을
/// 넣지 않는다」), and translating it would have set nine of them in five
/// languages. This pumps every tab that carried one and looks for each
/// sentence's own words.
void main() {
  Future<ExportDialogState> pumpDialog(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1120, 660));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            session: session,
            formatAvailability: ExportFormatAvailability.permissive(),
          ),
        ),
      ),
    );
    await tester.pump();
    return tester.state<ExportDialogState>(find.byType(ExportDialog));
  }

  Future<void> switchTab(WidgetTester tester, String tab) async {
    await tester.tap(find.byKey(ValueKey<String>('export-tab-$tab')));
    await tester.pump();
  }

  /// A phrase from each of the nine sentences, as it stood on 2026-09-16.
  const phrases = [
    "The panel's B4 paper rendered per page",
    'One .xdts digital timesheet per cut',
    'One A4 PDF of the whole picture conte',
    "The panel's A4 paper rendered per page",
    "The cut's own pixels, so the PNG drops",
    'at print resolution',
    'Separate files are the PSD layering',
    'A 겸용 cut and its siblings are ONE envelope',
    'Canvas is cut-scope only',
  ];

  void expectNoNote(WidgetTester tester, String where) {
    for (final phrase in phrases) {
      expect(
        find.textContaining(phrase),
        findsNothing,
        reason: '$where still explains itself: 「$phrase」',
      );
    }
  }

  testWidgets('no tab explains its module under the controls', (
    tester,
  ) async {
    await pumpDialog(tester);
    // Sequence, project scope: the Size module's note stood here.
    await tester.tap(find.byKey(const ValueKey<String>('export-scope-project')));
    await tester.pump();
    expectNoNote(tester, 'the sequence tab under the project scope');

    for (final tab in const ['timesheet', 'conte', 'envelope']) {
      await switchTab(tester, tab);
      expectNoNote(tester, 'the $tab tab');
    }
  });
}

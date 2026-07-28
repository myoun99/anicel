import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';

/// The sheet document/layout memo: most session notifies (fx toggles,
/// selections, waveform loads) change none of the document's inputs — the
/// host must NOT rebuild the document for them, only for real model edits.
void main() {
  testWidgets('the sheet document rebuilds only when its inputs change', (
    tester,
  ) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => TimesheetTabHost(
              session: session,
              continuous: false,
              onContinuousChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    TimesheetDocument documentNow() {
      final paint = tester.widget<CustomPaint>(
        find.byKey(const ValueKey<String>('timesheet-document-paint')),
      );
      return (paint.painter as TimesheetDocumentPainter).document;
    }

    final before = documentNow();

    // A cut-invariant notify (fx bypass is session view state, not model).
    session.toggleLayerFx(session.activeLayer!.id);
    await tester.pumpAndSettle();
    expect(
      identical(documentNow(), before),
      isTrue,
      reason: 'cut-invariant notifies must reuse the memoized document',
    );

    // A real model edit changes the cut identity and rebuilds the sheet.
    session.toggleLayerTimesheet(session.activeLayer!.id);
    await tester.pumpAndSettle();
    expect(
      identical(documentNow(), before),
      isFalse,
      reason: 'model edits must rebuild the document',
    );
  });
}

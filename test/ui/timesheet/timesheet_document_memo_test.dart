import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';

/// The sheet document/layout memo: most session notifies (selections,
/// waveform loads, tool changes) change none of the document's inputs — the
/// host must NOT rebuild the document for them, only for real model edits.
///
/// R8 moved the fx switches ONTO the model, so an fx toggle is now on the
/// rebuilding side of that line — asserted here too, since it used to be
/// this test's example of the invariant kind.
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

    // A cut-invariant notify: moving the selection touches no document input.
    final other = session.layers
        .firstWhere((layer) => layer.id != session.activeLayerId)
        .id;
    session.selectLayer(other);
    await tester.pumpAndSettle();
    expect(
      identical(documentNow(), before),
      isTrue,
      reason: 'cut-invariant notifies must reuse the memoized document',
    );

    // A real model edit changes the cut identity and rebuilds the sheet.
    session.toggleLayerTimesheet(session.activeLayer!.id);
    await tester.pumpAndSettle();
    final afterEdit = documentNow();
    expect(
      identical(afterEdit, before),
      isFalse,
      reason: 'model edits must rebuild the document',
    );

    // R8: an fx toggle is a model edit — it must rebuild, not reuse.
    session.toggleLayerFx(session.activeLayer!.id);
    await tester.pumpAndSettle();
    expect(
      identical(documentNow(), afterEdit),
      isFalse,
      reason: 'R8 fx switches are persisted, so they change the cut',
    );
  });
}

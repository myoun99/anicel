import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_metadata.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_header_edit_layer.dart';

TimesheetDocument _document({String note = ''}) {
  return TimesheetDocument.fromCut(
    cut: Cut(
      id: const CutId('cut-1'),
      name: 'Cut 1',
      layers: const [],
      duration: 24,
      canvasSize: const CanvasSize(width: 1280, height: 720),
      metadata: CutMetadata(note: note),
    ),
    projectName: 'Project',
    fps: 24,
    info: const TimesheetInfo(artist: 'MYOUN'),
  );
}

const _editorKey = ValueKey<String>('timesheet-header-edit-field');

void main() {
  late List<(TimesheetHeaderField, String)> committedFields;
  late List<String> committedMemos;
  late Offset layerOrigin;

  Future<void> pumpLayer(WidgetTester tester, {String note = ''}) async {
    committedFields = [];
    committedMemos = [];
    final layout = TimesheetDocumentLayout(document: _document(note: note));
    final documentSize = layout.documentSize;

    await tester.binding.setSurfaceSize(
      Size(documentSize.width + 40, documentSize.height + 40),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: documentSize.width,
              height: documentSize.height,
              child: TimesheetHeaderEditLayer(
                layout: layout,
                viewport: CanvasViewport(),
                onHeaderFieldCommitted: (field, text) =>
                    committedFields.add((field, text)),
                onMemoCommitted: committedMemos.add,
              ),
            ),
          ),
        ),
      ),
    );
    layerOrigin = tester.getTopLeft(find.byType(TimesheetHeaderEditLayer));
  }

  group('TimesheetHeaderEditLayer', () {
    testWidgets('tapping the TITLE box opens an in-place editor preloaded '
        'with the printed value; submit commits the change', (tester) async {
      await pumpLayer(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('timesheet-header-edit-title-p0')),
      );
      await tester.pumpAndSettle();

      final editor = tester.widget<TextField>(find.byKey(_editorKey));
      expect(editor.controller!.text, 'Project');

      await tester.enterText(find.byKey(_editorKey), 'YOASOBI');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(committedFields, [(TimesheetHeaderField.title, 'YOASOBI')]);
      expect(find.byKey(_editorKey), findsNothing);
    });

    testWidgets('submitting unchanged text commits nothing', (tester) async {
      await pumpLayer(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('timesheet-header-edit-name-p0')),
      );
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(committedFields, isEmpty);
    });

    testWidgets('escape cancels the edit without committing', (tester) async {
      await pumpLayer(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('timesheet-header-edit-scene-p0')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_editorKey), 'S99');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(committedFields, isEmpty);
      expect(find.byKey(_editorKey), findsNothing);
    });

    testWidgets('tapping the memo band edits the cut note; tapping away '
        'commits it', (tester) async {
      await pumpLayer(tester, note: 'カットO.L');

      await tester.tap(
        find.byKey(const ValueKey<String>('timesheet-memo-edit-p0')),
      );
      await tester.pumpAndSettle();

      final editor = tester.widget<TextField>(find.byKey(_editorKey));
      expect(editor.controller!.text, 'カットO.L');

      await tester.enterText(find.byKey(_editorKey), 'A⋈B O.L');
      // The document margin is covered only by the tap-away barrier.
      await tester.tapAt(layerOrigin + const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(committedMemos, ['A⋈B O.L']);
      expect(find.byKey(_editorKey), findsNothing);
    });

    testWidgets('derived boxes (CUT/TIME/SHEET) take no tap zones', (
      tester,
    ) async {
      await pumpLayer(tester);

      for (final field in ['cut', 'time', 'sheet']) {
        expect(
          find.byKey(ValueKey<String>('timesheet-header-edit-$field-p0')),
          findsNothing,
        );
      }
    });
  });
}

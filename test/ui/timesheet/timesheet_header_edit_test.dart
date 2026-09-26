import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/timesheet/timesheet_words_in.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_metadata.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
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
    info: const TimesheetInfo(
      title: 'YOASOBI',
      episode: 'MV',
    ).withStaffName(const LayerMark(process: LayerProcess.key), '大川'),
  );
}

const _editorKey = ValueKey<String>('timesheet-header-edit-field');

void main() {
  late List<String> committedMemos;
  late Offset layerOrigin;

  Future<void> pumpLayer(WidgetTester tester, {String note = ''}) async {
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

    testWidgets('submitting unchanged text commits nothing', (tester) async {
      await pumpLayer(tester, note: 'カットO.L');

      await tester.tap(
        find.byKey(const ValueKey<String>('timesheet-memo-edit-p0')),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(layerOrigin + const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(committedMemos, isEmpty);
    });

    testWidgets('escape cancels the edit without committing', (tester) async {
      await pumpLayer(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('timesheet-memo-edit-p0')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_editorKey), 'PAN');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(committedMemos, isEmpty);
      expect(find.byKey(_editorKey), findsNothing);
    });

    testWidgets('⛔no header box takes a tap — the header is printed, not '
        'edited', (tester) async {
      // 유저 09-25: 「작품명/화수는 이제 타임시트패널같은곳에서 편집안하게.
      // 작업자든 뭐든. 해당 설정은 프로젝트 설정쪽에」.
      await pumpLayer(tester);

      for (final field in TimesheetHeaderField.values) {
        expect(
          find.byKey(ValueKey<String>('timesheet-header-edit-${field.name}-p0')),
          findsNothing,
          reason: field.name,
        );
      }
    });
  });

  test('the header prints the work\'s title and episode, the 원화 worker '
      'as its 作業者, and leaves the scene to the pen', () {
    final document = _document();
    final printed = TimesheetDocumentPainter(
      words: timesheetWordsIn(AppLanguage.en),
      document: document,
      layout: TimesheetDocumentLayout(document: document),
      face: const TextStyle(),
    );

    expect(printed.headerValueFor(TimesheetHeaderField.title, 0), 'YOASOBI');
    expect(printed.headerValueFor(TimesheetHeaderField.episode, 0), 'MV');
    expect(printed.headerValueFor(TimesheetHeaderField.name, 0), '大川');
    expect(printed.headerValueFor(TimesheetHeaderField.scene, 0), '');
  });
}

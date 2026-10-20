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

TimesheetDocument _document({
  List<String> notes = const [],
  int duration = 24,
}) {
  return TimesheetDocument.fromCut(
    cut: Cut(
      id: const CutId('cut-1'),
      name: 'Cut 1',
      layers: const [],
      duration: duration,
      canvasSize: const CanvasSize(width: 1280, height: 720),
      metadata: CutMetadata(
        pageNotes: notes,
      ).withStaffName(const LayerMark(process: LayerProcess.roughKey), '大川'),
    ),
    projectName: 'Project',
    fps: 24,
    info: const TimesheetInfo(title: 'YOASOBI', episode: 'MV'),
  );
}

const _editorKey = ValueKey<String>('timesheet-header-edit-field');

void main() {
  late List<(int, String)> committedMemos;
  late List<(TimesheetHeaderField, String)> committedHeads;
  late TimesheetDocumentLayout layout;
  late Offset layerOrigin;

  /// The fields the tab host gives a road (I-112).
  const edited = {
    TimesheetHeaderField.episode,
    TimesheetHeaderField.title,
    TimesheetHeaderField.cut,
    TimesheetHeaderField.name,
  };

  Future<void> pumpLayer(
    WidgetTester tester, {
    List<String> notes = const [],
    int duration = 24,
  }) async {
    committedMemos = [];
    committedHeads = [];
    layout = TimesheetDocumentLayout(
      document: _document(notes: notes, duration: duration),
    );
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
                onMemoCommitted: (page, memo) =>
                    committedMemos.add((page, memo)),
                headerCommits: {
                  for (final field in edited)
                    field: (text) => committedHeads.add((field, text)),
                },
              ),
            ),
          ),
        ),
      ),
    );
    layerOrigin = tester.getTopLeft(find.byType(TimesheetHeaderEditLayer));
  }

  group('TimesheetHeaderEditLayer', () {
    testWidgets('tapping the memo band edits the page\'s memo; tapping away '
        'commits it', (tester) async {
      await pumpLayer(tester, notes: ['カットO.L']);

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

      expect(committedMemos, [(0, 'A⋈B O.L')]);
      expect(find.byKey(_editorKey), findsNothing);
    });

    // 🗣️F-301 (유저 2026-10-05): 「타임시트의 메모란은 페이지별로 다름 …
    // 페이지별로 독립」.
    testWidgets('🚨each page\'s band edits that page\'s memo — the second '
        'shows its own and commits for itself', (tester) async {
      await pumpLayer(tester, notes: ['One', 'Two'], duration: 200);

      await tester.tap(
        find.byKey(const ValueKey<String>('timesheet-memo-edit-p1')),
      );
      await tester.pumpAndSettle();
      final editor = tester.widget<TextField>(find.byKey(_editorKey));
      expect(editor.controller!.text, 'Two', reason: 'its own, not page 1\'s');

      await tester.enterText(find.byKey(_editorKey), 'Two!');
      await tester.tapAt(layerOrigin + const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(committedMemos, [(1, 'Two!')]);
    });

    testWidgets('submitting unchanged text commits nothing', (tester) async {
      await pumpLayer(tester, notes: ['カットO.L']);

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


    testWidgets('🎯the NAME box edits its worker in place — one line, centred '
        'as printed, Enter lands it (I-112)', (tester) async {
      await pumpLayer(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('timesheet-name-edit-p0')),
      );
      await tester.pumpAndSettle();
      final editor = tester.widget<TextField>(find.byKey(_editorKey));
      expect(editor.controller!.text, '大川');
      expect(editor.maxLines, 1);
      expect(editor.textAlign, TextAlign.center);

      await tester.enterText(find.byKey(_editorKey), 'ユキ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(committedHeads, [(TimesheetHeaderField.name, 'ユキ')]);
      expect(find.byKey(_editorKey), findsNothing);
    });

    // 🗣️I-112 (유저 2026-10-21): 「추가로 화수,타이틀,신,이름 등 다른
    // 변경가능한것도 변경가능하게. 타임은 안하는게 나을듯. 페이지도 자동이고.」
    testWidgets('🎯every box with a road opens on what it prints and lands '
        'through its own road; ⛔a box without one — the length, the page, '
        'the scene — is printed, not edited', (tester) async {
      await pumpLayer(tester);
      const typed = {
        TimesheetHeaderField.episode: ('MV', '#3'),
        TimesheetHeaderField.title: ('YOASOBI', '夜に駆ける'),
        TimesheetHeaderField.cut: ('Cut 1', 'C-012'),
        TimesheetHeaderField.name: ('大川', 'ユキ'),
      };

      for (final box in layout.headerFieldBoxes(0)) {
        await tester.tapAt(layerOrigin + box.rect.center);
        await tester.pumpAndSettle();
        final words = typed[box.field];
        if (words == null) {
          expect(find.byKey(_editorKey), findsNothing, reason: box.field.name);
          continue;
        }
        final editor = tester.widget<TextField>(find.byKey(_editorKey));
        expect(editor.controller!.text, words.$1, reason: box.field.name);
        await tester.enterText(find.byKey(_editorKey), words.$2);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
      }

      expect(committedHeads, [
        for (final box in layout.headerFieldBoxes(0))
          if (typed[box.field] case (_, final next)) (box.field, next),
      ]);
      expect(committedHeads, hasLength(4));
      expect(committedMemos, isEmpty);
    });
  });

  test('the header prints the work\'s title and episode, the cut\'s 러프원화 '
      'worker as its 作業者, and leaves the scene to the pen', () {
    final document = _document();
    final printed = TimesheetDocumentPainter(
      words: timesheetWordsIn(AppLanguage.en),
      document: document,
      layout: TimesheetDocumentLayout(document: document),
      face: const TextStyle(),
    );

    expect(printed.headerValueFor(TimesheetHeaderField.title, 0), 'YOASOBI');
    expect(printed.headerValueFor(TimesheetHeaderField.episode, 0), 'MV');
    expect(printed.headerValueFor(TimesheetHeaderField.cut, 0), 'Cut 1');
    expect(printed.headerValueFor(TimesheetHeaderField.name, 0), '大川');
    expect(printed.headerValueFor(TimesheetHeaderField.scene, 0), '');
  });
}

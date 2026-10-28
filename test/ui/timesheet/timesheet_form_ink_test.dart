// THE SHEET'S FORM LEAVES INK WHERE THE RULES SAY: A ROW RULE ACROSS THE
// COLUMNS, THE FRAME NUMBERS IN THE LEFT MARGIN, AND AN S SLOT'S LETTERS ON
// THE LETTER ROW — WHILE A CEL ROW'S NAME THERE IS THE VALUES' INK.
//
// Three mutants of the paintHalf extraction (2026-09-03) survived every
// sheet test — the row rules, the row numbers and the column titles each
// never painted. The sheet tests look at the document, not at pixels;
// these pins rasterise a stratum and count ink in one place each.
//
// F-485 (유저 2026-10-27): 「서식은 진짜 서식만 있어야함. 그래서 A같은 셀
// 이름은 텍스트 층에 넣도록. S1이나 S2 이런 글자는 서식에 있어도 됨」.
// ↩️Every title printed with the form until then.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/timesheet/timesheet_words_in.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';

TimesheetDocument _document({String name = 'A'}) => TimesheetDocument.fromCut(
  cut: Cut(
    id: const CutId('cut-1'),
    name: '1',
    duration: 12,
    canvasSize: const CanvasSize(width: 1920, height: 1080),
    layers: [
      Layer(
        id: const LayerId('a'),
        name: name,
        frames: [
          Frame(id: const FrameId('a-f1'), duration: 1, strokes: const []),
        ],
        timeline: {
          0: const TimelineExposure.drawing(FrameId('a-f1'), length: 2),
        },
      ),
    ],
  ),
  projectName: 'P',
  fps: 24,
);

class _Form {
  _Form(this.layout, this.bytes, this.width);

  final TimesheetDocumentLayout layout;
  final Uint8List bytes;
  final int width;

  int inkIn(Rect rect) {
    var n = 0;
    for (var y = rect.top.floor(); y < rect.bottom.ceil(); y += 1) {
      for (var x = rect.left.floor(); x < rect.right.ceil(); x += 1) {
        if (bytes[(y * width + x) * 4 + 3] > 0) {
          n += 1;
        }
      }
    }
    return n;
  }
}

/// Rasterises the form stratum alone — or [layer].
Future<_Form> _paintForm(
  TimesheetDocument document, [
  SheetPaintLayer layer = SheetPaintLayer.form,
]) async {
  final layout = TimesheetDocumentLayout(document: document);
  final painter = TimesheetDocumentPainter(
    words: timesheetWordsIn(AppLanguage.en),
    face: const TextStyle(),
    document: document,
    layout: layout,
    layers: {layer},
  );
  final size = layout.documentSize;
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(size.width.ceil(), size.height.ceil());
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return _Form(layout, data!.buffer.asUint8List(), image.width);
}

void main() {
  test('a row rule runs across the first column', () async {
    final document = _document();
    final form = await _paintForm(document);
    final layout = form.layout;
    final left = layout.halfLeft(0, 0) + layout.columnLeftInHalf(0);
    final width = layout.columnWidthFor(document.columns[0].kind);
    // The rule under row 2 (row 0's top rule is the header's own line).
    final y = layout.halfRowsTop(0) + 3 * TimesheetDocumentLayout.rowHeight;
    expect(
      form.inkIn(Rect.fromLTWH(left + 2, y - 1.5, width - 4, 3)),
      greaterThan(0),
    );
  });

  test('the frame numbers print in the left margin', () async {
    final document = _document();
    final form = await _paintForm(document);
    final layout = form.layout;
    final numbersRight = layout.halfLeft(0, 0) - 4;
    final top = layout.halfRowsTop(0);
    expect(
      form.inkIn(
        Rect.fromLTWH(
          numbersRight - 24,
          top,
          24,
          TimesheetDocumentLayout.rowHeight * 4,
        ),
      ),
      greaterThan(0),
    );
  });

  /// The letter-row box over [column], inside its rules.
  Rect letterBox(TimesheetDocumentLayout layout, int column) {
    final kind = layout.document.columns[column].kind;
    final lettersTop =
        layout.halfRowsTop(0) - TimesheetDocumentLayout.letterRowHeight;
    return Rect.fromLTWH(
      layout.halfLeft(0, 0) + layout.columnLeftInHalf(column) + 1,
      lettersTop + 1,
      layout.columnWidthFor(kind) - 2,
      TimesheetDocumentLayout.letterRowHeight - 2,
    );
  }

  test('a cel row\'s name prints on the letter row with the values, and '
      'changes nothing the form prints', () async {
    final named = _document();
    final unnamed = _document(name: '');
    expect(
      (
        named.columns[0].kind,
        named.columns[0].label,
        unnamed.columns[0].label,
      ),
      (TimesheetColumnKind.action, 'A', ''),
      reason: '⛔fixture: row A heads the first column — or a row of no name',
    );
    final values = await _paintForm(named, SheetPaintLayer.content);
    final blank = await _paintForm(unnamed, SheetPaintLayer.content);
    expect(values.inkIn(letterBox(values.layout, 0)), greaterThan(0));
    expect(blank.inkIn(letterBox(blank.layout, 0)), 0, reason: '⛔CONTROL');
    final form = (await _paintForm(named)).bytes;
    final formOfNoName = (await _paintForm(unnamed)).bytes;
    var apart = 0;
    for (var i = 0; i < form.length; i += 1) {
      if (form[i] != formOfNoName[i]) {
        apart += 1;
      }
    }
    expect(
      (form.length, apart),
      (formOfNoName.length, 0),
      reason: 'the form never reads the film ([SheetPaintLayer.form])',
    );
  });

  test('an S slot\'s letters print on the letter row with the form', () async {
    final document = _document();
    final s1 = document.columns.indexWhere(
      (column) => column.kind == TimesheetColumnKind.se,
    );
    expect(document.columns[s1].label, 'S1', reason: '⛔fixture: an S slot');
    final form = await _paintForm(document);
    final values = await _paintForm(document, SheetPaintLayer.content);
    expect(form.inkIn(letterBox(form.layout, s1)), greaterThan(0));
    expect(values.inkIn(letterBox(values.layout, s1)), 0);
  });

  // 🗣️F-500 (유저 2026-10-29): 「전각 기준 3글자까지 보이도록. 그 후론 글자수
  // 작게하면서 버티다가 임계점넘어가면 ...으로 생략」 — Q2 b, the block word's
  // law: its size kept, its gaps then its width giving way. The test face
  // sets every letter an em wide, as a full-width one is.
  group('a column\'s title', () {
    const style = TextStyle(fontSize: 9);
    const room = 22.0;

    test('that fits is set as it is', () {
      final (:glyph, :fit) = columnTitleSetOnto('AB', style, room);
      expect((glyph.plainText, fit.x), ('AB', 1.0));
    });

    test('of three letters narrows to show all three, at its size', () {
      final (:glyph, :fit) = columnTitleSetOnto('ABC', style, room);
      expect(glyph.plainText, 'ABC');
      expect(fit.x, inExclusiveRange(columnTitleNarrowest, 1));
      expect(glyph.width * fit.x, lessThanOrEqualTo(room));
      expect(glyph.height, columnTitleSetOnto('AB', style, room).glyph.height);
    });

    test('that would narrow past half is cut short to what narrows no '
        'further', () {
      final (:glyph, :fit) = columnTitleSetOnto('ABCDEFGH', style, room);
      expect(glyph.plainText, 'ABCD…');
      expect(fit.x, greaterThanOrEqualTo(columnTitleNarrowest));
      expect(
        columnTitleSetOnto('ABCDE…', style, room).glyph.plainText,
        'ABCD…',
        reason: '⛔premise: one letter more would narrow past half',
      );
    });

    test('⛔in no room is still there', () {
      final (:glyph, :fit) = columnTitleSetOnto('A', style, 0);
      expect(glyph.plainText, '…');
      expect(fit.x, greaterThan(0));
    });

    test('of three letters prints across its column', () async {
      final values = await _paintForm(
        _document(name: 'ABC'),
        SheetPaintLayer.content,
      );
      final box = letterBox(values.layout, 0);
      final inked = [
        for (var x = box.left.floor(); x < box.right.ceil(); x += 1)
          if (values.inkIn(Rect.fromLTWH(x.toDouble(), box.top, 1, box.height)) >
              0)
            x,
      ];
      expect(
        inked.last - inked.first + 1,
        greaterThan(2 * style.fontSize!),
        reason: 'more than two letters\' width — ↩️「A…」',
      );
    });
  });
}

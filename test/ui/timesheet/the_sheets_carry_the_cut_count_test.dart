import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_words_in.dart';

/// F-252 (유저 2026-10-09): 「페이지별로 프레임번호 초기화한거 되돌려줘」 —
/// the gutter counts the CUT's frames, sheet after sheet: the second sheet
/// of a 24fps cut opens at 145, not at 1 — and 「초수도 반영해서 7부터
/// 시작한다던가」: its seconds carry on too, from 7. And 「24라는 숫자 제대로
/// 오게하고 그 왼쪽에 초 텍스트 … 1초마다 진한 가로선 … 그 가로선 옆에」 —
/// the frame that closes a second prints its number like any other, and the
/// second's index stands left of the numbers, on the bold rule.
///
/// ↩️Each sheet counted from 1, and the second's index printed in place of
/// its last frame's number.
void main() {
  group('the marks', () {
    ({int? number, String? second}) at(int frame, {int fps = 24}) =>
        timesheetGutterMarks(frame, fps: fps);

    test('even frames print their number; the odd ones print nothing', () {
      expect(at(0), (number: null, second: null));
      expect(at(1), (number: 2, second: null));
      expect(at(2), (number: null, second: null));
      expect(at(9), (number: 10, second: null));
    });

    test('the frame that closes a second prints its number AND the second', () {
      expect(at(23), (number: 24, second: '1'));
      expect(at(47), (number: 48, second: '2'));
    });

    test('the second sheet carries on the cut\'s count — 145 and 7, not 1',
        () {
      // 144 frames a sheet at 24fps (6 seconds): frame 144 is the second
      // sheet's first row.
      expect(at(144), (number: null, second: null));
      expect(at(145), (number: 146, second: null));
      expect(at(167), (number: 168, second: '7'));
      expect(at(287), (number: 288, second: '12'));
    });

    test('at an odd rate the second\'s last frame still prints its number', () {
      expect(at(24, fps: 25), (number: 25, second: '1'));
      expect(at(23, fps: 25), (number: 24, second: null));
    });
  });

  const row = TimesheetDocumentLayout.rowHeight;
  const gutter = TimesheetDocumentLayout.frameNumberGutterWidth;

  testWidgets('the second\'s index stands LEFT of the numbers, centred on '
      'the bold rule that closes it — and the 24 prints in the gutter',
      (tester) async {
    final sheets = await _printTwoSheets(tester);
    final half = sheets.layout.halfLeft(0, 0);
    final rowsTop = sheets.layout.halfRowsTop(0);
    // The band left of the numbers' gutter, [from] to [to] pixels off the
    // rule under row [rows] (rows counted from the half's top).
    int besideTheRule(int rows, {double from = -6, double to = 6}) {
      final rule = rowsTop + rows * row;
      return sheets.inked(
        half - gutter - 14,
        half - gutter,
        rule + from,
        rule + to,
      );
    }

    expect(
      besideTheRule(24),
      greaterThan(0),
      reason: 'the first second\'s index stands beside the rule under 24',
    );
    expect(
      besideTheRule(24, to: -1),
      greaterThan(0),
      reason: 'centred on the rule: it stands above it…',
    );
    expect(besideTheRule(24, from: 1), greaterThan(0), reason: '…and below');
    expect(
      besideTheRule(12),
      0,
      reason: 'a half-second\'s rule carries no index',
    );
    expect(
      besideTheRule(0),
      0,
      reason: 'the top of the sheet closes no second',
    );
    expect(
      sheets.inked(
        half - gutter,
        half,
        rowsTop + 23 * row,
        rowsTop + 24 * row,
      ),
      greaterThan(0),
      reason: 'the 24 prints in the gutter — the index no longer takes its '
          'place',
    );
  });

  testWidgets('the second sheet prints the cut\'s numbers and seconds — '
      'wider words where the first sheet\'s were one figure', (tester) async {
    final sheets = await _printTwoSheets(tester);
    final layout = sheets.layout;
    // How far left the number on row 1 of a sheet's first half reaches:
    // `2` on the first sheet, `146` on the second.
    int? numberReach(int page) {
      final half = layout.halfLeft(page, 0);
      final top = layout.halfRowsTop(page) + row;
      return sheets.leftmostInk(
        half - gutter - 8,
        half,
        top + 2,
        top + row - 2,
      );
    }

    // How far left the index on the rule under row 24 of a sheet's second
    // half reaches, in the gap between the halves: `4` on the first sheet,
    // `10` on the second.
    int? secondReach(int page) {
      final half = layout.halfLeft(page, 1);
      final rule = layout.halfRowsTop(page) + 24 * row;
      return sheets.leftmostInk(
        half - gutter - TimesheetDocumentLayout.halfGap + 2,
        half - gutter,
        rule - 6,
        rule + 6,
      );
    }

    expect(numberReach(0), isNotNull, reason: 'CONTROL: the first sheet\'s 2');
    expect(
      numberReach(1),
      lessThan(numberReach(0)!),
      reason: '146, not 2: the second sheet goes on with the cut\'s count',
    );
    expect(secondReach(0), isNotNull, reason: 'CONTROL: the first sheet\'s 4');
    expect(
      secondReach(1),
      lessThan(secondReach(0)!),
      reason: '10, not 4: its seconds go on too (「7부터 시작」)',
    );
  });
}

/// The form of a 150-frame, 24fps cut — two sheets — printed alone on no
/// paper: what is inked is what it prints.
Future<_Printed> _printTwoSheets(WidgetTester tester) async {
  // 150 frames at 24fps on 6-second pages: two sheets.
  final document = TimesheetDocument.fromCut(
    cut: Cut(
      id: const CutId('cut'),
      name: '1',
      layers: const [],
      duration: 150,
      canvasSize: const CanvasSize(width: 1280, height: 720),
    ),
    projectName: 'P',
    fps: 24,
  );
  expect(document.pages, hasLength(2), reason: 'fixture: two sheets');
  final layout = TimesheetDocumentLayout(document: document);

  final size = layout.documentSize;
  final width = size.width.ceil();
  final recorder = ui.PictureRecorder();
  TimesheetDocumentPainter(
    document: document,
    layout: layout,
    face: const TextStyle(),
    words: timesheetWordsIn(AppLanguage.ja),
    layers: const {SheetPaintLayer.form},
  ).paint(ui.Canvas(recorder), size);
  final picture = recorder.endRecording();
  final rgba = (await tester.runAsync(() async {
    final image = await picture.toImage(width, size.height.ceil());
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  }))!;
  picture.dispose();
  return _Printed(layout, width, rgba);
}

class _Printed {
  _Printed(this.layout, this.width, this.rgba);

  final TimesheetDocumentLayout layout;
  final int width;
  final Uint8List rgba;

  bool _inkedAt(int x, int y) => rgba[(y * width + x) * 4 + 3] != 0;

  /// How many pixels are inked in the box [left, right) × [top, bottom).
  int inked(double left, double right, num top, num bottom) {
    var count = 0;
    for (var y = top.floor(); y < bottom.ceil(); y += 1) {
      for (var x = left.floor(); x < right.ceil(); x += 1) {
        if (_inkedAt(x, y)) {
          count += 1;
        }
      }
    }
    return count;
  }

  /// The leftmost inked column of that box — how far left a word reaches.
  int? leftmostInk(double left, double right, num top, num bottom) {
    for (var x = left.floor(); x < right.ceil(); x += 1) {
      for (var y = top.floor(); y < bottom.ceil(); y += 1) {
        if (_inkedAt(x, y)) {
          return x;
        }
      }
    }
    return null;
  }
}

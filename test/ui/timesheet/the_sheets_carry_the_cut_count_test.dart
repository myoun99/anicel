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
/// of a 24fps cut opens at 145, not at 1. And 「24라는 숫자 제대로 오게하고
/// 그 왼쪽에 초 텍스트 … 1초마다 진한 가로선 … 그 가로선 옆에」 — the frame
/// that closes a second prints its number like any other, and the second's
/// index stands left of the numbers, on the bold rule.
///
/// ↩️Each sheet counted from 1, and the second's index printed in place of
/// its last frame's number.
void main() {
  group('the marks', () {
    ({int? number, int? second}) at(int frame, {int fps = 24}) =>
        timesheetGutterMarks(frame, fps: fps);

    test('even frames print their number; the odd ones print nothing', () {
      expect(at(0), (number: null, second: null));
      expect(at(1), (number: 2, second: null));
      expect(at(2), (number: null, second: null));
      expect(at(9), (number: 10, second: null));
    });

    test('the frame that closes a second prints its number AND the second', () {
      expect(at(23), (number: 24, second: 1));
      expect(at(47), (number: 48, second: 2));
    });

    test('the second sheet carries on the cut\'s count — 145, not 1', () {
      // 144 frames a sheet at 24fps (6 seconds): frame 144 is the second
      // sheet's first row.
      expect(at(144), (number: null, second: null));
      expect(at(145), (number: 146, second: null));
      expect(at(167), (number: 168, second: 7));
      expect(at(287), (number: 288, second: 12));
    });

    test('at an odd rate the second\'s last frame still prints its number', () {
      expect(at(24, fps: 25), (number: 25, second: 1));
      expect(at(23, fps: 25), (number: 24, second: null));
    });

    test('no rate, no seconds', () {
      expect(at(23, fps: 0), (number: 24, second: null));
    });
  });

  testWidgets('the second\'s index stands LEFT of the numbers, on the bold '
      'rule that closes it — and the 24 prints in the gutter', (tester) async {
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
      // The form alone, on no paper: what is inked is what it prints.
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

    const row = TimesheetDocumentLayout.rowHeight;
    const gutter = TimesheetDocumentLayout.frameNumberGutterWidth;

    /// How many pixels are inked in the box [left, right) × [top, bottom).
    int inked(Uint8List pixels, double left, double right, num top, num bottom) {
      var count = 0;
      for (var y = top.floor(); y < bottom.ceil(); y += 1) {
        for (var x = left.floor(); x < right.ceil(); x += 1) {
          if (pixels[(y * width + x) * 4 + 3] != 0) {
            count += 1;
          }
        }
      }
      return count;
    }

    final half = layout.halfLeft(0, 0);
    final rowsTop = layout.halfRowsTop(0);
    // The band left of the numbers' gutter, a little either side of the
    // rule under row [rows] (rows counted from the half's top).
    int besideTheRule(int rows) => inked(
      rgba,
      half - gutter - 14,
      half - gutter,
      rowsTop + rows * row - 6,
      rowsTop + rows * row + 6,
    );

    expect(
      besideTheRule(24),
      greaterThan(0),
      reason: 'the first second\'s index stands beside the rule under 24',
    );
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
      inked(rgba, half - gutter, half, rowsTop + 23 * row, rowsTop + 24 * row),
      greaterThan(0),
      reason: 'the 24 prints in the gutter — the index no longer takes its '
          'place',
    );
  });
}

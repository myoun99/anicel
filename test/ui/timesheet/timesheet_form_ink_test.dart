// THE SHEET'S FORM LEAVES INK WHERE THE RULES SAY: A ROW RULE ACROSS THE
// COLUMNS, THE FRAME NUMBERS IN THE LEFT MARGIN, AND THE COLUMN TITLES ON
// THE LETTER ROW.
//
// Three mutants of the paintHalf extraction (2026-09-03) survived every
// sheet test — the row rules, the row numbers and the column titles each
// never painted. The sheet tests look at the document, not at pixels;
// these pins rasterise the FORM stratum and count ink in one place each.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

TimesheetDocument _document() => TimesheetDocument.fromCut(
  cut: Cut(
    id: const CutId('cut-1'),
    name: '1',
    duration: 12,
    canvasSize: const CanvasSize(width: 1920, height: 1080),
    layers: [
      Layer(
        id: const LayerId('a'),
        name: 'A',
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

/// Rasterises the form stratum alone.
Future<_Form> _paintForm(TimesheetDocument document) async {
  final layout = TimesheetDocumentLayout(document: document);
  final painter = TimesheetDocumentPainter(
    face: const TextStyle(),
    document: document,
    layout: layout,
    layers: const {SheetPaintLayer.form},
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

  test('the column titles print on the letter row', () async {
    final document = _document();
    final form = await _paintForm(document);
    final layout = form.layout;
    final left = layout.halfLeft(0, 0) + layout.columnLeftInHalf(0);
    final width = layout.columnWidthFor(document.columns[0].kind);
    final lettersTop =
        layout.halfRowsTop(0) - TimesheetDocumentLayout.letterRowHeight;
    expect(
      form.inkIn(
        Rect.fromLTWH(
          left + 1,
          lettersTop + 1,
          width - 2,
          TimesheetDocumentLayout.letterRowHeight - 2,
        ),
      ),
      greaterThan(0),
    );
  });
}

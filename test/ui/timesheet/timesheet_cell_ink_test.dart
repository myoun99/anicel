// THE SHEET'S CELLS LEAVE INK WHERE THE RULES SAY: A DRAWING CELL PRINTS
// ITS LABEL, AND A HELD CELL PRINTS THE EXPOSURE BAR FROM THE THRESHOLD
// OFFSET ON — INCLUDING THE OFFSET EQUAL TO IT.
//
// Two mutants of the cell-kind cut (2026-09-03) survived every sheet test:
// drawing cells skipped entirely, and the bar's `>= threshold` read as
// `> threshold`. The sheet tests look at cell KINDS, not at pixels; these
// pins rasterise the content stratum and count ink inside one cell.
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
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';

Layer _animationLayer({required int length}) => Layer(
  id: const LayerId('a'),
  name: 'A',
  frames: [Frame(id: const FrameId('a-f1'), duration: 1, strokes: const [])],
  timeline: {
    0: TimelineExposure.drawing(const FrameId('a-f1'), length: length),
  },
);

TimesheetDocument _document({
  required int length,
  TimesheetInfo info = TimesheetInfo.empty,
}) => TimesheetDocument.fromCut(
  cut: Cut(
    id: const CutId('cut-1'),
    name: '1',
    duration: 12,
    canvasSize: const CanvasSize(width: 1920, height: 1080),
    layers: [_animationLayer(length: length)],
  ),
  projectName: 'P',
  fps: 24,
  info: info,
);

/// Rasterises the content stratum and counts the pixels with any ink inside
/// the cell at [row] of the first column.
Future<int> _inkInCell(TimesheetDocument document, {required int row}) async {
  final layout = TimesheetDocumentLayout(document: document);
  final painter = TimesheetDocumentPainter(
    document: document,
    layout: layout,
    layers: const {SheetPaintLayer.content},
  );
  final size = layout.documentSize;
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(size.width.ceil(), size.height.ceil());
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  final bytes = data!.buffer.asUint8List();
  final width = image.width;

  final left = layout.halfLeft(0, 0) + layout.columnLeftInHalf(0);
  final top = layout.halfRowsTop(0) + row * TimesheetDocumentLayout.rowHeight;
  final columnWidth = layout.columnWidthFor(document.columns[0].kind);
  return _inkIn(
    bytes,
    width,
    Rect.fromLTWH(left, top, columnWidth, TimesheetDocumentLayout.rowHeight),
  );
}

int _inkIn(Uint8List rgba, int width, Rect rect) {
  var n = 0;
  for (var y = rect.top.floor(); y < rect.bottom.ceil(); y += 1) {
    for (var x = rect.left.floor(); x < rect.right.ceil(); x += 1) {
      if (rgba[(y * width + x) * 4 + 3] > 0) {
        n += 1;
      }
    }
  }
  return n;
}

void main() {
  test('a drawing cell prints its label', () async {
    final document = _document(length: 2);
    expect(document.columns[0].cells[0].kind, TimesheetCellKind.drawing);
    expect(await _inkInCell(document, row: 0), greaterThan(0));
  });

  test('the exposure bar starts AT the threshold offset', () async {
    final document = _document(
      length: 3,
      info: const TimesheetInfo(exposureBarThreshold: 1),
    );
    expect(document.columns[0].cells[1].kind, TimesheetCellKind.held);
    expect(document.columns[0].cells[1].spanOffset, 1, reason: 'fixture');
    expect(await _inkInCell(document, row: 1), greaterThan(0));
  });

  test('below the threshold a held cell stays bare', () async {
    final document = _document(
      length: 3,
      info: const TimesheetInfo(exposureBarThreshold: 2),
    );
    expect(await _inkInCell(document, row: 1), 0);
  });
}

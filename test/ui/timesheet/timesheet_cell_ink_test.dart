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
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/timesheet/timesheet_words_in.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';

Layer _animationLayer({
  required int length,
  String id = 'a',
  LayerMark mark = LayerMark.none,
}) => Layer(
  id: LayerId(id),
  mark: mark,
  name: 'A',
  frames: [Frame(id: FrameId('$id-f1'), duration: 1, strokes: const [])],
  timeline: {
    0: TimelineExposure.drawing(FrameId('$id-f1'), length: length),
  },
);

TimesheetDocument _document({
  required int length,
  TimesheetInfo info = TimesheetInfo.empty,
  List<Layer>? layers,
}) => TimesheetDocument.fromCut(
  cut: Cut(
    id: const CutId('cut-1'),
    name: '1',
    duration: 12,
    canvasSize: const CanvasSize(width: 1920, height: 1080),
    layers: layers ?? [_animationLayer(length: length)],
  ),
  projectName: 'P',
  fps: 24,
  info: info,
);

/// Rasterises the content stratum and counts the pixels with any ink inside
/// the cell at [row] of [column].
Future<int> _inkInCell(
  TimesheetDocument document, {
  required int row,
  int column = 0,
}) async {
  final layout = TimesheetDocumentLayout(document: document);
  final painter = TimesheetDocumentPainter(
    words: timesheetWordsIn(AppLanguage.en),
    face: const TextStyle(),
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

  final left = layout.halfLeft(0, 0) + layout.columnLeftInHalf(column);
  final top = layout.halfRowsTop(0) + row * TimesheetDocumentLayout.rowHeight;
  final columnWidth = layout.columnWidthFor(document.columns[column].kind);
  // Two pixels in from each side: a neighbour's ink (the SE wash) lands on
  // the shared edge's split pixel and would read as this cell's own.
  return _inkIn(
    bytes,
    width,
    Rect.fromLTWH(
      left + 2,
      top,
      columnWidth - 4,
      TimesheetDocumentLayout.rowHeight,
    ),
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

  // F-430 (유저 2026-10-21): 「이 늘림 선은 x부분 이후도 늘림선 긋는것임.
  // 진짜 어디던 긋는느낌」.
  test('the stretch line runs on down the empty run past an ×, from the '
      'threshold offset counted from the ×', () async {
    final document = _document(
      length: 3,
      info: const TimesheetInfo(exposureBarThreshold: 1),
    );
    final cells = document.columns[0].cells;
    expect(cells[3].kind, TimesheetCellKind.emptyRunStart, reason: 'fixture');
    expect(cells[4].kind, TimesheetCellKind.emptyRunSpan);
    expect(cells[4].spanOffset, 1);
    expect(await _inkInCell(document, row: 4), greaterThan(0));

    final later = _document(
      length: 3,
      info: const TimesheetInfo(exposureBarThreshold: 2),
    );
    expect(await _inkInCell(later, row: 4), 0);
    expect(await _inkInCell(later, row: 5), greaterThan(0));
  });

  // F-430: 「액션란이랑 셀란 늘림선 따로따로 적용가능하게 나누고, 액션은
  // 늘림선 기본 없음 … 셀란은 기본 있음, 1코마」.
  test('by default the CELL block draws its stretch line from the second '
      'comma, past its × too, and the ACTION block draws none', () async {
    final document = _document(
      length: 0,
      layers: [
        _animationLayer(length: 3),
        _animationLayer(
          length: 3,
          id: 'ib',
          mark: const LayerMark(process: LayerProcess.inbetween),
        ),
      ],
    );
    final cell = document.columns.indexWhere(
      (column) => column.kind == TimesheetColumnKind.cel,
    );
    expect(document.columns[0].kind, TimesheetColumnKind.action);
    expect(document.columns[cell].layerId, const LayerId('ib'));

    expect(await _inkInCell(document, row: 1, column: cell), greaterThan(0));
    expect(await _inkInCell(document, row: 4, column: cell), greaterThan(0));
    expect(await _inkInCell(document, row: 1), 0);
    expect(await _inkInCell(document, row: 4), 0);
  });

  test('each block draws by its own threshold', () async {
    final document = _document(
      length: 0,
      info: const TimesheetInfo(
        exposureBarThreshold: 1,
        cellExposureBarThreshold: null,
      ),
      layers: [
        _animationLayer(length: 3),
        _animationLayer(
          length: 3,
          id: 'ib',
          mark: const LayerMark(process: LayerProcess.inbetween),
        ),
      ],
    );
    final cell = document.columns.indexWhere(
      (column) => column.kind == TimesheetColumnKind.cel,
    );

    expect(await _inkInCell(document, row: 1), greaterThan(0));
    expect(await _inkInCell(document, row: 1, column: cell), 0);
  });
}

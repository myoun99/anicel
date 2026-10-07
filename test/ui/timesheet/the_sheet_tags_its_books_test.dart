// D24 후반 — the sheet tags its books over the ACTION block (유저
// 2026-09-25, 사진 셋 TOEI_book · TOEI_book_all · TOEI_3sec): a blue tag
// over each boundary a book lies at, on every half, the tags stepping down
// to the right, each with a leader line down to the grid; stacked up from
// the memo band's bottom, the paper's size kept (timesheet-book-tag-place-Q1:
// 「메모 띠 아래쪽에 겹쳐 쌓는다 (크기 그대로)」).
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_words_in.dart';

/// The reference sheets' tag blue (TOEI_book.jpg, measured).
const _tagBlue = Color(0xFF4169E1);

Layer _cels(String name) =>
    Layer(id: LayerId(name), name: name, frames: const []);

Layer _book(String id, String frame) => Layer(
  id: LayerId(id),
  name: 'BOOK',
  kind: LayerKind.image,
  mark: const LayerMark(process: LayerProcess.art),
  frames: [
    Frame(
      id: FrameId('$id-f'),
      duration: 1,
      strokes: const [],
      name: frame,
    ),
  ],
);

/// Books between A and B and over C, the last column.
final _document = TimesheetDocument.fromCut(
  cut: Cut(
    id: const CutId('cut'),
    name: '1',
    duration: 24,
    canvasSize: const CanvasSize(width: 1920, height: 1080),
    layers: [
      _cels('A'),
      _book('b1', '1'),
      _cels('B'),
      _cels('C'),
      _book('b2', '2'),
    ],
  ),
  projectName: 'P',
  fps: 24,
);

void main() {
  test('each book\'s tag stands over its boundary on every half — the last '
      'on the memo band\'s bottom, each before it a step higher', () {
    final layout = TimesheetDocumentLayout(document: _document);
    final floor =
        layout.memoBandRect(0).bottom -
        TimesheetDocumentLayout.bookTagFloorGap;
    const column = TimesheetDocumentLayout.actionColumnWidth;

    expect(layout.halfStrips, hasLength(2), reason: '⛔전제: a 6s page');
    for (final strip in layout.halfStrips) {
      final left = layout.halfLeft(0, strip.half);
      expect(layout.bookTags(0, strip.half), [
        (
          label: 'BOOK1',
          x: left + column,
          bottom: floor - TimesheetDocumentLayout.bookTagStep,
        ),
        (label: 'BOOK2', x: left + column * 3, bottom: floor),
      ]);
    }
  });

  test('the painter lays each tag there — a blue box right of its leader '
      'line, the line running down to the grid', () {
    final layout = TimesheetDocumentLayout(document: _document);
    final laid = _Laid();
    TimesheetDocumentPainter(
      words: timesheetWordsIn(AppLanguage.en),
      face: const TextStyle(),
      document: _document,
      layout: layout,
      layers: const {SheetPaintLayer.content},
    ).paint(laid, layout.documentSize);

    const halves = [0, 1];
    final boxes = [
      for (final rect in laid.rects)
        if (rect.color.toARGB32() == _tagBlue.toARGB32()) rect.rect,
    ];
    expect(boxes, hasLength(halves.length * 2));
    for (final half in halves) {
      for (final tag in layout.bookTags(0, half)) {
        final box = boxes.singleWhere(
          (box) =>
              (box.bottom - tag.bottom).abs() < 1e-6 &&
              box.left > tag.x &&
              box.left - tag.x < 8,
        );
        expect(
          laid.lines,
          contains((
            from: Offset(tag.x, box.center.dy),
            to: Offset(
              tag.x,
              layout.memoBandRect(0).bottom +
                  TimesheetDocumentLayout.headerGap,
            ),
          )),
          reason:
              'the leader line: from the tag down across the gap under '
              'the memo band, to the grid',
        );
      }
    }
  });
}

class _Laid implements Canvas {
  final rects = <({Rect rect, Color color})>[];
  final lines = <({Offset from, Offset to})>[];
  final _saved = <Matrix4>[];
  var _transform = Matrix4.identity();

  @override
  void save() => _saved.add(_transform.clone());

  @override
  void saveLayer(Rect? bounds, Paint paint) => save();

  @override
  void restore() => _transform = _saved.removeLast();

  @override
  void translate(double dx, double dy) =>
      _transform = _transform.multiplied(Matrix4.translationValues(dx, dy, 0));

  @override
  void scale(double sx, [double? sy]) => _transform = _transform.multiplied(
    Matrix4.diagonal3Values(sx, sy ?? sx, 1),
  );

  @override
  void drawRect(Rect rect, Paint paint) => rects.add((
    rect: MatrixUtils.transformRect(_transform, rect),
    color: paint.color,
  ));

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => lines.add((
    from: MatrixUtils.transformPoint(_transform, p1),
    to: MatrixUtils.transformPoint(_transform, p2),
  ));

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) {}

  @override
  int getSaveCount() => _saved.length + 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

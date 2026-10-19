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
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_words_in.dart';

import '../../helpers/painted_glyph_boxes.dart';

/// The sheet's ink as its painter lays it: [PaintedGlyphBoxes]' paragraph
/// boxes, and the lines and rects it draws, with their colours. The cells
/// pass draws those in document space, untransformed.
class _SheetInk extends PaintedGlyphBoxes {
  final lines = <({Offset from, Offset to, int argb})>[];
  final rects = <({Rect rect, int argb})>[];

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) =>
      lines.add((from: p1, to: p2, argb: paint.color.toARGB32()));

  @override
  void drawRect(Rect rect, Paint paint) =>
      rects.add((rect: rect, argb: paint.color.toARGB32()));
}

/// 🗣️F-358 (유저 2026-10-14): 「여러 컷에 걸친 se블록이 있을때, 글로벌에선
/// e라는 글자가 보이는 구간인데 로컬에선 T라는게 보인다던가 … 위치는 같도록.
/// 글로벌기준으로」 · 「타임시트패널도 지금 글자 보이는거 다른데, 제대로 글로벌
/// 기준으로 맞춰서 위치통일」 · 「타임시트패널에도 타임라인에서 보이는 글자
/// 나눠짐상태? 그대로 보이도록. 즉 오프셋 맞추듯이?」.
///
/// One sound over three cuts' sheets: its words laid out ONCE over the whole
/// block, each sheet — and each page half on it — a window on that layout.
/// Measured as the ink the three sheets paint, put back on the track's axis:
/// together they print the line once, evenly, as one run.
void main() {
  const rowHeight = TimesheetDocumentLayout.rowHeight;
  const words = 'ABCDEFGHIJ';
  // Three cuts of 24; the sound runs global [16, 56): its head in the first
  // cut, through the whole second, into the third. A page is one second, so
  // each cut's sheet is one page of two 12-row halves — and the sound runs
  // past the first two sheets' rows, not only their cuts.
  const cutStarts = [0, 24, 48];

  TimesheetDocument sheetAt(
    int cutStart, {
    String? seName = 'N',
    int pageSeconds = 1,
  }) => TimesheetDocument.fromCut(
    cut: Cut(
      id: CutId('cut-$cutStart'),
      name: '$cutStart',
      duration: 24,
      canvasSize: const CanvasSize(width: 1920, height: 1080),
      layers: const [],
    ),
    projectName: 'P',
    fps: 24,
    pageSeconds: pageSeconds,
    trackSeLayers: [
      Layer(
        id: const LayerId('se'),
        name: 'SE1',
        kind: LayerKind.se,
        frames: [
          Frame(
            id: const FrameId('s'),
            duration: 40,
            strokes: const [],
            name: words,
            seName: seName,
          ),
        ],
        timeline: {
          16: const TimelineExposure.drawing(FrameId('s'), length: 40),
        },
      ),
    ],
    cutStartFrame: cutStart,
  );

  /// Where [at] stands on the TRACK when the sheet of the cut at [cutStart]
  /// paints it in its SE column — in rows, from the track's start — or null
  /// outside that column.
  double? trackRowOf(
    TimesheetDocument sheet,
    TimesheetDocumentLayout layout,
    int cutStart,
    Offset at,
  ) {
    final column = sheet.columns.indexWhere(
      (column) => column.kind == TimesheetColumnKind.se,
    );
    final width = layout.columnWidthFor(TimesheetColumnKind.se);
    for (final half in [0, 1]) {
      final left = layout.halfLeft(0, half) + layout.columnLeftInHalf(column);
      if (at.dx >= left - 0.5 &&
          at.dx <= left + width + 0.5 &&
          at.dy >= layout.halfRowsTop(0)) {
        return cutStart +
            half * sheet.halfFrameCount +
            (at.dy - layout.halfRowsTop(0)) / rowHeight;
      }
    }
    return null;
  }

  /// What the SE column of the cut at [cutStart] wears, on the track's
  /// axis: the writing's centres, the red bars' rows, the name boxes'.
  ({List<double> writing, List<double> bars, List<double> boxes}) inkOf(
    int cutStart, {
    String? seName = 'N',
    int pageSeconds = 1,
  }) {
    // The name box's tint — not the wash an empty row wears.
    final nameBox = AppColors.accent.withValues(alpha: 0.3).toARGB32();
    final sheet = sheetAt(
      cutStart,
      seName: seName,
      pageSeconds: pageSeconds,
    );
    final layout = TimesheetDocumentLayout(document: sheet);
    final ink = _SheetInk();
    TimesheetDocumentPainter(
      words: timesheetWordsIn(AppLanguage.en),
      face: const TextStyle(),
      document: sheet,
      layout: layout,
    ).paint(ink, Size(layout.paperLeft + layout.paperWidth + 8, 2000));
    double? row(Offset at) => trackRowOf(sheet, layout, cutStart, at);
    bool inColumn(Offset from, Offset to) =>
        row(from) != null && row(to) != null;
    return (
      writing: [
        for (final box in ink.boxes) ?row(box.center),
      ]..sort(),
      bars: [
        for (final line in ink.lines)
          if (line.argb == AppColors.danger.toARGB32() &&
              inColumn(line.from, line.to))
            row(line.from)!,
      ],
      boxes: [
        for (final fill in ink.rects)
          if (fill.argb == nameBox &&
              inColumn(fill.rect.topLeft, fill.rect.bottomRight))
            row(fill.rect.topLeft)!,
      ],
    );
  }

  test('the three sheets print the line ONCE, evenly, as one run — each '
      'showing the part of it its rows hold', () {
    final writing = [for (final start in cutStarts) ...inkOf(start).writing]
      ..sort();
    // The name rides the head; the words follow it.
    expect(writing.first, inInclusiveRange(16, 17), reason: 'the name');
    final glyphs = writing.skip(1).toList();
    expect(glyphs, hasLength(words.length), reason: 'none lost, none twice');
    final steps = [
      for (var i = 1; i < glyphs.length; i += 1) glyphs[i] - glyphs[i - 1],
    ];
    for (final step in steps) {
      expect(step, closeTo(steps.first, 1e-3), reason: '$glyphs');
    }
    expect(
      [for (final start in cutStarts) inkOf(start).writing.length],
      everyElement(greaterThan(0)),
      reason: '⛔전제: every sheet holds a part of the line',
    );
  });

  // 🗣️F-358-Q1 (유저 10-18): each glyph on the frame the rows lay it on
  // (`seSpanParts`) — a named sound's words over its frames after the head,
  // an unnamed one's over all of them, edge to edge.
  for (final seName in ['N', null]) {
    test('the words stand on the frames the rows lay them on '
        '(${seName == null ? 'no name' : 'named'})', () {
      final writing = [
        for (final start in cutStarts) ...inkOf(start, seName: seName).writing,
      ]..sort();
      final glyphs = seName == null ? writing : writing.skip(1).toList();
      final from = seName == null ? 16 : 17;
      final cell = (56 - from) / words.length;
      expect(glyphs, hasLength(words.length));
      for (final (index, centre) in glyphs.indexed) {
        expect(
          centre,
          closeTo(from + (index + 0.5) * cell, 0.02),
          reason: 'glyph $index',
        );
      }
    });
  }

  // 🗣️F-358 (유저 2026-10-17): 「컷 엔드라인(OL여백이든 뭐든 총합적인
  // 엔드라인) 넘어가는건 안보이게하고」.
  test('the rows a page has past the line the cut is drawn to print none '
      'of it', () {
    // A page of 48: the first cut's sound runs on past its 24 rows, onto
    // the half the page holds and the cut does not.
    final ink = inkOf(0, pageSeconds: 2);

    expect(ink.writing, isNotEmpty, reason: '⛔전제');
    expect(ink.writing, everyElement(lessThan(24)));
    expect(
      ink.bars,
      [closeTo(16, 0.2)],
      reason: 'it opens, and closes on no row the cut has',
    );
  });

  test('the head is the first cut\'s and the end the last\'s: the opening '
      'bar and the name box at 16, the closing bar under 55 — and nothing '
      'of either on the sheets the sound only runs through', () {
    final first = inkOf(0);
    final middle = inkOf(24);
    final last = inkOf(48);

    expect(first.bars, [closeTo(16, 0.2)], reason: 'it opens; it never closes');
    expect(first.boxes, [closeTo(16, 0.2)]);
    expect(middle.bars, isEmpty);
    expect(middle.boxes, isEmpty);
    expect(last.bars, [closeTo(56, 0.2)], reason: 'it closes under 55');
    expect(last.boxes, isEmpty);
  });
}

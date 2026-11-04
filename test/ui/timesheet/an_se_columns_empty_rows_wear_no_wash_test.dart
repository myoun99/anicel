import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/camera_instruction.dart';
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
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_words_in.dart';

import '../../helpers/painted_glyph_boxes.dart';

/// The rects the sheet's painter lays, as it lays them.
class _SheetRects extends PaintedGlyphBoxes {
  final rects = <({Rect rect, int argb})>[];

  @override
  void drawRect(Rect rect, Paint paint) =>
      rects.add((rect: rect, argb: paint.color.toARGB32()));
}

/// 🗣️F-557 (유저 2026-11-04): 「타임시트 용지 출력한걸로 확인했는데, 우선
/// se블록이랑 se가 없는곳의 반투명 영역이랑 같은 층인게 맘에안듬. 이걸
/// psd로 받아서 대사 위치 수정하기 힘든느낌. 그래서 그냥 대사 없는 구간
/// 칠하는 기능자체를 삭제」.
///
/// ↩️An SE column's empty rows wore a light-gray "no SE here" wash, down to
/// the line the cut is drawn to (F-340) — the のりしろ an O.L asks of it
/// included, which this sheet still draws.
void main() {
  const rowHeight = TimesheetDocumentLayout.rowHeight;

  test('no empty row of an SE column is washed — down to the のりしろ an '
      'O.L leaving the cut asks', () {
    // A 24-frame cut an O.L leaves over 18..29: the sheet is drawn to 30.
    final sheet = TimesheetDocument.fromCut(
      cut: Cut(
        id: const CutId('c'),
        name: 'c',
        duration: 24,
        canvasSize: const CanvasSize(width: 1920, height: 1080),
        layers: const [],
      ),
      projectName: 'P',
      fps: 24,
      pageSeconds: 6,
      cutStartFrame: 0,
      transitionSpans: const [
        (start: 18, length: 12, mark: CameraInstructionMarkType.ol),
      ],
      trackSeLayers: [
        Layer(
          id: const LayerId('se'),
          name: 'SE1',
          kind: LayerKind.se,
          frames: [
            Frame(
              id: const FrameId('s'),
              duration: 2,
              strokes: const [],
              name: 'A',
            ),
          ],
          timeline: const {
            2: TimelineExposure.drawing(FrameId('s'), length: 2),
          },
        ),
      ],
    );
    expect(sheet.drawnFrameCount, 30, reason: '⛔전제: the のりしろ is drawn');
    final layout = TimesheetDocumentLayout(document: sheet);
    final ink = _SheetRects();
    TimesheetDocumentPainter(
      words: timesheetWordsIn(AppLanguage.en),
      face: const TextStyle(),
      document: sheet,
      layout: layout,
    ).paint(ink, Size(layout.paperLeft + layout.paperWidth + 8, 4000));

    final column = sheet.columns.indexWhere(
      (column) => column.kind == TimesheetColumnKind.se,
    );
    expect(column, isNot(-1), reason: '⛔전제: the sheet has its SE column');
    final left = layout.halfLeft(0, 0) + layout.columnLeftInHalf(column);
    final width = layout.columnWidthFor(TimesheetColumnKind.se);
    final washed = {
      for (final fill in ink.rects)
        // The wash: a faint row-high rect across the column.
        if (fill.argb >>> 24 < 0x20 &&
            (fill.rect.left - left).abs() < 0.5 &&
            (fill.rect.width - width).abs() < 0.5 &&
            (fill.rect.height - rowHeight).abs() < 0.5)
          ((fill.rect.top - layout.halfRowsTop(0)) / rowHeight).round(),
    };

    expect(washed, isEmpty);
  });
}

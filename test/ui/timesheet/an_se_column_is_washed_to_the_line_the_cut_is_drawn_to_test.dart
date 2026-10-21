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

/// 🗣️F-340 (유저 2026-10-11): 「OL추가시 타임시트패널에서 se행의 회색칸이
/// 끝까지 안이어짐. OL여백으로 생긴 엔드라인은 그 경우 그게 왠만한
/// 경우에선 진짜 엔드라인을 대체하는 방식인데, SE행이 아직 그 방식
/// 안쓰는듯」 — an SE column's empty rows wear the "no SE here" wash down to
/// the line the cut is DRAWN to, the のりしろ an O.L asks of it included.
void main() {
  const rowHeight = TimesheetDocumentLayout.rowHeight;

  test('the wash runs through the のりしろ an O.L leaving the cut asks — '
      'every empty row the column shows, and none past it', () {
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

    expect(washed, {
      for (var row = 0; row < 30; row += 1)
        if (row != 2 && row != 3) row,
    });
  });
}

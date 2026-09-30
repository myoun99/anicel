import 'dart:ui' as ui;

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
import 'package:anicel/src/models/se_line_type.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_words_in.dart';

/// 🗣️I-20 (유저 2026-09-30): 「이 텍스트는 타임시트에도 이름 위에 빨간 가로선
/// 위에 배경색없이 텍스트만 띄우도록」 · 「ON일때는 타임시트 이름위 … 표시하지
/// 않음 … OFF거나 MONO일때만」.
///
/// ⚠️The oracle is the DIFFERENCE between two paintings of one sheet that
/// differ only in the block's delivery: OFF adds exactly one paragraph, and
/// it sits above the block's first row — never a count taken alone.
void main() {
  const startRow = 3;

  TimesheetDocument sheet(SeLineType type) => TimesheetDocument.fromCut(
    cut: Cut(
      id: const CutId('cut-1'),
      name: '1',
      duration: 12,
      canvasSize: const CanvasSize(width: 1920, height: 1080),
      layers: [
        Layer(
          id: const LayerId('s'),
          name: 'S1',
          kind: LayerKind.se,
          frames: [
            Frame(
              id: const FrameId('s-f1'),
              duration: 4,
              strokes: const [],
              name: 'やめて',
              seName: 'A子',
              seType: type,
            ),
          ],
          timeline: {
            startRow: const TimelineExposure.drawing(
              FrameId('s-f1'),
              length: 4,
            ),
          },
        ),
      ],
    ),
    projectName: 'P',
    fps: 24,
    instructionDefById: CameraInstructionSet.standard.defById,
  );

  List<Offset> paragraphsOf(TimesheetDocument document) {
    final painted = _Paragraphs();
    final layout = TimesheetDocumentLayout(document: document);
    TimesheetDocumentPainter(
      words: timesheetWordsIn(AppLanguage.en),
      document: document,
      layout: layout,
    ).paint(painted, layout.documentSize);
    return painted.offsets;
  }

  testWidgets('ON prints nothing over the bar; OFF and MONO print one line '
      'there', (tester) async {
    final on = paragraphsOf(sheet(SeLineType.on));
    for (final type in [SeLineType.off, SeLineType.mono]) {
      final document = sheet(type);
      final layout = TimesheetDocumentLayout(document: document);
      final painted = paragraphsOf(document);
      expect(painted.length, on.length + 1, reason: type.name);
      final extra = painted.where((offset) => !on.contains(offset)).single;
      final rowTop = layout.frameRowTop(startRow);
      expect(
        extra.dy,
        lessThan(rowTop),
        reason: '${type.name}: over the red bar, not across the name',
      );
      expect(extra.dy, greaterThan(rowTop - 12), reason: 'right over it');
    }
  });
}

class _Paragraphs implements Canvas {
  final offsets = <Offset>[];

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) =>
      offsets.add(offset);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

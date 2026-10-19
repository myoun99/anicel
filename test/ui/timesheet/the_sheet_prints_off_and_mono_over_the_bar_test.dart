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
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_words_in.dart';

/// 🗣️I-20 (유저 2026-09-30): 「이 텍스트는 타임시트에도 이름 위에 빨간 가로선
/// 위에 배경색없이 텍스트만 띄우도록」 · 「ON일때는 타임시트 이름위 … 표시하지
/// 않음 … OFF거나 MONO일때만」.
///
/// ⚠️The oracle is the DIFFERENCE between two paintings of one sheet that
/// differ only in the block's delivery: OFF adds exactly one paragraph, and
/// it sits above the block's first row — never a count taken alone.
///
/// 🗣️F-358 (유저 2026-10-19): 「se의 시작 빨간라인 위에 이름두도록 … 기존의
/// off같은 타입글자를 위로 이동하고 거기에 이름넣는거지」 — so it stands on
/// the name where there is one.
void main() {
  const startRow = 3;

  TimesheetDocument sheet(SeLineType type, {String? seName = 'A子'}) =>
      TimesheetDocument.fromCut(
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
              seName: seName,
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

  _Paragraphs paint(TimesheetDocument document) {
    final painted = _Paragraphs();
    final layout = TimesheetDocumentLayout(document: document);
    TimesheetDocumentPainter(
      words: timesheetWordsIn(AppLanguage.en),
      face: const TextStyle(),
      document: document,
      layout: layout,
    ).paint(painted, layout.documentSize);
    return painted;
  }

  /// Where OFF or MONO writes, next to what ON writes on the same sheet.
  Offset deliveryOf(SeLineType type, {String? seName = 'A子'}) {
    final on = paint(sheet(SeLineType.on, seName: seName)).offsets;
    final painted = paint(sheet(type, seName: seName)).offsets;
    expect(painted.length, on.length + 1, reason: type.name);
    return painted.where((offset) => !on.contains(offset)).single;
  }

  testWidgets('ON prints nothing over the name; OFF and MONO print one line '
      'right over it — and the name stands over the red bar', (tester) async {
    final layout = TimesheetDocumentLayout(document: sheet(SeLineType.on));
    final rowTop = layout.frameRowTop(startRow);
    final nameBox = paint(sheet(SeLineType.on)).rects.single;
    expect(nameBox.bottom, lessThan(rowTop), reason: 'over the bar');
    expect(nameBox.top, greaterThan(rowTop - 18), reason: 'in the row above');
    for (final type in [SeLineType.off, SeLineType.mono]) {
      final delivery = deliveryOf(type);
      expect(
        delivery.dy,
        lessThan(nameBox.top),
        reason: '${type.name}: over the name, not across it',
      );
      expect(delivery.dy, greaterThan(nameBox.top - 12), reason: 'right over');
    }
  });

  testWidgets('with no name, OFF and MONO print one line right over the red '
      'bar', (tester) async {
    final layout = TimesheetDocumentLayout(document: sheet(SeLineType.on));
    final rowTop = layout.frameRowTop(startRow);
    expect(paint(sheet(SeLineType.on, seName: null)).rects, isEmpty);
    for (final type in [SeLineType.off, SeLineType.mono]) {
      final delivery = deliveryOf(type, seName: null);
      expect(delivery.dy, lessThan(rowTop), reason: '${type.name}: over it');
      expect(delivery.dy, greaterThan(rowTop - 12), reason: 'right over it');
    }
  });
}

class _Paragraphs implements Canvas {
  final offsets = <Offset>[];

  /// The name boxes laid: rects in the name's accent tint.
  final rects = <Rect>[];

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) =>
      offsets.add(offset);

  @override
  void drawRect(Rect rect, Paint paint) {
    if (paint.color == AppColors.accent.withValues(alpha: 0.3)) {
      rects.add(rect);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

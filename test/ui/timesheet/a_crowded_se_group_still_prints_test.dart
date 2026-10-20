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
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_words_in.dart';

/// **A sheet whose S group holds more columns than its width has room for
/// still prints.**
///
/// The S group is the form's fixed width, shared by its columns; a word in
/// a column is laid two pixels narrower than the column. 🔬Past twenty
/// columns that room went below zero, and the sheet stopped on an
/// assertion as it laid the first title (found 2026-10-21 with 26 S rows).
void main() {
  Layer seLayer(int index) => Layer(
    id: LayerId('s$index'),
    name: 'S${index + 1}',
    kind: LayerKind.se,
    frames: [
      Frame(id: FrameId('s$index-f1'), duration: 1, strokes: const []),
    ],
    timeline: {
      0: TimelineExposure.drawing(FrameId('s$index-f1'), length: 3),
    },
  );

  testWidgets('twenty-six S columns print, titles and entries', (
    tester,
  ) async {
    final document = TimesheetDocument.fromCut(
      cut: Cut(
        id: const CutId('cut-1'),
        name: '1',
        duration: 12,
        canvasSize: const CanvasSize(width: 1920, height: 1080),
        layers: [for (var index = 0; index < 26; index += 1) seLayer(index)],
      ),
      projectName: 'P',
      fps: 24,
    );
    final layout = TimesheetDocumentLayout(document: document);
    final columns = [
      for (final column in document.columns)
        if (column.kind == TimesheetColumnKind.se) column,
    ];
    expect(columns, hasLength(26), reason: '⛔전제');
    expect(
      layout.columnWidthFor(TimesheetColumnKind.se),
      lessThan(2),
      reason: '⛔전제: a column narrower than a word\'s margins',
    );
    final painter = TimesheetDocumentPainter(
      words: timesheetWordsIn(AppLanguage.en),
      document: document,
      layout: layout,
      face: const TextStyle(),
    );
    final size = Size(layout.paperLeft + layout.paperWidth + 8, 512);

    final recorder = ui.PictureRecorder();
    expect(() => painter.paint(Canvas(recorder), size), returnsNormally);
    recorder.endRecording().dispose();
  });
}

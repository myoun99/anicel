import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_words_in.dart';

/// Each sheet counts its own frames: the gutter beside a page's rows reads
/// 2, 4, 6 … and the seconds from THAT page's first frame, as printed paper
/// does sheet after sheet — never the cut's running count.
///
/// The words cannot be read back off a canvas, so the oracle is the
/// pixels: the second sheet's gutter prints exactly what the first's does.
void main() {
  testWidgets('the second sheet\'s gutter prints what the first\'s does', (
    tester,
  ) async {
    // 150 frames at 24fps on 6-second pages: two sheets.
    final document = TimesheetDocument.fromCut(
      cut: Cut(
        id: const CutId('cut'),
        name: '1',
        layers: const [],
        duration: 150,
        canvasSize: const CanvasSize(width: 1280, height: 720),
      ),
      projectName: 'P',
      fps: 24,
    );
    expect(document.pages, hasLength(2), reason: 'fixture: two sheets');
    final layout = TimesheetDocumentLayout(document: document);

    final size = layout.documentSize;
    final width = size.width.ceil();
    final recorder = ui.PictureRecorder();
    TimesheetDocumentPainter(
      document: document,
      layout: layout,
      face: const TextStyle(),
      words: timesheetWordsIn(AppLanguage.ja),
      // The form alone, on no paper: what is inked is what it prints.
      layers: const {SheetPaintLayer.form},
    ).paint(ui.Canvas(recorder), size);
    final picture = recorder.endRecording();
    final rgba = (await tester.runAsync(() async {
      final image = await picture.toImage(width, size.height.ceil());
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    }))!;
    picture.dispose();

    /// The pixels of [page]'s first gutter, every row of its half.
    List<int> gutter(int page) {
      final right = layout.halfLeft(page, 0).floor();
      final left =
          right - TimesheetDocumentLayout.frameNumberGutterWidth.ceil();
      final top = layout.halfRowsTop(page).floor();
      final bottom =
          top + layout.halfRowCount(0) * TimesheetDocumentLayout.rowHeight;
      return [
        for (var y = top; y < bottom; y += 1)
          for (var x = left; x < right; x += 1)
            for (var channel = 0; channel < 4; channel += 1)
              rgba[(y * width + x) * 4 + channel],
      ];
    }

    final first = gutter(0);
    final second = gutter(1);
    var inked = 0;
    for (var alpha = 3; alpha < first.length; alpha += 4) {
      if (first[alpha] != 0) {
        inked += 1;
      }
    }
    expect(inked, greaterThan(0), reason: 'LIVENESS: the gutter prints');
    expect(second.length, first.length);
    var differing = 0;
    for (var index = 0; index < first.length; index += 1) {
      if (second[index] != first[index]) {
        differing += 1;
      }
    }
    expect(
      differing,
      0,
      reason: 'the second sheet counts from its own first frame',
    );
  });
}

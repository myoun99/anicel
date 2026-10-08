import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_metadata.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_words_in.dart';

/// 🗣️F-301 (유저 2026-10-05): 「타임시트의 메모란은 페이지별로 다름. 지금
/// 1페이지에 적은게 2,3페이지 등등 적용되있는데, 페이지별로 독립」 — each
/// page's memo band prints that page's memo, and no other's.
void main() {
  TimesheetDocumentLayout layoutWith(List<String> notes) =>
      TimesheetDocumentLayout(
        document: TimesheetDocument.fromCut(
          cut: Cut(
            id: const CutId('c'),
            name: '1',
            layers: const [],
            duration: 200,
            canvasSize: const CanvasSize(width: 1920, height: 1080),
            metadata: CutMetadata(pageNotes: notes),
          ),
          projectName: 'P',
          fps: 24,
        ),
      );

  testWidgets('a page\'s memo prints in its own band alone', (tester) async {
    final empty = layoutWith(const []);
    expect(empty.pageIndexes, [0, 1], reason: '⛔전제: two pages');
    final size = empty.documentSize;
    final width = size.width.ceil();

    /// The bytes [layout]'s sheet paints inside page [page]'s memo band.
    Future<Uint8List> band(TimesheetDocumentLayout layout, int page) async {
      final recorder = ui.PictureRecorder();
      TimesheetDocumentPainter(
        words: timesheetWordsIn(AppLanguage.en),
        document: layout.document,
        layout: layout,
        face: const TextStyle(),
      ).paint(ui.Canvas(recorder), size);
      final picture = recorder.endRecording();
      final pixels = (await tester.runAsync(() async {
        final image = await picture.toImage(width, size.height.ceil());
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        image.dispose();
        return data!;
      }))!;
      picture.dispose();
      final rect = layout.memoBandRect(page);
      return Uint8List.fromList([
        for (var y = rect.top.ceil(); y < rect.bottom.floor(); y += 1)
          ...pixels.buffer.asUint8List(
            (y * width + rect.left.ceil()) * 4,
            (rect.right.floor() - rect.left.ceil()) * 4,
          ),
      ]);
    }

    final blank = [await band(empty, 0), await band(empty, 1)];
    final first = layoutWith(const ['One']);
    final second = layoutWith(const ['', 'Two']);

    expect(await band(first, 0), isNot(blank[0]), reason: '⛔CONTROL');
    expect(
      await band(first, 1),
      blank[1],
      reason: 'the first page\'s memo is not the second\'s',
    );
    expect(
      await band(second, 0),
      blank[0],
      reason: 'the second page\'s memo is not the first\'s',
    );
    expect(await band(second, 1), isNot(blank[1]));
  });
}

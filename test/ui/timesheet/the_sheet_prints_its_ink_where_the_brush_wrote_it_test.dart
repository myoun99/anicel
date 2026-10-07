import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/timesheet/timesheet_words_in.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/timesheet_ink_keys.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_layer.dart';

/// The timesheet prints its saved ink where the brush wrote it — through
/// the windows the brush writes through ([timesheetInkWindows]), each
/// window's surface laid by the one placement every sheet reads.
///
/// A page's ink is that page's paper (F-252): a pixel of it prints on the
/// paper where it was written, and on no other page.
void main() {
  const cutId = CutId('c');
  final document = TimesheetDocument.fromCut(
    cut: Cut(
      id: cutId,
      name: '1',
      layers: const [],
      duration: 288,
      canvasSize: const CanvasSize(width: 1920, height: 1080),
    ),
    projectName: 'P',
    fps: 24,
  );
  final layout = TimesheetDocumentLayout(document: document);

  testWidgets('a stroke on a page prints where it was written on that '
      'page, and nowhere on the next', (tester) async {
    expect(layout.pageIndexes, [0, 1], reason: 'fixture: two pages');
    // A square in the ink's pixels — the paper's
    // ([TimesheetDocumentLayout.paperScale]) — 200 × 300 into the page.
    const written = Offset(200, 300);
    const side = 10.0;
    final scale = layout.paperScale;
    final ink = (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(
        Rect.fromLTWH(
          written.dx * scale,
          written.dy * scale,
          side * scale,
          side * scale,
        ),
        Paint()..color = const Color(0xFFFF0000),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(
        ((written.dx + side) * scale).ceil(),
        ((written.dy + side) * scale).ceil(),
      );
      picture.dispose();
      return image;
    }))!;
    addTearDown(ink.dispose);

    final first = timesheetInkPageKey(cutId, 0);
    final windows = timesheetInkWindows(layout: layout, cutId: cutId);
    final size = layout.documentSize;
    final stride = size.width.ceil();
    // The red channel [at] on the sheet's ink stratum, with [live] keys
    // shown by a live brush window instead.
    Future<int Function(Offset at)> printed({
      Set<BrushFrameKey> live = const {},
    }) async {
      final recorder = ui.PictureRecorder();
      TimesheetDocumentPainter(
        words: timesheetWordsIn(AppLanguage.en),
        document: document,
        layout: layout,
        face: const TextStyle(),
        layers: const {SheetPaintLayer.ink},
        ink: [for (final window in windows) window.mark],
        inkImageFor: (key) => key == first ? ink : null,
        liveInkKeys: live,
      ).paint(ui.Canvas(recorder), size);
      final drawn = recorder.endRecording();
      final pixels = (await tester.runAsync(() async {
        final image = await drawn.toImage(stride, size.height.ceil());
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        image.dispose();
        return data!;
      }))!;
      drawn.dispose();
      return (Offset at) =>
          pixels.getUint8((at.dy.round() * stride + at.dx.round()) * 4);
    }

    const middle = Offset(side / 2, side / 2);
    final onFirst = layout.pageRect(0).topLeft + written + middle;
    final red = await printed();
    expect(red(onFirst), 255, reason: 'where the brush wrote it');
    expect(
      red(layout.pageRect(1).topLeft + written + middle),
      0,
      reason: 'the next page\'s paper is its own',
    );
    expect(
      (await printed(live: {first}))(onFirst),
      0,
      reason: 'a window a live brush view shows is its own: the baked ink '
          'stands down, or translucent ink composites twice',
    );
  });
}

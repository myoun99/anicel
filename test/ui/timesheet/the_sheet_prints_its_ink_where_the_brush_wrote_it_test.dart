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
/// A page's two halves share ONE band surface: the right half shows its
/// lower rows. A printer that laid every surface from its window's corner
/// would print a stroke written on the right half's 9th row nowhere at all
/// — past the left window's foot, above the right window's head.
void main() {
  const cutId = CutId('c');
  final document = TimesheetDocument.fromCut(
    cut: Cut(
      id: cutId,
      name: '1',
      layers: const [],
      duration: 144,
      canvasSize: const CanvasSize(width: 1920, height: 1080),
    ),
    projectName: 'P',
    fps: 24,
  );
  final layout = TimesheetDocumentLayout(document: document);
  const row = TimesheetDocumentLayout.rowHeight;

  testWidgets('a stroke on the band\'s 81st row prints on the RIGHT half\'s '
      '9th row, and nowhere on the left', (tester) async {
    expect(document.halfFrameCount, 72, reason: 'fixture: two halves of 72');
    // The band's surface down to frame 81, a stroke across frame 80's row.
    const width = 40;
    const height = (81 * row * timesheetInkScale) ~/ 1;
    final ink = (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(
        const Rect.fromLTWH(
          0,
          80 * row * timesheetInkScale,
          width * 1.0,
          row * timesheetInkScale,
        ),
        Paint()..color = const Color(0xFFFF0000),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(width, height);
      picture.dispose();
      return image;
    }))!;
    addTearDown(ink.dispose);

    final band = timesheetInkStripKey(cutId, 0);
    final windows = timesheetInkWindows(
      layout: layout,
      pagedLayout: layout,
      cutId: cutId,
    );
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
        inkImageFor: (key) => key == band ? ink : null,
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

    final y = layout.halfRowsTop(0) + 8 * row + row / 2;
    final right = Offset(layout.halfLeft(0, 1) + 5, y);
    final red = await printed();
    expect(
      red(right),
      255,
      reason: 'the right half shows the band from its 73rd row',
    );
    expect(
      red(Offset(layout.halfLeft(0, 0) + 5, y)),
      0,
      reason: 'the left half shows the band\'s first 72 rows',
    );
    expect(
      (await printed(live: {band}))(right),
      0,
      reason: 'a window a live brush view shows is its own: the baked ink '
          'stands down, or translucent ink composites twice',
    );
  });
}

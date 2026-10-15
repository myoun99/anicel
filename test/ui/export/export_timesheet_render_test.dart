import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show TextStyle;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/models/timesheet_ink_keys.dart';
import 'package:anicel/src/ui/export/export_timesheet_render.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_layer.dart';
import 'package:anicel/src/ui/timesheet/timesheet_words_in.dart';

import '../../helpers/cel_photo_fixture.dart';
import '../../helpers/checker_sampling.dart';

void main() {
  Frame frame(String id) =>
      Frame(id: FrameId(id), duration: 1, strokes: const []);

  (TimesheetDocument, TimesheetDocumentLayout) sheet({int duration = 300}) {
    final cut = Cut(
      id: const CutId('cut'),
      name: 'CUT1',
      duration: duration,
      canvasSize: const CanvasSize(width: 8, height: 8),
      layers: [
        Layer(
          id: const LayerId('a'),
          name: 'A',
          frames: [frame('f1'), frame('f2')],
        ),
        createCameraLayer(cutId: const CutId('cut')),
      ],
    );
    final document = TimesheetDocument.fromCut(
      cut: cut,
      projectName: 'Project',
      fps: 24,
      info: TimesheetInfo.empty,
    );
    return (document, TimesheetDocumentLayout(document: document));
  }

  testWidgets('a long cut splits into pages; each renders at scale and '
      'differs from its neighbor', (tester) async {
    await tester.runAsync(() async {
      // 300 frames @24 with 6s pages = 144/page → 3 pages.
      final (document, layout) = sheet();
      expect(document.pages.length, 3);

      Future<ui.Image> page(int index) => renderTimesheetPageImage(
        face: const TextStyle(),
        document: document,
        layout: layout,
        pageIndex: index,
        words: timesheetWordsIn(AppLanguage.en),
      );

      // F-294 (유저 2026-10-05: 「최신빌드로 시트 출력하면 1113x1574인데? …
      // 1x하더라도 100%크기인채로 출력해야」): at 1x a page is its paper's
      // own pixels — the panel's 100% — not the form's units.
      final first = await page(0);
      expect(layout.pageRect(0).width.round(), 1113, reason: 'fixture');
      expect(first.width, 1754);
      expect(first.height, 2480);

      final second = await page(1);
      final firstBytes = (await first.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      final secondBytes = (await second.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      expect(firstBytes, isNot(equals(secondBytes)),
          reason: 'page 2 carries different rows/numbers');

      // Ink exists: the page is not blank paper alone.
      var nonPaper = 0;
      for (var i = 0; i < firstBytes.length; i += 4) {
        if (firstBytes[i] < 200 || firstBytes[i + 1] < 200) {
          nonPaper += 1;
        }
      }
      expect(nonPaper, greaterThan(100));

      // An explicit output size WINS over the paper's — the sheet and the
      // conte page answer this the same way, and the preview relies on it
      // to raster a thumbnail at a size it chose.
      final forced = await renderTimesheetPageImage(
        face: const TextStyle(),
        document: document,
        layout: layout,
        pageIndex: 0,
        words: timesheetWordsIn(AppLanguage.en),
        outputSize: const CanvasSize(width: 64, height: 40),
      );
      expect(forced.width, 64);
      expect(forced.height, 40);

      first.dispose();
      second.dispose();
      forced.dispose();
    });
  });

  testWidgets('a photo on a page\'s ink prints from its file, sampled for '
      'the pixels the page is rendered at — the screen\'s law (I-97)', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final (document, layout) = sheet();
      final key = timesheetInkPageKey(const CutId('cut'), 0);
      final window = timesheetInkWindows(
        layout: layout,
        cutId: const CutId('cut'),
      ).firstWhere((window) => window.key == key);
      final placement = window.placement;
      final page = layout.pageRect(0);
      final middle = placement.pixelOf(page.center);
      final file = await checkerImage(16);
      addTearDown(file.dispose);

      /// The reds about the photo, the page rendered at [size] of its
      /// paper's pixels and a pixel of the file [perPixel] of them.
      Future<List<int>> printed({
        required double size,
        required double perPixel,
      }) async {
        // The image's pixels to a unit of the sheet.
        final perUnit = 1754 * size / page.width;
        final photo = photoOf(
          1,
          center: CanvasPoint(x: middle.dx, y: middle.dy),
          size: const CanvasSize(width: 16, height: 16),
          scale: perPixel * placement.scale / perUnit,
        );
        final rendered = await renderTimesheetPageImage(
          face: const TextStyle(),
          document: document,
          layout: layout,
          pageIndex: 0,
          words: timesheetWordsIn(AppLanguage.en),
          outputSize: CanvasSize(
            width: (1754 * size).round(),
            height: (2480 * size).round(),
          ),
          ink: (
            windows: [window.mark],
            rasterFor: (asked) => null,
            photosFor: (asked) => [if (asked == key) photo],
          ),
          imageFor: (path) => path == photo.reference.assetPath ? file : null,
        );
        try {
          final shown = (page.center - page.topLeft) * perUnit;
          return await redsAround(rendered, shown.dx.round(), shown.dy.round());
        } finally {
          rendered.dispose();
        }
      }

      // Either side of the display law's line, one: a scale handed in a
      // quarter wrong crosses it.
      final full = await printed(size: 1, perPixel: 1.25);
      expect(full, containsAll([0, 255]), reason: 'LIVENESS: the file');
      expect(
        full.every(isPure),
        isTrue,
        reason: 'a pixel of the file over one of the page\'s: hard-edged',
      );
      expect(
        (await printed(size: 0.5, perPixel: 0.75)).any(isGrey),
        isTrue,
        reason: 'under one: smoothed',
      );
    });
  });
}

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_cut_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/ui/export/export_timesheet_render.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_notation.dart';

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
        document: document,
        layout: layout,
        pageIndex: index,
        notation: TimesheetNotation.english,
        scale: 1,
      );

      final first = await page(0);
      final rect = layout.pageRect(0);
      expect(first.width, rect.width.round());
      expect(first.height, rect.height.round());

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

      final scaled = await renderTimesheetPageImage(
        document: document,
        layout: layout,
        pageIndex: 0,
        notation: TimesheetNotation.english,
        scale: 2,
      );
      expect(scaled.width, rect.width.round() * 2);

      first.dispose();
      second.dispose();
      scaled.dispose();
    });
  });
}

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';

/// 🚨THE TIMESHEET'S FORM LIES ON A SHEET OF PAPER (F-294, 유저 2026-10-05:
/// 「타임시트 용지패널 용지크기 너무 작음 … 1754x2480을 기본으로 할것」 ·
/// 「이런 패널들은 사이즈 생각할때 dpi를 기준으로 생각할거야」).
///
/// The form is measured in units of its own — a frame row is 18 — and its
/// paper is a size in PIXELS: every page is that paper, whatever the sheet
/// prints, and the form lies on it as large as fits, centred.
/// ↩️The form was the paper, 1096×1574 on a 24fps sheet, shown a unit a
/// pixel.
void main() {
  TimesheetDocument document({required int fps, int duration = 150}) =>
      TimesheetDocument.fromCut(
        cut: Cut(
          id: const CutId('cut-1'),
          name: 'Cut 1',
          layers: const [],
          duration: duration,
          canvasSize: const CanvasSize(width: 1280, height: 720),
        ),
        projectName: 'Project',
        fps: fps,
      );

  // A form that fills the paper's height (24fps, the sheet the user wrote
  // the size for), a taller one (30fps: 90 rows a half) and one that fills
  // its width (12fps: 36 rows a half).
  const rates = [24, 30, 12];

  test('a 24fps sheet\'s form is 1096×1574 of its own units — the paper it '
      'once was — and a unit of it is 2480/1574 of the paper\'s pixels: a '
      'frame row 28 pixels tall where it was 18', () {
    final layout = TimesheetDocumentLayout(document: document(fps: 24));

    expect(layout.formWidth, 1096);
    expect(layout.formHeight, 1574);
    expect(layout.paperScale, 2480 / 1574);
    expect(
      TimesheetDocumentLayout.rowHeight * layout.paperScale,
      closeTo(28.36, 0.01),
    );
  });

  test('every page is the paper — 1754×2480 pixels — whatever the sheet '
      'prints', () {
    for (final fps in rates) {
      final layout = TimesheetDocumentLayout(document: document(fps: fps));
      expect(
        layout.paperPixelSize,
        const CanvasSize(width: 1754, height: 2480),
      );
      for (final page in layout.visiblePageIndexes) {
        final paper = layout.pageRect(page);
        expect(
          paper.width * layout.paperScale,
          closeTo(1754, 1e-6),
          reason: '$fps fps, page $page',
        );
        expect(
          paper.height * layout.paperScale,
          closeTo(2480, 1e-6),
          reason: '$fps fps, page $page',
        );
      }
    }
  });

  test('the form stands whole on its page, centred, filling one side of it '
      '— and everything the sheet prints lies inside the form', () {
    const padding = TimesheetDocumentLayout.pagePadding;
    for (final fps in rates) {
      final layout = TimesheetDocumentLayout(document: document(fps: fps));
      final reason = '$fps fps';
      final paper = layout.pageRect(0);
      final form = layout.formRect(0);

      expect(form.size, Size(layout.formWidth, layout.formHeight));
      final left = form.left - paper.left;
      final top = form.top - paper.top;
      expect(left, greaterThanOrEqualTo(0), reason: reason);
      expect(top, greaterThanOrEqualTo(0), reason: reason);
      expect(paper.right - form.right, closeTo(left, 1e-9), reason: reason);
      expect(paper.bottom - form.bottom, closeTo(top, 1e-9), reason: reason);
      expect(math.min(left, top), 0, reason: '$reason: it fills one side');
      expect(math.max(left, top), greaterThan(1), reason: '$reason: fixture');

      // The header band, the strips and the rows, inside the padding.
      final header = layout.headerBandRect(0);
      expect(
        header.left,
        form.left + padding + TimesheetDocumentLayout.frameNumberGutterWidth,
        reason: reason,
      );
      expect(header.top, form.top + padding, reason: reason);
      expect(header.right, closeTo(form.right - padding, 1e-9), reason: reason);
      final lastStrip = layout.halfStrips.last.half;
      expect(
        layout.halfLeft(0, lastStrip) + layout.halfWidth,
        closeTo(form.right - padding, 1e-9),
        reason: reason,
      );
      expect(layout.halfLeft(0, 0), header.left, reason: reason);
      expect(
        layout.halfRowsTop(0) +
            layout.halfRowCount(0) * TimesheetDocumentLayout.rowHeight,
        closeTo(form.bottom - padding, 1e-9),
        reason: reason,
      );
    }
  });

  test('which side the form fills: the height on a 24fps sheet, the width '
      'on a 12fps one', () {
    final tall = TimesheetDocumentLayout(document: document(fps: 24));
    expect(tall.formRect(0).top, tall.pageRect(0).top);
    expect(tall.formRect(0).left, greaterThan(tall.pageRect(0).left));

    final short = TimesheetDocumentLayout(document: document(fps: 12));
    expect(short.formRect(0).left, short.pageRect(0).left);
    expect(short.formRect(0).top, greaterThan(short.pageRect(0).top));
  });

  test('the view toggle moves nothing on the paper: the one strip keeps the '
      'page\'s width, its form the page form\'s corner, and the paper its '
      'pixels a unit', () {
    for (final fps in rates) {
      final sheet = document(fps: fps);
      final paged = TimesheetDocumentLayout(document: sheet);
      final strip = TimesheetDocumentLayout(document: sheet, continuous: true);
      final reason = '$fps fps';

      expect(strip.paperScale, paged.paperScale, reason: reason);
      expect(strip.paperWidth, paged.paperWidth, reason: reason);
      expect(strip.formWidth, paged.formWidth, reason: reason);
      expect(
        strip.formRect(0).topLeft,
        paged.formRect(0).topLeft,
        reason: reason,
      );
      expect(strip.headerBandRect(0), paged.headerBandRect(0), reason: reason);
      expect(strip.memoBandRect(0), paged.memoBandRect(0), reason: reason);
      // The strip's paper keeps the margin the page has over and under its
      // form.
      final over = strip.formRect(0).top - strip.pageRect(0).top;
      expect(
        strip.pageRect(0).bottom - strip.formRect(0).bottom,
        closeTo(over, 1e-9),
        reason: reason,
      );
      expect(
        strip.formHeight,
        paged.formHeight +
            (sheet.rowCount - paged.halfRowCount(0)) *
                TimesheetDocumentLayout.rowHeight,
        reason: '$reason: the strip is every row long',
      );
    }
  });
}

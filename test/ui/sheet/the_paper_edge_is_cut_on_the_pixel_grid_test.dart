@Tags(['impeller'])
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timesheet/timesheet_words_in.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/envelope/cut_envelope_layout.dart';
import 'package:anicel/src/models/envelope/cut_envelope_presets.dart';
import 'package:anicel/src/models/envelope/cut_envelope_source.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/ui/canvas/viewport_canvas_transform.dart';
import 'package:anicel/src/ui/conte/conte_page_painter.dart';
import 'package:anicel/src/ui/conte/conte_sheet_builder.dart';
import 'package:anicel/src/ui/conte/conte_words_in.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';

/// 🚨F-179 — A SHEET'S PAPER HAS NO LINE AROUND IT.
///
/// 유저 2026-09-25: 「타임시트 용지? 다른용지도 그런데 용지 외곽에 반투명
/// 라인 있는데 이런거 필요없어」. Two things drew it: every sheet filled its
/// paper anti-aliased, so an edge landing inside a device pixel covered that
/// pixel partly — paper blended over the backdrop, one pixel wide — and the
/// timesheet stroked a 1.4px border on the page edge on top.
///
/// The law ([paintSheetPaper]): the paper is cut on the pixel centres, the
/// way F-67 cuts the drawing canvas's — every device pixel along the edge is
/// wholly paper or wholly not, and nothing is drawn over the edge.
///
/// ⚠️The view is chosen so the edges under test really are fractional; the
/// test refuses to run on a whole edge, which is cut the same with or
/// without anti-aliasing and would pass on nothing.
///
/// ⚠️ON IMPELLER (the tag): Skia honours `isAntiAlias = false`, so there
/// this passes with no cut at all; Impeller blends the edge it is handed.
void main() {
  // Fractional on purpose: the edges below land inside device pixels.
  const zoom = 0.37;
  final view = renderSnappedViewport(
    CanvasViewport(zoom: zoom, panX: 11, panY: 7),
    1.0,
  );
  const transparent = [0, 0, 0, 0];

  /// [painter] at [size], [scale] pixels to a unit on the canvas it is handed
  /// — as an export lays it — and [ratio] past that canvas, as the screen
  /// does: its own transform never sees that one.
  Future<Uint8List> rasterize(
    CustomPainter painter,
    Size size, {
    double scale = 1,
    double ratio = 1,
  }) async {
    final recorder = ui.PictureRecorder();
    final pixels = size * scale * ratio;
    painter.paint(
      Canvas(recorder, Offset.zero & size * scale)..scale(scale),
      size,
    );
    final recorded = recorder.endRecording();
    final screen = ui.PictureRecorder();
    Canvas(screen)
      ..scale(ratio)
      ..drawPicture(recorded);
    recorded.dispose();
    final picture = screen.endRecording();
    final image = await picture.toImage(
      pixels.width.round(),
      pixels.height.round(),
    );
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  List<int> rgbaAt(Uint8List rgba, int width, int x, int y) {
    final i = (y * width + x) * 4;
    return [rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3]];
  }

  /// The device pixels either side of the page's RIGHT and BOTTOM edges —
  /// the two a whole-pixel pan leaves fractional — away from the corners:
  /// each must be exactly the paper where its centre is on the paper, and
  /// exactly nothing where it is not.
  void expectCutOnTheGrid(
    Uint8List rgba,
    Size size, {
    required Rect page,
    required List<int> paper,
    required String sheet,
  }) {
    final width = size.width.round();
    for (final edge in [page.right, page.bottom]) {
      expect(
        edge - edge.floorToDouble(),
        isNot(0),
        reason:
            '$sheet: edge $edge is whole — the fixture no longer exercises '
            'the fractional cut',
      );
    }
    for (
      var y = (page.top + 12).ceil();
      y < page.bottom - 12;
      y += 5
    ) {
      for (var x = page.right.floor() - 2; x <= page.right.floor() + 2; x++) {
        expect(
          rgbaAt(rgba, width, x, y),
          x + 0.5 < page.right ? paper : transparent,
          reason: '$sheet: device pixel ($x, $y), right edge at ${page.right}',
        );
      }
    }
    for (
      var x = (page.left + 12).ceil();
      x < page.right - 12;
      x += 5
    ) {
      for (
        var y = page.bottom.floor() - 2;
        y <= page.bottom.floor() + 2;
        y++
      ) {
        expect(
          rgbaAt(rgba, width, x, y),
          y + 0.5 < page.bottom ? paper : transparent,
          reason:
              '$sheet: device pixel ($x, $y), bottom edge at ${page.bottom}',
        );
      }
    }
  }

  /// [documentRect] in paper units, where the snapped view lands it — on
  /// the device, at [ratio].
  Rect onScreen(
    Rect documentRect, {
    CanvasViewport? through,
    double ratio = 1,
  }) {
    final at = through ?? view;
    return Rect.fromLTRB(
      (at.panX + at.zoom * documentRect.left) * ratio,
      (at.panY + at.zoom * documentRect.top) * ratio,
      (at.panX + at.zoom * documentRect.right) * ratio,
      (at.panY + at.zoom * documentRect.bottom) * ratio,
    );
  }

  const layers = {SheetPaintLayer.paper, SheetPaintLayer.form};

  testWidgets('the timesheet page — no border stroked on its edge', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final project = createDefaultProject();
      final document = TimesheetDocument.fromCut(
        cut: project.tracks.first.cuts.first,
        projectName: project.name,
        fps: 24,
      );
      final layout = TimesheetDocumentLayout(document: document);
      final page = onScreen(layout.pageRect(0));
      final size = Size(page.right + 16, page.bottom + 16).ceilToSize();
      final rgba = await rasterize(
        TimesheetDocumentPainter(
          words: timesheetWordsIn(AppLanguage.en),
          document: document,
          layout: layout,
          face: const TextStyle(),
          viewport: view,
          layers: layers,
        ),
        size,
      );
      expectCutOnTheGrid(
        rgba,
        size,
        page: page,
        paper: const [255, 255, 255, 255],
        sheet: 'timesheet',
      );
    });
  });

  testWidgets("at a ratio the grid is the device's: a canvas unit is not a "
      'pixel', (tester) async {
    await tester.runAsync(() async {
      const ratio = 1.5;
      final view = renderSnappedViewport(
        CanvasViewport(zoom: zoom, panX: 11, panY: 7),
        ratio,
      );

      final project = createDefaultProject();
      final document = TimesheetDocument.fromCut(
        cut: project.tracks.first.cuts.first,
        projectName: project.name,
        fps: 24,
      );
      final layout = TimesheetDocumentLayout(document: document);
      final page = onScreen(layout.pageRect(0), through: view, ratio: ratio);
      final pixels = Size(page.right + 16, page.bottom + 16).ceilToSize();
      expectCutOnTheGrid(
        await rasterize(
          TimesheetDocumentPainter(
            words: timesheetWordsIn(AppLanguage.en),
            document: document,
            layout: layout,
            face: const TextStyle(),
            viewport: view,
            effectiveRatio: ratio,
            layers: layers,
          ),
          pixels / ratio,
          ratio: ratio,
        ),
        pixels,
        page: page,
        paper: const [255, 255, 255, 255],
        sheet: 'timesheet',
      );

      // 1925: the right edge stands at 723.58 units, 1085.4 pixels — cut on
      // units it lands a pixel out, at 1086. At most widths the two round
      // alike, and the sheet passes on nothing.
      for (final form in CutEnvelopePresets.all) {
        final envelope = CutEnvelopeLayout.fit(
          form: form,
          paperWidth: 1925,
          paperHeight: 1925 / form.aspectRatio,
        );
        final sheet = onScreen(
          Rect.fromLTWH(0, 0, envelope.paperWidth, envelope.paperHeight),
          through: view,
          ratio: ratio,
        );
        final room = Size(sheet.right + 16, sheet.bottom + 16).ceilToSize();
        final paper = Color(form.paperArgb);
        expectCutOnTheGrid(
          await rasterize(
            CutEnvelopePainter(
              layout: envelope,
              source: const CutEnvelopeSource(),
              face: const TextStyle(),
              viewport: view,
              effectiveRatio: ratio,
              layers: layers,
            ),
            room / ratio,
            ratio: ratio,
          ),
          room,
          page: sheet,
          paper: [
            (paper.r * 255).round(),
            (paper.g * 255).round(),
            (paper.b * 255).round(),
            (paper.a * 255).round(),
          ],
          sheet: 'envelope ${form.id}',
        );
      }
    });
  });

  testWidgets('with no view, as an export, the canvas lands the page on its '
      'pixels: the ratio it says is not a second one', (tester) async {
    await tester.runAsync(() async {
      const ratio = 1.37;
      final project = createDefaultProject();
      final document = TimesheetDocument.fromCut(
        cut: project.tracks.first.cuts.first,
        projectName: project.name,
        fps: 24,
      );
      final layout = TimesheetDocumentLayout(document: document);
      final rect = layout.pageRect(0);
      final page = Rect.fromLTRB(
        rect.left * ratio,
        rect.top * ratio,
        rect.right * ratio,
        rect.bottom * ratio,
      );
      final pixels = Size(page.right + 16, page.bottom + 16).ceilToSize();
      expectCutOnTheGrid(
        await rasterize(
          TimesheetDocumentPainter(
            words: timesheetWordsIn(AppLanguage.en),
            document: document,
            layout: layout,
            face: const TextStyle(),
            effectiveRatio: ratio,
            layers: layers,
          ),
          pixels / ratio,
          scale: ratio,
        ),
        pixels,
        page: page,
        paper: const [255, 255, 255, 255],
        sheet: 'timesheet',
      );
    });
  });

  testWidgets('the conte page', (tester) async {
    await tester.runAsync(() async {
      final source = buildConteSheetSource(createDefaultProject());
      final pages = layoutConteSheet(
        source,
        metrics: const ConteSheetMetrics(cameraAspect: 16 / 9),
      );
      final metrics = pages.first.metrics;
      final page = onScreen(
        Rect.fromLTWH(0, 0, metrics.pageWidth, metrics.pageHeight),
      );
      final size = Size(page.right + 16, page.bottom + 16).ceilToSize();
      final rgba = await rasterize(
        ContePagePainter(
          page: pages.first,
          source: source,
          words: conteWordsIn(AppLanguage.ja),
          viewport: view,
          layers: layers,
        ),
        size,
      );
      expectCutOnTheGrid(
        rgba,
        size,
        page: page,
        paper: const [255, 255, 255, 255],
        sheet: 'conte',
      );
    });
  });

  testWidgets('the cut envelope', (tester) async {
    await tester.runAsync(() async {
      for (final form in CutEnvelopePresets.all) {
        final layout = CutEnvelopeLayout.fit(
          form: form,
          paperWidth: 1920,
          paperHeight: 1920 / form.aspectRatio,
        );
        final page = onScreen(
          Rect.fromLTWH(0, 0, layout.paperWidth, layout.paperHeight),
        );
        final size = Size(page.right + 16, page.bottom + 16).ceilToSize();
        final rgba = await rasterize(
          CutEnvelopePainter(
            layout: layout,
            source: const CutEnvelopeSource(),
            face: const TextStyle(),
            viewport: view,
            layers: layers,
          ),
          size,
        );
        final paper = Color(form.paperArgb);
        expectCutOnTheGrid(
          rgba,
          size,
          page: page,
          paper: [
            (paper.r * 255).round(),
            (paper.g * 255).round(),
            (paper.b * 255).round(),
            (paper.a * 255).round(),
          ],
          sheet: 'envelope ${form.id}',
        );
      }
    });
  });
}

extension on Size {
  Size ceilToSize() => Size(width.ceilToDouble(), height.ceilToDouble());
}

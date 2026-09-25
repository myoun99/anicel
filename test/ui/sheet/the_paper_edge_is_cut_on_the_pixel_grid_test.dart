import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
void main() {
  // Fractional on purpose: the edges below land inside device pixels.
  const zoom = 0.37;
  final view = renderSnappedViewport(
    CanvasViewport(zoom: zoom, panX: 11, panY: 7),
    1.0,
  );
  const transparent = [0, 0, 0, 0];

  Future<Uint8List> rasterize(CustomPainter painter, Size size) async {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder, Offset.zero & size), size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      size.width.round(),
      size.height.round(),
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

  /// [documentRect] in paper units, where the snapped view lands it.
  Rect onScreen(Rect documentRect) => Rect.fromLTRB(
    view.panX + view.zoom * documentRect.left,
    view.panY + view.zoom * documentRect.top,
    view.panX + view.zoom * documentRect.right,
    view.panY + view.zoom * documentRect.bottom,
  );

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

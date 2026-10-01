import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/conte/conte_page_marks.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/conte/conte_sheet_source.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/ui/canvas/viewport_canvas_transform.dart';
import 'package:anicel/src/ui/conte/conte_page_painter.dart';
import 'package:anicel/src/ui/conte/conte_words_in.dart';

/// 🚨A PICTURE MEETS ITS WINDOW'S EDGE AT EVERY ZOOM (F-197).
///
/// 유저 2026-09-27: 「해당컷 채우기로 전면 검정색됫는데 콘티프리뷰패널에서
/// 줌하거나 팬할때 그림이랑 실루엣 경계에 흰 여백? 선이 생김」 · 「팬은
/// 아니고 줌할때마다 생김. 그상태로고정」. A black picture in the black
/// silhouette leaves no light pixel anywhere across the edge between them,
/// whatever pixel a zoom puts that edge inside. The live picture over it
/// while the brush is on is pinned beside the panel's other live pins
/// (`a_picture_takes_the_pen_into_its_blocks_cel_test.dart`).
void main() {
  final source = ConteSheetSource(
    cuts: [
      ConteCutSource(
        cutId: const CutId('a'),
        name: '1',
        durationFrames: 24,
        cumulativeEndFrames: 24,
        cells: const [
          ConteCellSource(
            startFrame: 0,
            endFrameExclusive: 24,
            pictureFrame: 0,
          ),
        ],
      ),
    ],
  );
  final page = layoutConteSheet(source).single;
  final window = contePictureSlot(page.cells.single, page.metrics);

  testWidgets('a black picture in the black silhouette leaves no light pixel '
      'across any side of its window, at any zoom', (tester) async {
    await tester.runAsync(() async {
      final black = await _solid(640, 360, const Color(0xFF000000));
      final seams = <String>[];
      var scans = 0;
      for (final zoom in const [0.61, 0.83, 1.0, 1.37, 1.9, 2.46, 3.3]) {
        final view = renderSnappedViewport(
          CanvasViewport(zoom: zoom, panX: 11, panY: 7),
          1,
        );
        final shot = await _print(page, source, view, black);
        double x(double paper) => view.panX + view.zoom * paper;
        double y(double paper) => view.panY + view.zoom * paper;
        final midX = x(window.center.dx).round();
        final midY = y(window.center.dy).round();
        // Across each side: from the first pixel wholly inside the
        // silhouette's black — a zoomed-out border is only a few pixels
        // wide, and past it lies the white paper — to three pixels into the
        // picture.
        final border = page.metrics.silhouetteBorder;
        for (final (side, from, to, across) in [
          (
            'left',
            x(window.left - border).ceil(),
            x(window.left).floor() + 3,
            true,
          ),
          (
            'right',
            x(window.right).ceil() - 4,
            x(window.right + border).floor() - 1,
            true,
          ),
          (
            'top',
            y(window.top - border).ceil(),
            y(window.top).floor() + 3,
            false,
          ),
          (
            'bottom',
            y(window.bottom).ceil() - 4,
            y(window.bottom + border).floor() - 1,
            false,
          ),
        ]) {
          for (var d = from; d <= to; d += 1) {
            final value = across ? shot.red(d, midY) : shot.red(midX, d);
            scans += 1;
            if (value > 64) {
              seams.add('zoom $zoom, $side side, pixel $d: $value');
            }
          }
        }
      }
      black.dispose();
      expect(scans, greaterThan(100), reason: 'fixture: the edges are read');
      expect(seams, isEmpty);
    });
  });
}

/// A [width]×[height] picture of one colour — a cell whose whole frame is
/// that colour.
Future<ui.Image> _solid(int width, int height, Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

/// [page] printed through [view] at one device pixel a point of screen,
/// with [image] in every cell.
Future<_Shot> _print(
  ContePageLayout page,
  ConteSheetSource source,
  CanvasViewport view,
  ui.Image image,
) async {
  final m = page.metrics;
  final size = Size(
    (view.panX + view.zoom * m.pageWidth).ceilToDouble(),
    (view.panY + view.zoom * m.pageHeight).ceilToDouble(),
  );
  final recorder = ui.PictureRecorder();
  ContePagePainter(
    page: page,
    source: source,
    words: conteWordsIn(AppLanguage.ja),
    viewport: view,
    pictureFor: (_, _) => image,
  ).paint(Canvas(recorder, Offset.zero & size), size);
  final picture = recorder.endRecording();
  final shot = await picture.toImage(size.width.round(), size.height.round());
  picture.dispose();
  final bytes = (await shot.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  ))!.buffer.asUint8List();
  final width = shot.width;
  shot.dispose();
  return _Shot(bytes, width);
}

class _Shot {
  const _Shot(this.rgba, this.width);

  final Uint8List rgba;
  final int width;

  int red(int x, int y) => rgba[(y * width + x) * 4];
}

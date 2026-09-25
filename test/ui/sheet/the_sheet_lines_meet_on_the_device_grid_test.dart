import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/conte/conte_page_marks.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/conte/conte_sheet_source.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/sheet_marks.dart';
import 'package:anicel/src/ui/canvas/viewport_canvas_transform.dart';
import 'package:anicel/src/ui/conte/conte_page_painter.dart';
import 'package:anicel/src/ui/sheet_painting.dart';

/// 🚨THE HEAD'S LINES AND THE BODY'S EDGES LAND ON ONE DEVICE PIXEL.
///
/// 유저 2026-09-25, looking at the proposal: 「헤더의 사각형 실루엣 선이랑
/// 아래쪽 본문이랑 라인이 미묘하게 어긋나있거나 하는데 절대
/// 어긋나지않도록」. The marks put the two on one x ([contePageMarks]); this
/// is the other half — on screen that x goes through ONE rounding
/// ([SheetDeviceGrid]), so a rule's edge and a fill's edge cannot come out a
/// pixel apart, at any zoom, any pan, any monitor.
void main() {
  final source = ConteSheetSource(
    cuts: [
      ConteCutSource(
        cutId: const CutId('a'),
        name: '1',
        durationFrames: 24,
        cumulativeEndFrames: 24,
        cells: const [
          ConteCellSource(startFrame: 0, endFrameExclusive: 24, pictureFrame: 0),
        ],
      ),
    ],
  );
  final page = layoutConteSheet(source).single;
  final m = page.metrics;
  final marks = contePageMarks(page, source);
  final silhouette = marks
      .whereType<SheetFill>()
      .firstWhere((fill) => fill.argb == 0xFF101010)
      .rect;
  final rules = marks.whereType<SheetRule>().toList();
  final sides = [
    for (final rule in rules)
      if (rule.isUpright &&
          rule.rect.left >= m.pictureLeft &&
          rule.rect.right <= m.actionLeft)
        rule,
  ];
  final underside = rules.singleWhere(
    (rule) =>
        !rule.isUpright &&
        rule.rect.left == m.pictureLeft &&
        rule.rect.bottom == m.bodyTop,
  );
  final paper = Size(m.pageWidth, m.pageHeight);

  test('at every view the head\'s picture-column sides and underside meet '
      'the silhouette on its device pixel — a rule too thin to show is '
      'widened INSIDE, never across the black\'s edge', () {
    expect(sides, hasLength(2), reason: 'fixture: both sides of the column');
    var views = 0;
    for (final ratio in const [1.0, 1.25, 1.5, 1.75, 2.0, 3.0]) {
      for (final zoom in const [0.37, 0.5, 0.73, 1.0, 1.1, 1.46, 2.19, 3.3]) {
        for (final (panX, panY) in const [(11.0, 7.0), (13.3, 5.7)]) {
          final grid = SheetDeviceGrid.of(const Size(2000, 3000), (
            viewport: renderSnappedViewport(
              CanvasViewport(zoom: zoom, panX: panX, panY: panY),
              ratio,
            ),
            devicePixelRatio: ratio,
            paper: paper,
          ));
          final body = grid.snap(silhouette);
          final at = 'zoom $zoom, ratio $ratio, pan ($panX, $panY)';
          expect(
            grid.snapRule(sides.first).left,
            body.left,
            reason: 'left side at $at',
          );
          expect(
            grid.snapRule(sides.last).right,
            body.right,
            reason: 'right side at $at',
          );
          expect(
            grid.snapRule(underside).bottom,
            body.top,
            reason: 'underside at $at',
          );
          views += 1;
        }
      }
    }
    expect(views, 96);
  });

  test('every fill and rule edge lands ON a device pixel boundary', () {
    // A fill cut on the grid is one colour per pixel on any rasterizer; an
    // edge left inside a pixel is up to the backend's sampling — this test
    // runner's and the app's GPU renderer are not the same one.
    var edges = 0;
    for (final ratio in const [1.0, 1.25, 1.5, 3.0]) {
      final grid = SheetDeviceGrid.of(const Size(2000, 3000), (
        viewport: renderSnappedViewport(
          CanvasViewport(zoom: 1.37, panX: 11.3, panY: 7.9),
          ratio,
        ),
        devicePixelRatio: ratio,
        paper: paper,
      ));
      for (final mark in marks) {
        final cut = switch (mark) {
          SheetFill(:final rect) => grid.snap(rect),
          SheetRule() => grid.snapRule(mark),
          _ => null,
        };
        if (cut == null) {
          continue;
        }
        for (final edge in [cut.left, cut.top, cut.right, cut.bottom]) {
          final device = edge * ratio;
          expect(device, closeTo(device.roundToDouble(), 1e-6));
          edges += 1;
        }
      }
    }
    expect(edges, greaterThan(100), reason: 'fixture: the page has edges');
  });

  test('a rule never vanishes: zoomed far out it still covers a device '
      'pixel', () {
    final grid = SheetDeviceGrid.of(const Size(200, 300), (
      viewport: CanvasViewport(zoom: 0.05, panX: 3, panY: 3),
      devicePixelRatio: 1,
      paper: paper,
    ));
    for (final rule in marks.whereType<SheetRule>()) {
      final cut = grid.snapRule(rule);
      expect(cut.width, greaterThanOrEqualTo(1));
      expect(cut.height, greaterThanOrEqualTo(1));
    }
  });

  testWidgets('printed, the head\'s right side and the silhouette turn light '
      'at the same device column', (tester) async {
    await tester.runAsync(() async {
      // A fractional view: the edge falls inside a pixel.
      final view = renderSnappedViewport(
        CanvasViewport(zoom: 1.37, panX: 11, panY: 7),
        1,
      );
      final size = Size(
        (view.panX + view.zoom * m.pageWidth).ceilToDouble(),
        (view.panY + view.zoom * m.pageHeight).ceilToDouble(),
      );
      final recorder = ui.PictureRecorder();
      ContePagePainter(
        page: page,
        source: source,
        viewport: view,
      ).paint(Canvas(recorder, Offset.zero & size), size);
      final picture = recorder.endRecording();
      final image = await picture.toImage(
        size.width.round(),
        size.height.round(),
      );
      picture.dispose();
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      final width = image.width;
      image.dispose();

      int red(Uint8List rgba, int x, int y) => rgba[(y * width + x) * 4];

      /// The last dark column before the light, scanning right across the
      /// picture column's right edge on row [y].
      int lastDark(int y) {
        final from = (view.panX + view.zoom * (m.actionLeft - 4)).floor();
        final to = (view.panX + view.zoom * (m.actionLeft + 4)).ceil();
        var last = -1;
        for (var x = from; x <= to; x += 1) {
          if (red(bytes, x, y) < 128) {
            last = x;
          }
        }
        return last;
      }

      final headRow = (view.panY +
              view.zoom * (m.tableTop + m.headerRowHeight / 2))
          .round();
      final bodyRow = (view.panY + view.zoom * (m.bodyTop + m.rowHeight / 2))
          .round();
      expect(lastDark(headRow), isNot(-1), reason: 'the head\'s rule is there');
      expect(lastDark(headRow), lastDark(bodyRow));
    });
  });
}

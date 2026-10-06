import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/canvas/viewport_pages_painter.dart';

/// The pages a canvas-base panel shows as rasters — the media viewer's and
/// the export preview's one painter: each page drawn INTO where it lies,
/// through the view, over the ground its document stands on.
void main() {
  /// A flat [color] picture, [side] pixels square.
  Future<ui.Image> flat(Color color, int side) {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(color, BlendMode.src);
    return recorder.endRecording().toImage(side, side);
  }

  /// What the painter draws of one page on a 16×16 box, as straight RGBA.
  Future<Uint8List> painted(
    WidgetTester tester, {
    required ViewportPageGround ground,
    Rect page = const Rect.fromLTWH(0, 0, 12, 12),
    ui.Image? image,
    double zoom = 1,
  }) async {
    final bytes = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      ViewportPagesPainter(
        pages: [(rect: page, image: image)],
        ground: ground,
        viewport: CanvasViewport(zoom: zoom),
        effectiveRatio: 1,
      ).paint(Canvas(recorder), const Size(16, 16));
      final picture = await recorder.endRecording().toImage(16, 16);
      final data = await picture.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      picture.dispose();
      return data!.buffer.asUint8List();
    });
    return bytes!;
  }

  List<int> pixel(Uint8List bytes, int x, int y) =>
      bytes.sublist((y * 16 + x) * 4, (y * 16 + x) * 4 + 4);

  testWidgets('a page with no raster yet is its ground alone: nothing, '
      'white paper, or the transparency checker', (tester) async {
    final none = await painted(tester, ground: ViewportPageGround.none);
    expect(pixel(none, 1, 1), [0, 0, 0, 0]);

    final paper = await painted(tester, ground: ViewportPageGround.paper);
    expect(pixel(paper, 1, 1), [255, 255, 255, 255]);
    expect(pixel(paper, 9, 1), [255, 255, 255, 255]);
    expect(pixel(paper, 14, 14), [0, 0, 0, 0], reason: 'outside the page');

    // The canvas's own checker: cells of eight, white and grey.
    final checker = await painted(tester, ground: ViewportPageGround.checker);
    expect(pixel(checker, 1, 1), [255, 255, 255, 255]);
    expect(pixel(checker, 9, 1), [204, 204, 204, 255]);
    expect(pixel(checker, 9, 9), [255, 255, 255, 255]);
    expect(pixel(checker, 14, 14), [0, 0, 0, 0], reason: 'outside the page');
  });

  testWidgets('a raster is drawn INTO its page\'s rect, through the view', (
    tester,
  ) async {
    final red = await tester.runAsync(() => flat(const Color(0xFFFF0000), 2));
    addTearDown(red!.dispose);

    const page = Rect.fromLTWH(0, 0, 4, 4);
    final atOne = await painted(
      tester,
      ground: ViewportPageGround.none,
      page: page,
      image: red,
    );
    expect(pixel(atOne, 2, 2), [255, 0, 0, 255]);
    expect(pixel(atOne, 6, 6), [0, 0, 0, 0]);

    final atTwo = await painted(
      tester,
      ground: ViewportPageGround.none,
      page: page,
      image: red,
      zoom: 2,
    );
    expect(pixel(atTwo, 6, 6), [255, 0, 0, 255], reason: 'the view doubles it');
    expect(pixel(atTwo, 10, 10), [0, 0, 0, 0]);
  });
}

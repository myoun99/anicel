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

  /// What the painter draws on a 16×16 box, as straight RGBA.
  Future<Uint8List> painted(
    WidgetTester tester, {
    required ViewportPageGround ground,
    ui.Image? image,
    double zoom = 1,
  }) async {
    final bytes = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      ViewportPagesPainter(
        pages: [(rect: const Rect.fromLTWH(0, 0, 4, 4), image: image)],
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
    expect(pixel(paper, 8, 8), [0, 0, 0, 0], reason: 'outside the page');

    final checker = await painted(tester, ground: ViewportPageGround.checker);
    expect(pixel(checker, 1, 1)[3], 255, reason: 'the checker is opaque');
    expect(pixel(checker, 8, 8), [0, 0, 0, 0], reason: 'outside the page');
    expect(
      checker,
      isNot(paper),
      reason: 'a checker, not a sheet of white paper',
    );
  });

  testWidgets('a raster is drawn INTO its page\'s rect, through the view', (
    tester,
  ) async {
    final red = await tester.runAsync(() => flat(const Color(0xFFFF0000), 2));
    addTearDown(red!.dispose);

    final atOne = await painted(
      tester,
      ground: ViewportPageGround.none,
      image: red,
    );
    expect(pixel(atOne, 2, 2), [255, 0, 0, 255]);
    expect(pixel(atOne, 6, 6), [0, 0, 0, 0]);

    final atTwo = await painted(
      tester,
      ground: ViewportPageGround.none,
      image: red,
      zoom: 2,
    );
    expect(pixel(atTwo, 6, 6), [255, 0, 0, 255], reason: 'the view doubles it');
    expect(pixel(atTwo, 10, 10), [0, 0, 0, 0]);
  });
}

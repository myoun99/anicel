// THE PAPER IS PAINTED WHEN THE VIEW ASKS FOR IT, AND NOT WHEN IT DOES NOT —
// IN PIXELS, NOT IN A FLAG.
//
// The paint-pass cut (2026-09-03) was checked with a mutant that inverted
// the paper guard (`if (!paintPaper) return` → `if (paintPaper) return`),
// and every paper test stayed green: they read the view's `paintPaper`
// flag, and the one that reads pixels has ink over the whole page. This
// pin renders an EMPTY stack over a dark backdrop and counts the paper's
// own colour.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

void main() {
  const canvasSize = CanvasSize(width: 200, height: 100);
  const screen = Size(300, 200);
  // A colour no backdrop or default paper shares.
  const paperArgb = 0xFF3366CC;

  Future<CustomPainter> pump(WidgetTester tester, {required bool paper}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: screen.width,
            height: screen.height,
            child: CanvasLayerStackView(
              nodes: const [],
              imageCache: LayerFrameImageCache(frameStore: BrushFrameStore()),
              canvasSize: canvasSize,
              viewport: CanvasViewport(zoom: 1, panX: 0, panY: 0),
              paintPaper: paper,
              paperBackground: const ProjectBackground.color(paperArgb),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(CanvasLayerStackView),
            matching: find.byType(CustomPaint),
          ),
        )
        .where((paint) => paint.painter != null)
        .first
        .painter!;
  }

  Future<int> paperPixels(WidgetTester tester, CustomPainter painter) async {
    final bytes = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        Offset.zero & screen,
        Paint()..color = const Color(0xFF101010),
      );
      painter.paint(canvas, screen);
      final picture = recorder.endRecording();
      final image = picture.toImageSync(
        screen.width.round(),
        screen.height.round(),
      );
      picture.dispose();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    return _countColour(bytes!, paperArgb);
  }

  testWidgets('paintPaper: true puts the paper colour on the screen', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final painter = await pump(tester, paper: true);
    expect(await paperPixels(tester, painter), greaterThan(1000));
  });

  testWidgets('paintPaper: false leaves the backdrop bare', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final painter = await pump(tester, paper: false);
    expect(await paperPixels(tester, painter), 0);
  });
}

int _countColour(Uint8List rgba, int argb) {
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  var n = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    if (rgba[i] == r && rgba[i + 1] == g && rgba[i + 2] == b) {
      n += 1;
    }
  }
  return n;
}

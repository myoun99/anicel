import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/services/brush_frame_store.dart';

/// ㊱ — the ACTIVE layer's opacity on the editing canvas.
///
/// 유저 실기: 「레이어 불투명도 바꿨을 때 다른 레이어에서 보면 적용돼 있는데, 그
/// 레이어를 액티브로 하면 캔버스 그림이 100%가 됨」.
///
/// The value was never lost on the way in — the session computes it and the
/// node carries it. It stopped at the painter, which destructured everything
/// about the active node EXCEPT its alpha. The wrap that used to apply it
/// (`BrushCanvasPanel.interactiveContentOpacity`) cannot: in merged mode the
/// interactive view is input-only, so that wrap now dims a widget which
/// paints nothing.
void main() {
  const canvasSize = CanvasSize(width: 4, height: 4);

  /// One fully opaque red pixel at (0,0) — enough to read an alpha off.
  BitmapSurfacePainter redSurfacePainter() {
    var tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 4);
    tile = writeRgbaColorToBitmapTile(
      tile: tile,
      x: 0,
      y: 0,
      color: RgbaColor(r: 255, g: 0, b: 0, a: 255),
    );
    return BitmapSurfacePainter(
      surface: BitmapSurface(
        canvasSize: canvasSize,
        tileSize: 4,
        tiles: {tile.coord: tile},
      ),
      showTransparentBackground: false,
    );
  }

  /// The stack view's own painter, taken from the tree — the class is
  /// private, and [CustomPainter] is the whole surface this test needs
  /// (paint + shouldRepaint).
  Future<CustomPainter> pumpStack(
    WidgetTester tester, {
    required double opacity,
    required BitmapSurfacePainter surfacePainter,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 4,
              height: 4,
              child: CanvasLayerStackView(
                nodes: [CanvasActiveLayerNode(opacity: opacity)],
                imageCache: LayerFrameImageCache(frameStore: BrushFrameStore()),
                canvasSize: canvasSize,
                viewport: CanvasViewport(),
                activeSurfacePainter: surfacePainter,
              ),
            ),
          ),
        ),
      ),
    );
    final painted = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(CanvasLayerStackView),
            matching: find.byType(CustomPaint),
          ),
        )
        .where((paint) => paint.painter != null)
        .toList();
    expect(painted, isNotEmpty, reason: 'the stack view paints through one');
    return painted.first.painter!;
  }

  testWidgets('the live surface is drawn at the ROW opacity, not full', (
    tester,
  ) async {
    final surfacePainter = redSurfacePainter();

    final opaque = await pumpStack(
      tester,
      opacity: 1.0,
      surfacePainter: surfacePainter,
    );
    final faint = await pumpStack(
      tester,
      opacity: 0.25,
      surfacePainter: surfacePainter,
    );

    // ⚠️`toImage` is a REAL async round-trip through the engine: awaited
    // under the fake clock a widget test simply hangs (it did — ten
    // minutes of it). Rasterizing belongs inside `runAsync`.
    final opaqueAlpha = (await tester.runAsync(() => _paintAlphaAt(opaque)))!;
    final faintAlpha = (await tester.runAsync(() => _paintAlphaAt(faint)))!;

    expect(opaqueAlpha, 255, reason: 'a full row still paints solid');
    expect(
      faintAlpha,
      lessThan(120),
      reason:
          '㊱: 0.25 on the row must reach the canvas — the live surface used '
          'to draw at full strength while every other row honoured its '
          'slider (got $faintAlpha)',
    );
    expect(faintAlpha, greaterThan(0), reason: 'and it is not gone, just thin');
  });

  testWidgets('an opacity change alone must REPAINT', (tester) async {
    final surfacePainter = redSurfacePainter();

    final opaque = await pumpStack(
      tester,
      opacity: 1.0,
      surfacePainter: surfacePainter,
    );
    final faint = await pumpStack(
      tester,
      opacity: 0.25,
      surfacePainter: surfacePainter,
    );

    expect(
      faint.shouldRepaint(opaque),
      isTrue,
      reason:
          '㊱: a slider drag changes NOTHING else about this node. A gate '
          'that does not compare the alpha shows the new value only when '
          'some unrelated fact happens to move (the ㉘/㉞ shape)',
    );
  });
}

/// The alpha of the surface's one red pixel after [painter] draws.
Future<int?> _paintAlphaAt(CustomPainter painter) async {
  final recorder = ui.PictureRecorder();
  const size = Size(4, 4);
  final canvas = Canvas(recorder, Offset.zero & size);
  painter.paint(canvas, size);
  final image = await recorder.endRecording().toImage(4, 4);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final pixels = bytes!.buffer.asUint8List();
  return _alphaOfFirstInked(pixels);
}

/// The first non-transparent pixel's alpha — the surface lands at (0,0) but
/// the viewport transform is the widget's business, not this test's.
int? _alphaOfFirstInked(Uint8List pixels) {
  for (var offset = 0; offset + 3 < pixels.length; offset += 4) {
    if (pixels[offset + 3] != 0) {
      return pixels[offset + 3];
    }
  }
  return null;
}
